#!/usr/bin/env bash
set -euo pipefail

ROS_DISTRO="${ROS_DISTRO:-melodic}"
PREFIX="/opt/ros/$ROS_DISTRO"

# shellcheck disable=SC1090,SC1091
source "$PREFIX/setup.bash"

for deb_package in \
  "ros-$ROS_DISTRO-xgc2-wheeltec-driver" \
  "ros-$ROS_DISTRO-xgc2-wheeltec-swarm-ros-bridge" \
  "ros-$ROS_DISTRO-xgc2-wheeltec-onboard-autostart" \
  "ros-$ROS_DISTRO-xgc2-wheeltec-onboard"; do
  dpkg -s "$deb_package" >/dev/null
done

test "$(rospack find turn_on_wheeltec_robot)" = "$PREFIX/share/turn_on_wheeltec_robot"
test "$(rospack find wheeltec_swarm_ros_bridge)" = "$PREFIX/share/wheeltec_swarm_ros_bridge"
test "$(rospack find wheeltec_onboard_autostart)" = "$PREFIX/share/wheeltec_onboard_autostart"
test -f "$PREFIX/share/wheeltec_onboard/package.xml"

test -x "$PREFIX/lib/turn_on_wheeltec_robot/wheeltec_robot_node"
test -f "$PREFIX/share/turn_on_wheeltec_robot/launch/wheeltec_robot.launch"
test -x "$PREFIX/share/turn_on_wheeltec_robot/scripts/install_wheeltec_controller_udev_rule.sh"
test -f "$PREFIX/share/turn_on_wheeltec_robot/udev/99-xgc2-wheeltec-controller.rules"
test -f "$PREFIX/share/wheeltec_swarm_ros_bridge/config/ros_topics.yaml"
test -f "$PREFIX/share/wheeltec_swarm_ros_bridge/launch/wheeltec_swarm_ros_bridge.launch"
test -f "$PREFIX/share/wheeltec_onboard_autostart/launch/wheeltec.launch"
test -f "$PREFIX/share/wheeltec_onboard_autostart/launch/chassis.launch"
test -f "$PREFIX/share/wheeltec_onboard_autostart/systemd/xgc2-wheeltec-chassis.service"
test -x "$PREFIX/lib/wheeltec_onboard_autostart/start-chassis"
test -x "$PREFIX/lib/wheeltec_onboard_autostart/start-swarm-ros-bridge"
test -f /lib/systemd/system/xgc2-wheeltec-chassis.service
test -f /lib/systemd/system/xgc2-wheeltec-swarm-ros-bridge.service
test -f /lib/systemd/system/xgc2-wheeltec-lidar.service
test -f /etc/xgc2/wheeltec/onboard.env
test ! -e /etc/systemd/system/multi-user.target.wants/xgc2-wheeltec-chassis.service
test ! -e /etc/systemd/system/multi-user.target.wants/xgc2-wheeltec-swarm-ros-bridge.service
test ! -e /etc/systemd/system/multi-user.target.wants/xgc2-wheeltec-lidar.service
grep -q 'EnvironmentFile=-/etc/xgc2/wheeltec/onboard.env' /lib/systemd/system/xgc2-wheeltec-chassis.service
grep -q 'EnvironmentFile=-/etc/xgc2/wheeltec/onboard.env' /lib/systemd/system/xgc2-wheeltec-swarm-ros-bridge.service

python3 - "$PREFIX/share/wheeltec_swarm_ros_bridge/config/ros_topics.yaml" <<'PY'
from __future__ import print_function

import sys
import yaml

with open(sys.argv[1], "r") as stream:
    config = yaml.safe_load(stream)

sends = {item["topic_name"]: item for item in config["send_topics"]}
assert sends["/imu"]["max_freq"] == 20
assert sends["/imu"]["msg_type"] == "sensor_msgs/Imu"
assert sends["/PowerVoltage"]["max_freq"] == 1
assert sends["/PowerVoltage"]["msg_type"] == "std_msgs/Float32"
assert config["recv_topics"][0]["topic_name"] == "/cmd_vel"
assert config["recv_topics"][0]["max_freq"] == 0
assert "qgc" in config["IP"]
PY

roslaunch --files turn_on_wheeltec_robot wheeltec_robot.launch >/dev/null
roslaunch --files wheeltec_swarm_ros_bridge wheeltec_swarm_ros_bridge.launch >/dev/null
roslaunch --files wheeltec_onboard_autostart wheeltec.launch >/dev/null

echo "Installed Wheeltec ROS1 package checks passed"
