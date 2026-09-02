#!/usr/bin/env bash
set -euo pipefail

ROS_DISTRO="${ROS_DISTRO:-melodic}"
PREFIX="/opt/ros/$ROS_DISTRO"

# shellcheck disable=SC1090,SC1091
source "$PREFIX/setup.bash"

for deb_package in \
  "ros-$ROS_DISTRO-xgc2-wheeltec-driver" \
  "ros-$ROS_DISTRO-xgc2-wheeltec-onboard-autostart" \
  "ros-$ROS_DISTRO-xgc2-wheeltec-onboard"; do
  dpkg -s "$deb_package" >/dev/null
done
dpkg -s "ros-$ROS_DISTRO-xgc2-wheeltec-swarm-ros-bridge" >/dev/null 2>&1 \
  && { echo "retired ros-$ROS_DISTRO-xgc2-wheeltec-swarm-ros-bridge must not install" >&2; exit 1; }

test "$(rospack find turn_on_wheeltec_robot)" = "$PREFIX/share/turn_on_wheeltec_robot"
test "$(rospack find wheeltec_onboard_autostart)" = "$PREFIX/share/wheeltec_onboard_autostart"
test -f "$PREFIX/share/wheeltec_onboard/package.xml"
if rospack find wheeltec_swarm_ros_bridge >/dev/null 2>&1; then
  echo "retired wheeltec_swarm_ros_bridge must not be on the ROS path" >&2
  exit 1
fi

test -x "$PREFIX/lib/turn_on_wheeltec_robot/wheeltec_robot_node"
test -f "$PREFIX/share/turn_on_wheeltec_robot/launch/wheeltec_robot.launch"
test -x "$PREFIX/share/turn_on_wheeltec_robot/scripts/install_wheeltec_controller_udev_rule.sh"
test -f "$PREFIX/share/turn_on_wheeltec_robot/udev/99-xgc2-wheeltec-controller.rules"
test ! -d "$PREFIX/share/wheeltec_swarm_ros_bridge"
test -f "$PREFIX/share/wheeltec_onboard_autostart/launch/wheeltec.launch"
test -f "$PREFIX/share/wheeltec_onboard_autostart/launch/chassis.launch"
test -f "$PREFIX/share/wheeltec_onboard_autostart/launch/swarm.launch"
test -f "$PREFIX/share/wheeltec_onboard_autostart/systemd/xgc2-wheeltec-chassis.service"
test -x "$PREFIX/lib/wheeltec_onboard_autostart/start-chassis"
test -x "$PREFIX/lib/wheeltec_onboard_autostart/start-swarm-ros-bridge"
test -f /lib/systemd/system/xgc2-wheeltec-chassis.service
test -f /lib/systemd/system/xgc2-wheeltec-swarm-ros-bridge.service
test -f /lib/systemd/system/xgc2-wheeltec-lidar.service
test -f /etc/xgc2/wheeltec/onboard.env
test ! -e /etc/xgc2/wheeltec/ros_topics.yaml
test ! -e /etc/systemd/system/multi-user.target.wants/xgc2-wheeltec-chassis.service
test ! -e /etc/systemd/system/multi-user.target.wants/xgc2-wheeltec-swarm-ros-bridge.service
test ! -e /etc/systemd/system/multi-user.target.wants/xgc2-wheeltec-lidar.service
grep -q 'EnvironmentFile=-/etc/xgc2/wheeltec/onboard.env' /lib/systemd/system/xgc2-wheeltec-chassis.service
grep -q 'EnvironmentFile=-/etc/xgc2/wheeltec/onboard.env' /lib/systemd/system/xgc2-wheeltec-swarm-ros-bridge.service
grep -q 'missing .* configure network' "$PREFIX/lib/wheeltec_onboard_autostart/start-swarm-ros-bridge"

roslaunch --files turn_on_wheeltec_robot wheeltec_robot.launch >/dev/null
roslaunch --files wheeltec_onboard_autostart swarm.launch >/dev/null
roslaunch --files wheeltec_onboard_autostart wheeltec.launch >/dev/null

echo "Installed Wheeltec ROS1 package checks passed"
