#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT=""
OUTPUT_DIR=""
ROS_DISTRO="${ROS_DISTRO:-melodic}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

product_version() {
  local version
  version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*$/\1/p' "$REPO_ROOT/.xgc2/product.yml" | head -n 1)"
  if [[ -z "$version" ]]; then
    echo "unable to read product version from $REPO_ROOT/.xgc2/product.yml" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

VERSION="${PACKAGE_VERSION:-$(product_version)}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-root)
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$INSTALL_ROOT" || -z "$OUTPUT_DIR" ]]; then
  echo "--install-root and --output-dir are required" >&2
  exit 1
fi
if [[ -z "$VERSION" ]]; then
  echo "package version is missing" >&2
  exit 1
fi

ARCH="$(dpkg --print-architecture)"
PREFIX="/opt/ros/$ROS_DISTRO"
PREFIX_ROOT="$INSTALL_ROOT$PREFIX"
BUILD_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"

copy_path() {
  local source_path="$1"
  local package_root="$2"
  local relative
  local target_path

  if [[ ! -e "$source_path" ]]; then
    return
  fi

  relative="$(realpath --relative-to="$INSTALL_ROOT" "$source_path")"
  target_path="$package_root/$relative"
  mkdir -p "$(dirname "$target_path")"
  cp -a "$source_path" "$target_path"
}

copy_ros_package_paths() {
  local ros_package="$1"
  local package_root="$2"

  copy_path "$PREFIX_ROOT/share/$ros_package" "$package_root"
  copy_path "$PREFIX_ROOT/lib/$ros_package" "$package_root"
  copy_path "$PREFIX_ROOT/include/$ros_package" "$package_root"
  copy_path "$PREFIX_ROOT/share/common-lisp/ros/$ros_package" "$package_root"
  copy_path "$PREFIX_ROOT/share/gennodejs/ros/$ros_package" "$package_root"
  copy_path "$PREFIX_ROOT/share/roseus/ros/$ros_package" "$package_root"
}

write_control() {
  local package_root="$1"
  local deb_package="$2"
  local depends="$3"
  local description="$4"

  mkdir -p "$package_root/DEBIAN"
  cat > "$package_root/DEBIAN/control" <<EOF
Package: $deb_package
Version: $VERSION
Section: misc
Priority: optional
Architecture: $ARCH
Maintainer: XGC2 <apt@example.com>
Depends: $depends
Description: $description
 XGC2 Wheeltec ROS $ROS_DISTRO package generated from the directly hosted
 vehicle source and split by the supported ROS package boundary.
EOF
}

write_readme() {
  local package_root="$1"
  local deb_package="$2"
  local ros_package="$3"

  mkdir -p "$package_root/usr/share/doc/$deb_package"
  cat > "$package_root/usr/share/doc/$deb_package/README" <<EOF
$deb_package

ROS package:
  $ros_package

Version:
  $VERSION

Install prefix:
  $PREFIX
EOF
}

build_deb() {
  local deb_package="$1"
  local ros_package="$2"
  local depends="$3"
  local description="$4"
  local package_root="$BUILD_DIR/$deb_package"
  local deb_path="${OUTPUT_DIR}/${deb_package}_${VERSION}_${ARCH}.deb"

  mkdir -p "$package_root"
  copy_ros_package_paths "$ros_package" "$package_root"

  if [[ ! -f "$package_root$PREFIX/share/$ros_package/package.xml" ]]; then
    echo "missing installed package.xml for $ros_package" >&2
    exit 1
  fi

  write_control "$package_root" "$deb_package" "$depends" "$description"
  write_readme "$package_root" "$deb_package" "$ros_package"

  find "$package_root" -type d -exec chmod 0755 {} +
  find "$package_root" -type f -exec chmod 0644 {} +
  chmod 0755 "$package_root/DEBIAN"
  chmod 0644 "$package_root/DEBIAN/control"

  if [[ -d "$package_root$PREFIX/lib/$ros_package" ]]; then
    find "$package_root$PREFIX/lib/$ros_package" -type f -exec chmod 0755 {} +
  fi
  if [[ -d "$package_root$PREFIX/share/$ros_package/scripts" ]]; then
    find "$package_root$PREFIX/share/$ros_package/scripts" -type f -exec chmod 0755 {} +
  fi

  fakeroot dpkg-deb --build "$package_root" "$deb_path" >/dev/null
}

driver_deb="ros-$ROS_DISTRO-xgc2-wheeltec-driver"
autostart_deb="ros-$ROS_DISTRO-xgc2-wheeltec-onboard-autostart"
onboard_deb="ros-$ROS_DISTRO-xgc2-wheeltec-onboard"
lidar_msgs_deb="ros-$ROS_DISTRO-xgc2-wheeltec-lslidar-msgs"
lidar_driver_deb="ros-$ROS_DISTRO-xgc2-wheeltec-lslidar-driver"
lidar_meta_deb="ros-$ROS_DISTRO-xgc2-wheeltec-lslidar"

build_driver_deb() {
  local deb_package="$1"
  local ros_package="turn_on_wheeltec_robot"
  local package_root="$BUILD_DIR/$deb_package"
  local deb_path="${OUTPUT_DIR}/${deb_package}_${VERSION}_${ARCH}.deb"

  mkdir -p "$package_root"
  copy_ros_package_paths "$ros_package" "$package_root"
  if [[ ! -f "$package_root$PREFIX/share/$ros_package/package.xml" ]]; then
    echo "missing installed package.xml for $ros_package" >&2
    exit 1
  fi

  write_control "$package_root" "$deb_package" \
    "udev, ros-$ROS_DISTRO-geometry-msgs, ros-$ROS_DISTRO-nav-msgs, ros-$ROS_DISTRO-roscpp, ros-$ROS_DISTRO-roslaunch, ros-$ROS_DISTRO-serial, ros-$ROS_DISTRO-sensor-msgs, ros-$ROS_DISTRO-std-msgs, ros-$ROS_DISTRO-tf" \
    "XGC2 Wheeltec serial chassis driver"
  write_readme "$package_root" "$deb_package" "$ros_package"

  cat > "$package_root/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
if [ "\$1" = "configure" ]; then
  SRC=$PREFIX/share/$ros_package/udev
  if [ -d "\$SRC" ]; then
    mkdir -p /etc/udev/rules.d
    for f in "\$SRC"/*.rules; do
      [ -f "\$f" ] || continue
      dest="/etc/udev/rules.d/\$(basename "\$f")"
      if [ ! -e "\$dest" ]; then
        cp "\$f" "\$dest"
      fi
    done
    if command -v udevadm >/dev/null 2>&1; then
      udevadm control --reload-rules >/dev/null 2>&1 || true
      udevadm trigger >/dev/null 2>&1 || true
    fi
  fi
  if id wheeltec >/dev/null 2>&1; then
    usermod -aG dialout wheeltec >/dev/null 2>&1 || true
  fi
fi
exit 0
EOF

  find "$package_root" -type d -exec chmod 0755 {} +
  find "$package_root" -type f -exec chmod 0644 {} +
  chmod 0755 "$package_root/DEBIAN"
  chmod 0644 "$package_root/DEBIAN/control"
  chmod 0755 "$package_root/DEBIAN/postinst"
  if [[ -d "$package_root$PREFIX/lib/$ros_package" ]]; then
    find "$package_root$PREFIX/lib/$ros_package" -type f -exec chmod 0755 {} +
  fi
  if [[ -d "$package_root$PREFIX/share/$ros_package/scripts" ]]; then
    find "$package_root$PREFIX/share/$ros_package/scripts" -type f -exec chmod 0755 {} +
  fi
  fakeroot dpkg-deb --build "$package_root" "$deb_path" >/dev/null
}

build_autostart_deb() {
  local deb_package="$1"
  local ros_package="wheeltec_onboard_autostart"
  local package_root="$BUILD_DIR/$deb_package"
  local deb_path="${OUTPUT_DIR}/${deb_package}_${VERSION}_${ARCH}.deb"

  mkdir -p "$package_root"
  copy_ros_package_paths "$ros_package" "$package_root"
  if [[ ! -f "$package_root$PREFIX/share/$ros_package/package.xml" ]]; then
    echo "missing installed package.xml for $ros_package" >&2
    exit 1
  fi

  mkdir -p \
    "$package_root/etc/xgc2/wheeltec" \
    "$package_root/lib/systemd/system"
  cp -a "$PREFIX_ROOT/share/$ros_package/config/onboard.env" \
    "$package_root/etc/xgc2/wheeltec/onboard.env"
  cp -a "$PREFIX_ROOT/share/$ros_package/systemd/"* \
    "$package_root/lib/systemd/system/"

  write_control "$package_root" "$deb_package" \
    "udev, ros-$ROS_DISTRO-roslaunch, ros-$ROS_DISTRO-swarm-ros-bridge (>= 1.1.0-12), $driver_deb (>= $VERSION)" \
    "XGC2 Wheeltec autostart compose and install-only units"
  write_readme "$package_root" "$deb_package" "$ros_package"

  cat > "$package_root/DEBIAN/conffiles" <<EOF
/etc/xgc2/wheeltec/onboard.env
EOF

  cat > "$package_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
  if id wheeltec >/dev/null 2>&1; then
    usermod -aG dialout wheeltec >/dev/null 2>&1 || true
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    # Vendor boot units stay on disk but must not race the product units.
    systemctl disable --now turn_on_wheeltec_robot.service >/dev/null 2>&1 || true
    systemctl disable --now swarm_ros_bridge.service >/dev/null 2>&1 || true
    systemctl disable --now teststartup.service >/dev/null 2>&1 || true
    # Install-only: never enable product units here.
    systemctl disable xgc2-wheeltec-lidar.service >/dev/null 2>&1 || true
  fi
fi
exit 0
EOF

  cat > "$package_root/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "deconfigure" ]; then
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now xgc2-wheeltec-chassis.service >/dev/null 2>&1 || true
    systemctl disable --now xgc2-wheeltec-swarm-ros-bridge.service >/dev/null 2>&1 || true
    systemctl disable --now xgc2-wheeltec-lidar.service >/dev/null 2>&1 || true
  fi
fi
exit 0
EOF

  cat > "$package_root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
fi
exit 0
EOF

  find "$package_root" -type d -exec chmod 0755 {} +
  find "$package_root" -type f -exec chmod 0644 {} +
  chmod 0755 "$package_root/DEBIAN"
  chmod 0644 "$package_root/DEBIAN/control" "$package_root/DEBIAN/conffiles"
  chmod 0755 "$package_root/DEBIAN/postinst" "$package_root/DEBIAN/prerm" "$package_root/DEBIAN/postrm"
  if [[ -d "$package_root$PREFIX/lib/$ros_package" ]]; then
    find "$package_root$PREFIX/lib/$ros_package" -type f -exec chmod 0755 {} +
  fi
  find "$package_root/lib/systemd/system" -type f -exec chmod 0644 {} +
  chmod 0644 "$package_root/etc/xgc2/wheeltec/onboard.env"
  fakeroot dpkg-deb --build "$package_root" "$deb_path" >/dev/null
}

build_driver_deb "$driver_deb"
build_autostart_deb "$autostart_deb"
build_deb "$onboard_deb" "wheeltec_onboard" "$driver_deb (>= $VERSION), $autostart_deb (>= $VERSION)" "XGC2 Wheeltec install-set metapackage"
if [[ -f "$PREFIX_ROOT/share/lslidar_msgs/package.xml" ]]; then
  build_deb "$lidar_msgs_deb" "lslidar_msgs" "ros-$ROS_DISTRO-std-msgs, ros-$ROS_DISTRO-message-runtime" "XGC2 Wheeltec LeiShen lidar messages"
  build_deb "$lidar_driver_deb" "lslidar_driver" "ros-$ROS_DISTRO-roscpp, ros-$ROS_DISTRO-sensor-msgs, ros-$ROS_DISTRO-pcl-ros, ros-$ROS_DISTRO-pcl-conversions, $lidar_msgs_deb (>= $VERSION)" "XGC2 Wheeltec LeiShen serial lidar driver"
  build_deb "$lidar_meta_deb" "lslidar" "$lidar_msgs_deb (>= $VERSION), $lidar_driver_deb (>= $VERSION)" "XGC2 Wheeltec LeiShen lidar metapackage"
fi

find "$OUTPUT_DIR" -maxdepth 1 -type f -name "*.deb" -print | sort
