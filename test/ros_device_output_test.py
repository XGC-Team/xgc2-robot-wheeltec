#!/usr/bin/env python3
"""Isolated Noetic fixture: simulated Scout + actual Wheeltec serial PTY output.
Run after sourcing the isolated catkin workspace. Never attaches a live master.
The PTY-only modem shim accepts DTR/RTS ioctls; this isn't a board ACK test.
"""
import argparse
import collections
import json
import os
from pathlib import Path
import pty
import select
import signal
import socket
import struct
import subprocess
import tempfile
import threading
import time
import xmlrpc.client


def wait_for(check, label, seconds=4):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(.01)
    raise AssertionError(label)


def stop(process):
    if process and process.poll() is None:
        os.killpg(process.pid, signal.SIGINT)
        try:
            process.wait(4)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise AssertionError('native process did not quiesce on SIGINT')


def main():
    args = argparse.ArgumentParser()
    args.add_argument('--devel', required=True, type=Path)
    args.add_argument('--helpers', required=True, type=Path)
    args = args.parse_args()
    processes = []
    serial_stop = threading.Event()
    serial_thread = None
    master_fd = slave_fd = None
    with tempfile.TemporaryDirectory(prefix='chassis-ros-native-') as temporary:
        directory = Path(temporary)
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        env = os.environ.copy()
        env.update(ROS_MASTER_URI=f'http://127.0.0.1:{port}', ROS_HOSTNAME='127.0.0.1',
                   ROS_HOME=str(directory/'ros-home'), ROS_LOG_DIR=str(directory/'ros-log'))
        os.environ.update({k: env[k] for k in ('ROS_MASTER_URI', 'ROS_HOSTNAME', 'ROS_HOME', 'ROS_LOG_DIR')})
        log = (directory/'process.log').open('w+')
        def launch(command, extra=None):
            configuration = env.copy()
            configuration.update(extra or {})
            process = subprocess.Popen(command, env=configuration, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            processes.append(process)
            return process
        try:
            core = launch(['roscore', '-p', str(port)])
            def master_ready():
                if core.poll() is not None:
                    raise AssertionError('isolated roscore startup failed')
                try:
                    return xmlrpc.client.ServerProxy(env['ROS_MASTER_URI']).getPid('/fixture')[0] == 1
                except (ConnectionError, OSError):
                    return False
            wait_for(master_ready, 'isolated roscore timeout')
            import rospy
            from geometry_msgs.msg import Twist
            from scout_msgs.msg import ScoutStatus
            rospy.init_node('device_output_fixture', disable_signals=True)
            # Native management must continue while the private ROS clock is paused.
            rospy.set_param('/use_sim_time', True)
            scout_values = collections.deque(maxlen=2000)
            rospy.Subscriber('/fixture/scout_status', ScoutStatus,
                             lambda msg: scout_values.append((time.monotonic(), msg.linear_velocity, msg.angular_velocity)))
            scout_pub = rospy.Publisher('/fixture/scout_cmd', Twist, queue_size=1)
            wheel_pub = rospy.Publisher('/fixture/wheel_cmd', Twist, queue_size=1)
            twist = Twist()
            twist.linear.x, twist.angular.z = .2, .3
            def publish():
                while not serial_stop.is_set():
                    scout_pub.publish(twist)
                    wheel_pub.publish(twist)
                    time.sleep(.01)
            publisher = threading.Thread(target=publish)
            publisher.start()
            def call(path, revision=None, robot=None, held=None):
                command = [str(args.helpers/'chassis_hold_peer'), str(path)]
                command += ['GET'] if revision is None else ['POST', str(revision), robot, str(held).lower()]
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=2)
                assert result.returncode == 0, f"SDK peer failed: {result.stderr}"
                status, body = result.stdout.split('\n', 1)
                return int(status), json.loads(body)
            scout_socket = directory/'scout.sock'
            scout = launch([str(args.devel/'lib/scout_base/scout_base_node'),
                            '_simulated_robot:=true', '_hold_robot_id:=scout-fixture',
                            f'_hold_socket:={scout_socket}', '/cmd_vel:=/fixture/scout_cmd',
                            '/scout_status:=/fixture/scout_status'])
            wait_for(lambda: scout_socket.exists(), 'Scout HTTP startup timeout')
            wait_for(lambda: any(abs(x) > .1 for _, x, _ in scout_values), 'Scout native cmd did not move')
            status, receipt = call(scout_socket, 0, 'scout-fixture', True)
            assert status == 200 and receipt['stage'] == 'applied' and receipt['revision'] == 1
            assert receipt['changes'][0]['zero_applied'] and not receipt['physical_stop_confirmed']
            stamp = time.monotonic()
            wait_for(lambda: any(t > stamp and x == 0 and yaw == 0 for t, x, yaw in scout_values), 'Scout hold did not update actual sim command state')
            time.sleep(.10)
            assert all(x == 0 and yaw == 0 for t, x, yaw in scout_values if t > stamp+.03), 'Scout held callback emitted nonzero'
            assert call(scout_socket, 0, 'scout-fixture', False)[0] == 409
            assert call(scout_socket, 1, 'scout-fixture', False)[0] == 200
            stamp = time.monotonic()
            wait_for(lambda: any(t > stamp and abs(x) > .1 for t, x, _ in scout_values), 'Scout release rejected fresh ROS command')
            stop(scout)
            assert scout.returncode == 0 and not scout_socket.exists(), 'Scout shutdown leaked endpoint or aborted'

            master_fd, slave_fd = pty.openpty()
            slave = os.ttyname(slave_fd)
            os.set_blocking(master_fd, False)
            frames = collections.deque(maxlen=2000)
            # Real device telemetry encoding, all zero motion. XOR BCC then tail.
            telemetry = bytearray(24)
            telemetry[0] = 0x7b
            telemetry[22] = 0x7b
            telemetry[23] = 0x7d
            def serial_peer():
                buffer = bytearray()
                while not serial_stop.is_set():
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
                            if frame[-1] != 0x7d:
                                continue
                            checksum = 0
                            for byte in frame[:9]:
                                checksum ^= byte
                            if checksum == frame[9]:
                                frames.append((time.monotonic(), struct.unpack('>hhh', frame[3:9])))
                    except (OSError, BlockingIOError):
                        time.sleep(.01)
            # Disable PTY echo so board telemetry cannot masquerade as output.
            import tty
            tty.setraw(slave_fd)
            serial_thread = threading.Thread(target=serial_peer)
            serial_thread.start()
            wheel_socket = directory/'wheel.sock'
            wheel = launch([str(args.devel/'lib/turn_on_wheeltec_robot/wheeltec_robot_node'),
                            f'_usart_port_name:={slave}', '_hold_robot_id:=wheel-fixture',
                            f'_hold_socket:={wheel_socket}', 'cmd_vel:=/fixture/wheel_cmd'],
                           {'LD_PRELOAD': str(args.helpers/'libpty_modem_shim.so')})
            wait_for(lambda: wheel_socket.exists(), 'Wheeltec HTTP startup timeout')
            wait_for(lambda: any(any(v != 0 for v in velocity) for _, velocity in frames), 'Wheeltec actual serial cmd did not move')
            status, receipt = call(wheel_socket, 0, 'wheel-fixture', True)
            assert status == 200 and receipt['stage'] == 'applied' and receipt['revision'] == 1
            assert receipt['changes'][0]['zero_applied'] and not receipt['physical_stop_confirmed']
            stamp = time.monotonic()
            wait_for(lambda: any(t > stamp and velocity == (0, 0, 0) for t, velocity in frames), 'Wheeltec hold omitted native zero frame')
            time.sleep(.10)
            assert all(velocity == (0, 0, 0) for t, velocity in frames if t > stamp+.03), 'Wheeltec held callback emitted nonzero frame'
            assert call(wheel_socket, 0, 'wheel-fixture', False)[0] == 409
            assert call(wheel_socket, 1, 'wheel-fixture', False)[0] == 200
            stamp = time.monotonic()
            wait_for(lambda: any(t > stamp and any(v != 0 for v in velocity) for t, velocity in frames), 'Wheeltec release rejected fresh ROS command')
            stop(wheel)
            assert wheel.returncode == 0 and not wheel_socket.exists(), 'Wheeltec shutdown leaked endpoint or failed'
            print('PASS actual Scout simulated command state and Wheeltec serial output arbitration, CAS, release and SIGINT')
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read()[-8000:])
            raise
        finally:
            serial_stop.set()
            if serial_thread:
                serial_thread.join()
            if 'publisher' in locals():
                publisher.join()
            if 'rospy' in locals():
                rospy.signal_shutdown('fixture complete')
            for process in reversed(processes):
                stop(process)
            if master_fd is not None:
                os.close(master_fd)
                os.close(slave_fd)
            log.close()


if __name__ == '__main__':
    main()
