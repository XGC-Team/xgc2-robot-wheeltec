# Wheeltec ROS1 chassis

Standalone serial chassis driver. IMU and odometry come from the MCU
on the same UART. Not bundled with lidar.

```text
src/turn_on_wheeltec_robot
```

Node `/wheeltec_robot` publishes `/imu` `/odom` `/PowerVoltage` and
subscribes to `/cmd_vel`. Default port `/dev/wheeltec_controller` @ 115200.

The same node serves `xgc2.chassis.hold` over `udp.v1` (default port 19530).
Launch with the registered robot id and a readable 0600 key file:

```sh
roslaunch turn_on_wheeltec_robot wheeltec_robot.launch robot_id:=site-robot-01
```

Launch arguments `hold_port`, `hold_key_file`, `hold_boot_held` and
`hold_required` set the corresponding private parameters. The defaults are
19530, `/etc/xgc2/chassis-hold.key`, false and true. See the
[driver HOLD contract](../../../docs/chassis-hold-contract.md) for the
receipt-time gate, MCU feedback and key ownership requirements.

The node does not clamp Twist. It sends `int16` mm/s (`cmd * 1000`).
Vendor TEB for `mini_mec` (planner only): vx 0.5 m/s, vy 0.3 m/s,
wz 1.5 rad/s. MCU firmware limit is not in this tree.

udev rules are packaged and installed only by the manual script.
