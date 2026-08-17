cmake_minimum_required(VERSION 2.8.3)
project(wheeltec_swarm_ros_bridge)

find_package(catkin REQUIRED)

catkin_package()

install(DIRECTORY config launch
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
)
