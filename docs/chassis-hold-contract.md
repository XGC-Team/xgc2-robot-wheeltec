# Wheeltec chassis HOLD host

The driver instantiates `ChassisHold` and `UdpEndpoint` from chassis-hold
0.2.0 and serves `xgc2.chassis.hold` over `udp.v1`, bound to `0.0.0.0`.
The library owns the state machine, service methods, authentication,
instance identity and release revisions. See its
[contract](https://github.com/XGC-Team/xgc2-chassis-hold/blob/fcfe8f441ad257b049c27dfc0ea4351bae6733f0/contracts/chassis-hold.md).
The driver links only the `core` and `udp` components, which support Bionic.

| Private ROS parameter | Default | Meaning |
| --- | --- | --- |
| `hold_robot_id` | Required | Registered identity of this one chassis |
| `hold_port` | `19530` | UDP service port, 1..65535 |
| `hold_key_file` | `/etc/xgc2/chassis-hold.key` | Authentication key file |
| `hold_boot_held` | `false` | Start held after each process restart |
| `hold_required` | `true` | Exit with an error when the endpoint cannot start |

Launches require `robot_id` and forward the other four parameters as
arguments with these defaults. Autostart reads the corresponding
`XGC2_CHASSIS_HOLD_*` settings from `/etc/xgc2/wheeltec/onboard.env`.

The robot setup user-script provisions the key; this package ships no key.
The file contains one `<key_id> <base64 of 32 bytes>` entry per line and is
owned by `wheeltec:wheeltec`, the account named by the chassis unit's
`User=wheeltec`, with mode 0600. Its directory `/etc/xgc2` is root-owned
with mode 0755. Run the provisioning commands as root, replacing `<keyfile>`
with the supplied key file path:

```sh
install -d -o root -g root -m 0755 /etc/xgc2
install -o wheeltec -g wheeltec -m 0600 <keyfile> /etc/xgc2/chassis-hold.key
```

With `hold_required=true`, an unreadable, missing, empty or malformed key
ends the process non-zero. With false, the
driver logs the endpoint error once and drives without HOLD, including
when `hold_boot_held` was requested.

The `/cmd_vel` callback receives a ROS `MessageEvent` and passes its
`getReceiptTime().toNSec()` to `admit` before `WriteMotion`. The domain clock
is `ros::Time::now().toNSec()`. Held commands and commands received before
the last release are dropped, including a callback dispatched after release.
Release never replays an old command.

The existing `Control()` thread owns every serial write and calls `tick()`
once per cycle, after `ros::spinOnce()`. While held, each tick sends the
original 11-byte zero `Twist` frame through `WriteMotion`. A complete write
allows `zero_written`. Feedback comes from the checksum-validated MCU
velocity frame parsed by `Get_Sensor_Data_New`: planar speed `hypot(vx, vy)`,
yaw speed and the ROS receipt stamp. Only measured rest after zero output
can advance to `stopped`, using the library defaults of 0.02 m/s, 0.05 rad/s
and a continuous 300 ms dwell. A zero command alone does not establish rest.

Serial write failure, serial read exceptions and the existing 15-second
frame watchdog end the process non-zero. Normal shutdown stops the endpoint
and library, writes zero and closes serial. The chassis systemd unit retains
`Restart=always` with a five-second restart delay; each new driver process
has a new library instance. Vehicle acceptance remains outside this test.

The driver fixture uses `xgc2-hold`, a temporary 0600 key, a PTY with the
modem shim and a private ROS master on a random port in 20000..40000 with
its own `ROS_HOME`. The shim's fixture-only write barrier checks a queued
command received before release and dispatched afterwards. Library
contract and transport-fault tests remain in the chassis-hold repository.

```sh
. /path/to/catkin/devel/setup.bash
cmake -S test -B .work/hold-test \
  -DWHEELTEC_DEVEL_PREFIX=/path/to/catkin/devel \
  -DPYTHON_EXECUTABLE=/usr/bin/python3
cmake --build .work/hold-test -- -j2
(cd .work/hold-test && ctest --output-on-failure)
```
