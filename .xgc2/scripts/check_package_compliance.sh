#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

git diff --check
shellcheck scripts/install_wheeltec_controller_udev_rule.sh .xgc2/scripts/build_debs_in_docker.sh .xgc2/scripts/check_installed_packages.sh .xgc2/scripts/check_package_compliance.sh .xgc2/scripts/package_debs.sh
xmllint --noout package.xml launch/wheeltec_robot.launch onboard/ros1/src/communication/wheeltec_swarm_ros_bridge/package.xml onboard/ros1/src/communication/wheeltec_swarm_ros_bridge/launch/wheeltec_swarm_ros_bridge.launch onboard/ros1/src/bringup/wheeltec_onboard_bringup/package.xml onboard/ros1/src/bringup/wheeltec_onboard_bringup/launch/wheeltec_onboard.launch

grep -q '^id: xgc2-wheeltec-onboard-ros1$' .xgc2/product.yml
grep -q '^version: 0.1.0-3$' .xgc2/product.yml
grep -q 'ros-melodic-xgc2-wheeltec-onboard' .xgc2/product.yml
grep -q 'ros-melodic-swarm-ros-bridge (>= 1.1.0-7)' .xgc2/product.yml
grep -q '<name>turn_on_wheeltec_robot</name>' package.xml
grep -q '<name>wheeltec_swarm_ros_bridge</name>' onboard/ros1/src/communication/wheeltec_swarm_ros_bridge/package.xml
grep -q '<name>wheeltec_onboard_bringup</name>' onboard/ros1/src/bringup/wheeltec_onboard_bringup/package.xml
grep -q 'max_freq: 0' onboard/ros1/src/communication/wheeltec_swarm_ros_bridge/config/ros_topics.yaml
grep -q 'ATTRS{serial}=="0002"' udev/99-xgc2-wheeltec-controller.rules

python3 .xgc2/scripts/xgc2_artifact_manifest.py --help >/dev/null

echo "Wheeltec product compliance checks passed"
