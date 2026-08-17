#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

git --git-dir="${REPO_ROOT}/.git" --work-tree="${REPO_ROOT}" diff --check
shellcheck \
  onboard/ros1/chassis/src/turn_on_wheeltec_robot/scripts/install_wheeltec_controller_udev_rule.sh \
  onboard/ros1/sensors/src/lidar/lslidar_driver/scripts/install_wheeltec_lidar_udev_rule.sh \
  onboard/ros1/autostart/src/wheeltec_onboard_autostart/scripts/start-chassis \
  onboard/ros1/autostart/src/wheeltec_onboard_autostart/scripts/start-swarm-ros-bridge \
  onboard/ros1/autostart/src/wheeltec_onboard_autostart/scripts/start-lidar \
  .xgc2/scripts/build_debs_in_docker.sh \
  .xgc2/scripts/check_installed_packages.sh \
  .xgc2/scripts/check_package_compliance.sh \
  .xgc2/scripts/package_debs.sh

xmllint --noout \
  onboard/ros1/chassis/src/turn_on_wheeltec_robot/package.xml \
  onboard/ros1/chassis/src/turn_on_wheeltec_robot/launch/wheeltec_robot.launch \
  onboard/ros1/communication/src/wheeltec_swarm_ros_bridge/package.xml \
  onboard/ros1/communication/src/wheeltec_swarm_ros_bridge/launch/wheeltec_swarm_ros_bridge.launch \
  onboard/ros1/autostart/src/wheeltec_onboard_autostart/package.xml \
  onboard/ros1/autostart/src/wheeltec_onboard_autostart/launch/wheeltec.launch \
  onboard/ros1/autostart/src/wheeltec_onboard_autostart/launch/chassis.launch \
  onboard/ros1/autostart/src/wheeltec_onboard_autostart/launch/swarm.launch \
  onboard/ros1/autostart/src/wheeltec_onboard_autostart/launch/lidar.launch \
  onboard/ros1/autostart/src/wheeltec_onboard/package.xml

grep -q '^id: xgc2-wheeltec-onboard-ros1$' .xgc2/product.yml
grep -q '^version: 0.1.0-4$' .xgc2/product.yml
grep -q 'ros-melodic-xgc2-wheeltec-onboard-autostart' .xgc2/product.yml
grep -q 'ros-melodic-swarm-ros-bridge (>= 1.1.0-11)' .xgc2/product.yml
grep -q '<name>turn_on_wheeltec_robot</name>' onboard/ros1/chassis/src/turn_on_wheeltec_robot/package.xml
grep -q '<name>wheeltec_swarm_ros_bridge</name>' onboard/ros1/communication/src/wheeltec_swarm_ros_bridge/package.xml
grep -q '<name>wheeltec_onboard_autostart</name>' onboard/ros1/autostart/src/wheeltec_onboard_autostart/package.xml
grep -q '<name>wheeltec_onboard</name>' onboard/ros1/autostart/src/wheeltec_onboard/package.xml
grep -q 'max_freq: 0' onboard/ros1/communication/src/wheeltec_swarm_ros_bridge/config/ros_topics.yaml
grep -q 'ATTRS{serial}=="0002"' onboard/ros1/chassis/src/turn_on_wheeltec_robot/udev/99-xgc2-wheeltec-controller.rules
grep -q 'ATTRS{serial}=="0001"' onboard/ros1/sensors/src/lidar/lslidar_driver/udev/99-xgc2-wheeltec-lidar.rules

python3 .xgc2/scripts/xgc2_artifact_manifest.py --help >/dev/null

echo "Wheeltec product compliance checks passed"
