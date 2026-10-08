cmake_minimum_required(VERSION 3.16)
project(ChassisHoldNativeTests LANGUAGES CXX)
include(CTest)
find_package(XgcRoboticsInterfaces CONFIG REQUIRED COMPONENTS ChassisHold)
find_package(Threads REQUIRED)
add_executable(chassis_hold_native_test chassis_hold_native_test.cpp)
target_compile_features(chassis_hold_native_test PRIVATE cxx_std_20)
target_compile_options(chassis_hold_native_test PRIVATE -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(chassis_hold_native_test PRIVATE XgcRoboticsInterfaces::ChassisHold Threads::Threads)
# An explicitly supplied isolated source include is useful before the common
# owner publishes its install; normal CI/deployment consumes the package.
if(CHASSIS_HOLD_SOURCE_INCLUDE)
  target_include_directories(chassis_hold_native_test PRIVATE "${CHASSIS_HOLD_SOURCE_INCLUDE}")
endif()
add_test(NAME chassis_hold_native COMMAND chassis_hold_native_test)
set_tests_properties(chassis_hold_native PROPERTIES TIMEOUT 20)

# Optional ROS/device-output fixture helpers; not part of installed products.
add_executable(chassis_hold_peer chassis_hold_peer.cpp)
target_link_libraries(chassis_hold_peer PRIVATE XgcRoboticsInterfaces::ChassisHold Threads::Threads)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  add_library(pty_modem_shim SHARED pty_modem_shim.cpp)
  target_link_libraries(pty_modem_shim PRIVATE ${CMAKE_DL_LIBS})
endif()
