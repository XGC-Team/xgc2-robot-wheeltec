cmake_minimum_required(VERSION 2.8.3)
project(turn_on_wheeltec_robot)

find_package(catkin REQUIRED COMPONENTS
  geometry_msgs
  nav_msgs
  roscpp
  serial
  sensor_msgs
  std_msgs
  tf
)

add_compile_options(-std=c++11)

catkin_package(
  CATKIN_DEPENDS
    geometry_msgs
    nav_msgs
    roscpp
    serial
    sensor_msgs
    std_msgs
    tf
)

include_directories(
  include
  ${catkin_INCLUDE_DIRS}
)

add_executable(wheeltec_robot_node
  src/wheeltec_robot.cpp
  src/Quaternion_Solution.cpp
)
target_link_libraries(wheeltec_robot_node
  ${catkin_LIBRARIES}
)

install(TARGETS wheeltec_robot_node
  RUNTIME DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

# Only the XGC2-supported chassis entry point is installed.  The upstream
# navigation/camera launch files reference components that are not part of
# this product yet.
install(FILES launch/wheeltec_robot.launch
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/launch
)

install(DIRECTORY udev/
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/udev
  FILES_MATCHING PATTERN "*.rules"
)

install(PROGRAMS scripts/install_wheeltec_controller_udev_rule.sh
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/scripts
)
