# Wheeltec ROS1 communication workspace

Sibling of `chassis`, `sensors`, and `autostart`. Vehicle YAML and launch
for the official `swarm_ros_bridge` binary (APT). systemd lives in
`onboard/ros1/autostart`.

```text
src/wheeltec_swarm_ros_bridge
```

Sends `/imu` (`sensor_msgs/Imu`, max 20 Hz, `:3001`) and `/PowerVoltage`
(`std_msgs/Float32`, max 1 Hz, `:3002`). Receives `/cmd_vel`. Peer address
is site config, not a baked field IP. Voltage stays a first-class Float32;
do not pack it into String.
