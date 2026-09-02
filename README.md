# XGC2 Wheeltec Robot

Vehicle-true ROS Melodic runtime for the Wheeltec mecanum onboard computer.

Layout matches AgileX Scout: sibling workspaces under `onboard/ros1/`.
Source of truth for field numbers is the usage-repo live page
`memory/field/wheeltec/`, not this product tree.

## Vehicle

| Item | Value |
| --- | --- |
| Host | `wheeltec` |
| Board | NVIDIA Jetson Nano |
| OS | Ubuntu 18.04 (Bionic) |
| ROS | Melodic |
| Arch | arm64 |

```text
onboard/ros1/chassis          turn_on_wheeltec_robot
onboard/ros1/communication    (no vehicle wrapper; official swarm_ros_bridge)
onboard/ros1/sensors          lidar only (lslidar_*)
onboard/ros1/autostart        compose + install-only units
```

`apt install ros-melodic-xgc2-wheeltec-onboard` installs chassis, bridge,
and autostart. No unit is enabled or started. Lidar is a separate package.

```text
xgc2-wheeltec-chassis.service
  start-chassis: wait /dev/wheeltec_controller
  wheeltec_onboard_autostart/chassis.launch
    wheeltec_robot_node  /imu /odom /PowerVoltage /cmd_vel
xgc2-wheeltec-swarm-ros-bridge.service
  wheeltec_onboard_autostart/swarm.launch
    send /imu :3001 20 Hz, /PowerVoltage :3002 1 Hz
    recv /cmd_vel from XGC1 Scout .150, XGC1 Mecanum .199, and XGC2 .251
      (default :3001; field script may select legacy :3005 or :3301)
xgc2-wheeltec-lidar.service
  optional; needs ros-melodic-xgc2-wheeltec-lslidar
```

## Packages

| Debian package | ROS package | Role |
| --- | --- | --- |
| `ros-melodic-xgc2-wheeltec-driver` | `turn_on_wheeltec_robot` | Serial chassis node |
| `ros-melodic-swarm-ros-bridge` | `swarm_ros_bridge` | Official bridge binary (APT Depends) |
| `ros-melodic-xgc2-wheeltec-onboard-autostart` | `wheeltec_onboard_autostart` | Compose launches and units; install-only |
| `ros-melodic-xgc2-wheeltec-onboard` | `wheeltec_onboard` | Install-set meta; no lidar Depends |
| `ros-melodic-xgc2-wheeltec-lslidar-msgs` | `lslidar_msgs` | Optional |
| `ros-melodic-xgc2-wheeltec-lslidar-driver` | `lslidar_driver` | Optional `/scan` |
| `ros-melodic-xgc2-wheeltec-lslidar` | `lslidar` | Optional meta |

```bash
sudo apt-get install ros-melodic-xgc2-wheeltec-onboard
# postinst installs units and disables vendor boot units; it does not enable
# product units. Site peer yaml: /etc/xgc2/wheeltec/ros_topics.yaml
sudo systemctl enable --now xgc2-wheeltec-chassis.service
sudo systemctl enable --now xgc2-wheeltec-swarm-ros-bridge.service
# do not enable xgc2-wheeltec-lidar.service unless the lidar package is installed
# optional:
# sudo apt-get install ros-melodic-xgc2-wheeltec-lslidar
```

Driver postinst copies packaged udev rules when those filenames are absent.

`docs/` is present-tense operator notes. Field notes live in `memory/field/wheeltec/`
(`xgc2-dev-memory`). Vendor navigation/camera/URDF leftovers are in
`vendor/legacy/` and are not packaged.

## Upstream provenance

- Chassis: <https://github.com/WheelBoard/turn_on_wheeltec_robot> (BSD-2-Clause)
- Lidar: LeiShen `lsx10` / `lslidar_driver` (GPL-3.0)
