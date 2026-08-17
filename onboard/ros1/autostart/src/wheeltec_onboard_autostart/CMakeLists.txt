cmake_minimum_required(VERSION 2.8.3)
project(wheeltec_onboard_autostart)

find_package(catkin REQUIRED)

catkin_package()

install(PROGRAMS
  scripts/start-chassis
  scripts/start-swarm-ros-bridge
  scripts/start-lidar
  scripts/wait-device
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(DIRECTORY launch
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
)

install(FILES
  config/onboard.env
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/config
)

install(DIRECTORY systemd
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
)
