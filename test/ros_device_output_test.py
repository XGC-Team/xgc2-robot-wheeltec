#!/usr/bin/env python3
"""Exercise the Wheeltec udp.v1 HOLD host on a PTY under a private ROS master.

The fixture-only modem shim accepts DTR/RTS and can pause one serial write;
serial bytes still pass through the actual driver and vendor serial library.
"""
import argparse
import base64
import collections
import json
import os
from pathlib import Path
import pty
import secrets
import select
import signal
import socket
import struct
import subprocess
import tempfile
import threading
import time
import tty
import xmlrpc.client


def wait_for(check, label, seconds=5, interval=.02):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(interval)
    raise AssertionError(label)


def stop(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGINT)
        try:
            process.wait(5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise AssertionError('process did not quiesce on SIGINT')
    else:
        process.wait()


def free_port(kind):
    for _ in range(100):
        port = 20000 + secrets.randbelow(20001)
        with socket.socket(socket.AF_INET, kind) as reservation:
            try:
                reservation.bind(('127.0.0.1', port))
                return port
            except OSError:
                pass
    raise AssertionError('no private port available in 20000..40000')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--devel', required=True, type=Path)
    parser.add_argument('--helpers', required=True, type=Path)
    args = parser.parse_args()
    processes = []
    serial_stop = threading.Event()
    serial_thread = None
    master_fd = slave_fd = None
    with tempfile.TemporaryDirectory(prefix='wheeltec-hold-') as temporary:
        directory = Path(temporary)
        port = free_port(socket.SOCK_STREAM)
        hold_port = free_port(socket.SOCK_DGRAM)
        env = os.environ.copy()
        env.update(ROS_MASTER_URI=f'http://127.0.0.1:{port}', ROS_HOSTNAME='127.0.0.1',
                   ROS_IP='127.0.0.1', ROS_HOME=str(directory/'ros-home'),
                   ROS_LOG_DIR=str(directory/'ros-log'))
        os.environ.update({key: env[key] for key in
                           ('ROS_MASTER_URI', 'ROS_HOSTNAME', 'ROS_IP', 'ROS_HOME', 'ROS_LOG_DIR')})
        barrier = directory/'write-barrier'
        key_file = directory/'hold.key'
        wrong_key = directory/'wrong.key'
        for path in (key_file, wrong_key):
            path.write_text('1 ' + base64.b64encode(secrets.token_bytes(32)).decode('ascii') + '\n')
            path.chmod(0o600)
        log = (directory/'process.log').open('w+')

        def launch(command, extra=None, capture=False):
            configuration = env.copy()
            configuration.update(extra or {})
            process = subprocess.Popen(command, env=configuration,
                                       stdout=subprocess.PIPE if capture else log,
                                       stderr=subprocess.STDOUT, text=True, start_new_session=True)
            processes.append(process)
            return process

        def cli_command(*words, key=key_file, timeout=2000):
            return ['xgc2-hold', '--endpoint', f'127.0.0.1:{hold_port}',
                    '--key-file', str(key), '--timeout-ms', str(timeout), *words]

        def cli(*words, key=key_file, timeout=2000, code=0):
            result = subprocess.run(cli_command(*words, key=key, timeout=timeout),
                                    env=env, capture_output=True, text=True, timeout=6)
            assert result.returncode == code, f'CLI {words}: {result.stdout} {result.stderr}'
            return json.loads(result.stdout)

        def state():
            return cli('state', '--robot', 'wheel-fixture')['reply']['robots'][0]

        try:
            core = launch(['roscore', '-p', str(port)])

            def master_ready():
                assert core.poll() is None, 'private roscore startup failed'
                try:
                    return xmlrpc.client.ServerProxy(env['ROS_MASTER_URI']).getPid('/fixture')[0] == 1
                except (ConnectionError, OSError):
                    return False

            wait_for(master_ready, 'private roscore timeout')
            import rospy
            from geometry_msgs.msg import Twist
            rospy.init_node('wheeltec_hold_fixture', disable_signals=True)
            wheel_pub = rospy.Publisher('/fixture/cmd_vel', Twist, queue_size=100)
            master_fd, slave_fd = pty.openpty()
            slave = os.ttyname(slave_fd)
            os.set_blocking(master_fd, False)
            tty.setraw(slave_fd)
            frames = collections.deque(maxlen=20000)
            feedback_moving = threading.Event()
            feedback_moving.set()
            peer_errors = []

            def serial_peer():
                buffer = bytearray()
                while not serial_stop.is_set():
                    # MCU velocity frame: planar linear speed and yaw, XOR BCC, tail.
                    telemetry = bytearray(24)
                    telemetry[0], telemetry[23] = 0x7b, 0x7d
                    if feedback_moving.is_set():
                        telemetry[4:8] = struct.pack('>hh', 200, 300)
                    checksum = 0
                    for byte in telemetry[:22]:
                        checksum ^= byte
                    telemetry[22] = checksum
                    try:
                        os.write(master_fd, telemetry)
                        if select.select([master_fd], [], [], .01)[0]:
                            buffer.extend(os.read(master_fd, 4096))
                        while len(buffer) >= 11:
                            if buffer[0] != 0x7b:
                                del buffer[0]
                                continue
                            frame = bytes(buffer[:11])
                            del buffer[:11]
                            checksum = 0
                            for byte in frame[:9]:
                                checksum ^= byte
                            assert frame[-1] == 0x7d and checksum == frame[9], 'invalid serial output frame'
                            frames.append((time.monotonic(), struct.unpack('>hhh', frame[3:9])))
                    except BlockingIOError:
                        serial_stop.wait(.01)
                    except Exception as error:
                        peer_errors.append(error)
                        return
                    serial_stop.wait(.01)

            serial_thread = threading.Thread(target=serial_peer)
            serial_thread.start()

            def driver(key=key_file, *options):
                return launch([str(args.devel/'lib/turn_on_wheeltec_robot/wheeltec_robot_node'),
                               f'_usart_port_name:={slave}', '_hold_robot_id:=wheel-fixture',
                               f'_hold_port:={hold_port}', f'_hold_key_file:={key}',
                               'cmd_vel:=/fixture/cmd_vel', *options],
                              {'LD_PRELOAD': str(args.helpers/'libpty_modem_shim.so'),
                               'WHEELTEC_TEST_WRITE_BARRIER': str(barrier)})

            def connected(process):
                assert process.poll() is None, 'driver exited unexpectedly'
                return wheel_pub.get_num_connections() == 1

            def publish(value):
                twist = Twist()
                twist.linear.x, twist.linear.y, twist.angular.z = value, value/2, value/4
                wheel_pub.publish(twist)

            def saw(value, since):
                return any(stamp >= since and velocity[0] == round(value*1000)
                           for stamp, velocity in list(frames))

            wheel = driver()
            wait_for(lambda: connected(wheel), 'driver ROS startup timeout')
            described = cli('describe')['reply']
            instance = described['instance']
            assert described['robots'] == ['wheel-fixture'] and described['feedback']['wheel-fixture']
            initial = state()
            assert not initial['held'] and initial['revision'] == 0 and initial['stage'] == 'released'
            stamp = time.monotonic()
            publish(.2)
            wait_for(lambda: saw(.2, stamp), 'released command did not reach serial')

            engaged = cli('engage', '--robot', 'wheel-fixture')['reply']['robots'][0]
            assert engaged['outcome'] == 'engaged' and engaged['revision'] == 1
            wait_for(lambda: state()['stage'] == 'zero_written', 'zero_written not reported', interval=.08)
            stamp = time.monotonic()
            for _ in range(15):
                publish(.4)
                time.sleep(.01)
            held_frames = [(at, velocity) for at, velocity in list(frames) if at > stamp]
            assert len(held_frames) >= 10, 'zero output was not re-asserted across control ticks'
            assert all(velocity == (0, 0, 0) for _, velocity in held_frames), 'held command reached serial'
            assert max(b[0]-a[0] for a, b in zip(held_frames, held_frames[1:])) < .08, 'zero ticks stalled'
            time.sleep(.35)
            assert state()['stage'] == 'zero_written', 'moving MCU feedback reported stopped'
            feedback_moving.clear()

            def stopped_state():
                current = state()
                return current if current['stage'] == 'stopped' else None

            stopped = wait_for(stopped_state, 'resting MCU feedback did not report stopped', interval=.08)
            assert stopped['zero_written_at_ms'] <= stopped['stopped_at_ms']

            stale = cli('release', '--robot', 'wheel-fixture=0', '--instance', instance, code=1)
            assert stale['reply']['robots'][0]['outcome'] == 'conflict' and state()['held']
            stale_instance = ('1' if instance[0] != '1' else '2') + instance[1:]
            rejected = cli('release', '--robot', 'wheel-fixture=1', '--instance', stale_instance, code=2)
            assert rejected['status'] == 'conflict' and state()['held']
            unauthenticated = cli('engage', '--all', key=wrong_key, timeout=250, code=2)
            assert unauthenticated['disposition'] == 'outcome_unknown' and 'reply' not in unauthenticated
            released = cli('release', '--robot', 'wheel-fixture=1', '--instance', instance)['reply']['robots'][0]
            assert released['outcome'] == 'released' and released['revision'] == 2
            stamp = time.monotonic()
            time.sleep(.10)
            assert not saw(.4, stamp), 'release replayed a held command'
            publish(.3)
            wait_for(lambda: saw(.3, stamp), 'release did not accept a fresh command')

            # Block a callback's write after spinOnce copied its queue. ROS IO
            # receives the next command while held; tick applies release before
            # the next spinOnce dispatches it, so only the receipt fence drops it.
            barrier.touch()
            publish(.5)
            wait_for(lambda: Path(str(barrier)+'.blocked').exists(), 'native write did not block')
            engaged = cli('engage', '--all')['reply']['robots'][0]
            assert engaged['held'] and engaged['stage'] == 'gated' and engaged['revision'] == 3
            stamp = time.monotonic()
            publish(.6)
            time.sleep(.10)
            pending = launch(cli_command('release', '--robot', 'wheel-fixture=3', '--instance', instance), capture=True)
            time.sleep(.10)
            assert pending.poll() is None, 'release did not wait for the native tick'
            barrier.unlink()
            output, _ = pending.communicate(timeout=6)
            assert pending.returncode == 0 and json.loads(output)['reply']['robots'][0]['outcome'] == 'released'
            time.sleep(.15)
            assert not saw(.6, stamp), 'a pre-release receipt was dispatched after release'
            publish(.7)
            wait_for(lambda: saw(.7, stamp), 'fresh command rejected after queued release')
            stop(wheel)
            assert wheel.returncode == 0, 'normal driver shutdown failed'
            wait_for(lambda: wheel_pub.get_num_connections() == 0, 'driver subscriber did not close')

            boot = driver(key_file, '_hold_boot_held:=true')
            wait_for(lambda: connected(boot), 'boot-held driver startup timeout')
            boot_state = state()
            assert boot_state['held'] and boot_state['revision'] == 1
            stamp = time.monotonic()
            publish(.8)
            time.sleep(.12)
            assert not saw(.8, stamp), 'boot-held driver accepted motion'
            stop(boot)
            assert boot.returncode == 0
            wait_for(lambda: wheel_pub.get_num_connections() == 0, 'boot-held subscriber did not close')

            unreadable_key = directory/'unreadable.key'
            unreadable_key.write_bytes(key_file.read_bytes())
            unreadable_key.chmod(0o000)
            assert not os.access(unreadable_key, os.R_OK), 'fixture must run without permission to read the test key'
            for unavailable_key in (directory/'missing.key', unreadable_key):
                required = driver(unavailable_key, '_hold_required:=true')
                required.wait(timeout=6)
                assert required.returncode != 0, f'hold_required accepted {unavailable_key.name}'
                optional = driver(unavailable_key, '_hold_required:=false', '_hold_boot_held:=true')
                wait_for(lambda: connected(optional), 'optional HOLD driver failed to start')
                stamp = time.monotonic()
                publish(.9)
                wait_for(lambda: saw(.9, stamp), 'optional HOLD with an unusable key did not pass commands')
                absent = cli('describe', timeout=250, code=2)
                assert 'reply' not in absent, 'optional HOLD exposed a service with an unusable key'
                stop(optional)
                assert optional.returncode == 0
                wait_for(lambda: wheel_pub.get_num_connections() == 0, 'optional HOLD subscriber did not close')
            assert not peer_errors, f'PTY peer failed: {peer_errors}'
            log.flush()
            log.seek(0)
            assert log.read().count('HOLD unavailable:') == 2, 'optional key error was not logged once per driver'
            print(f'PASS Wheeltec HOLD: receipt fence, zero ticks, MCU feedback, CAS, keys, boot and shutdown '
                  f'(master {port}, UDP {hold_port}, ROS_HOME {env["ROS_HOME"]})')
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read()[-8000:])
            raise
        finally:
            if barrier.exists():
                barrier.unlink()
            cleanup_errors = []
            for process in reversed(processes):
                try:
                    stop(process)
                except Exception as error:
                    cleanup_errors.append(error)
            serial_stop.set()
            if serial_thread:
                serial_thread.join()
            if 'rospy' in locals():
                rospy.signal_shutdown('fixture complete')
            if master_fd is not None:
                os.close(master_fd)
                os.close(slave_fd)
            log.close()
            assert not cleanup_errors, f'process cleanup failed: {cleanup_errors}'


if __name__ == '__main__':
    main()
