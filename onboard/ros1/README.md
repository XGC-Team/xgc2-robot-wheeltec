# Onboard ROS1 workspaces

Sibling workspaces, same shape as AgileX Scout.

```text
chassis/src/             turn_on_wheeltec_robot
communication/src/       wheeltec_swarm_ros_bridge
                         official swarm_ros_bridge from APT
sensors/src/             lidar only (lslidar_*)
autostart/src/           wheeltec_onboard_autostart
                         compose launches and install-only units
```

Autostart owns every unit. Apt installs them and enables none.
Lidar is optional and is not a hard Depends of the install set.
