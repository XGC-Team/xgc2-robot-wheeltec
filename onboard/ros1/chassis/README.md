# Wheeltec ROS1 chassis

Standalone serial chassis driver. IMU and odometry come from the MCU
on the same UART. Not bundled with lidar.

```text
src/turn_on_wheeltec_robot
```

Node `/wheeltec_robot` publishes `/imu` `/odom` `/PowerVoltage` and
subscribes to `/cmd_vel`. Default port `/dev/wheeltec_controller` @ 115200.

The node does not clamp Twist. It sends `int16` mm/s (`cmd * 1000`).
Vendor TEB for `mini_mec` (planner only): vx 0.5 m/s, vy 0.3 m/s,
wz 1.5 rad/s. MCU firmware limit is not in this tree.

udev rules are packaged and installed only by the manual script.
