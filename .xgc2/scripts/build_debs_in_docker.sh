#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DOCKER_IMAGE="${DOCKER_IMAGE:-ghcr.io/xgc-team/xgc2-images/xgc2-build-bionic-full-melodic:1.0.0}"
WORK_DIR="${WORK_DIR:-$REPO_ROOT/.work/docker}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/debs}"
INSTALL_CHECK="${INSTALL_CHECK:-true}"
XGC2_APT_BASE_URL="${XGC2_APT_BASE_URL:-https://xgc2.apt.xiaokang.ink}"
XGC2_APT_DISTRIBUTION="${XGC2_APT_DISTRIBUTION:-bionic}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      DOCKER_IMAGE="$2"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-install-check)
      INSTALL_CHECK=false
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

docker pull "$DOCKER_IMAGE"
docker_args=(--rm -e "DEBIAN_FRONTEND=noninteractive" -e "INSTALL_CHECK=$INSTALL_CHECK" -e "XGC2_APT_BASE_URL=$XGC2_APT_BASE_URL" -e "XGC2_APT_DISTRIBUTION=$XGC2_APT_DISTRIBUTION" -e "XGC2_APT_OVERLAY_URL=${XGC2_APT_OVERLAY_URL:-}" -v "$REPO_ROOT:/workspace/repo:ro" -v "$WORK_DIR:/workspace/work" -v "$OUTPUT_DIR:/workspace/out")
docker run "${docker_args[@]}" "$DOCKER_IMAGE" bash -lc '
    set -euo pipefail

    export DEBIAN_FRONTEND=noninteractive
    mkdir -p /etc/apt/keyrings
    curl -fsSL "$XGC2_APT_BASE_URL/xgc2-archive-keyring.gpg" -o /etc/apt/keyrings/xgc2-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/xgc2-archive-keyring.gpg] $XGC2_APT_BASE_URL $XGC2_APT_DISTRIBUTION main" > /etc/apt/sources.list.d/xgc2.list
    if [[ -n "$XGC2_APT_OVERLAY_URL" ]]; then
      echo "deb [signed-by=/etc/apt/keyrings/xgc2-archive-keyring.gpg] $XGC2_APT_OVERLAY_URL $XGC2_APT_DISTRIBUTION main" > /etc/apt/sources.list.d/00-xgc2-release-train.list
    fi
    apt-get update
    apt-get install -y --no-install-recommends ros-melodic-swarm-ros-bridge

    BUILD_ROOT="$(mktemp -d /workspace/work/wheeltec.XXXXXX)"
    WORKSPACE="$BUILD_ROOT/workspace"
    mkdir -p "$WORKSPACE/src"

    rsync -a /workspace/repo/onboard/ros1/chassis/src/turn_on_wheeltec_robot/ "$WORKSPACE/src/turn_on_wheeltec_robot/"
    rsync -a /workspace/repo/onboard/ros1/autostart/src/wheeltec_onboard_autostart/ "$WORKSPACE/src/wheeltec_onboard_autostart/"
    rsync -a /workspace/repo/onboard/ros1/autostart/src/wheeltec_onboard/ "$WORKSPACE/src/wheeltec_onboard/"
    rsync -a /workspace/repo/onboard/ros1/sensors/src/lidar/lslidar_msgs/ "$WORKSPACE/src/lslidar_msgs/"
    rsync -a /workspace/repo/onboard/ros1/sensors/src/lidar/lslidar_driver/ "$WORKSPACE/src/lslidar_driver/"
    rsync -a /workspace/repo/onboard/ros1/sensors/src/lidar/lslidar/ "$WORKSPACE/src/lslidar/"

    cd "$WORKSPACE"
    set +u
    source /opt/ros/melodic/setup.bash
    set -u
    DESTDIR="$WORKSPACE/install-root" catkin_make install -DCMAKE_INSTALL_PREFIX=/opt/ros/melodic -DCATKIN_ENABLE_TESTING=OFF -DCMAKE_BUILD_TYPE=Release

    set +u
    source devel/setup.bash
    set -u
    test "$(rospack find turn_on_wheeltec_robot)" = "$WORKSPACE/src/turn_on_wheeltec_robot"
    test "$(rospack find wheeltec_onboard_autostart)" = "$WORKSPACE/src/wheeltec_onboard_autostart"
    roslaunch --files turn_on_wheeltec_robot wheeltec_robot.launch >/dev/null
    roslaunch --files wheeltec_onboard_autostart swarm.launch >/dev/null
    roslaunch --files wheeltec_onboard_autostart wheeltec.launch >/dev/null

    /workspace/repo/.xgc2/scripts/package_debs.sh --install-root "$WORKSPACE/install-root" --output-dir /workspace/out

    if [[ "$INSTALL_CHECK" == "true" ]]; then
      printf "#!/bin/sh\nexit 101\n" > /usr/sbin/policy-rc.d
      chmod 0755 /usr/sbin/policy-rc.d
      apt-get install -y --no-install-recommends /workspace/out/ros-melodic-xgc2-wheeltec-driver_*.deb /workspace/out/ros-melodic-xgc2-wheeltec-onboard-autostart_*.deb /workspace/out/ros-melodic-xgc2-wheeltec-onboard_*.deb
      /workspace/repo/.xgc2/scripts/check_installed_packages.sh
    fi
  '

echo "Debian package output:"
find "$OUTPUT_DIR" -maxdepth 1 -type f -name "*.deb" -print | sort
