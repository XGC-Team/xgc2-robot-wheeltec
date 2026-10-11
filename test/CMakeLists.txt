cmake_minimum_required(VERSION 3.10)
project(WheeltecHoldTests LANGUAGES CXX)
include(CTest)
find_package(PythonInterp 3 REQUIRED)

set(WHEELTEC_DEVEL_PREFIX "" CACHE PATH "Catkin devel space containing the Wheeltec driver")
if(NOT WHEELTEC_DEVEL_PREFIX)
  message(FATAL_ERROR "WHEELTEC_DEVEL_PREFIX must name the built catkin devel space")
endif()

add_library(pty_modem_shim SHARED pty_modem_shim.cpp)
target_compile_features(pty_modem_shim PRIVATE cxx_std_17)
target_compile_options(pty_modem_shim PRIVATE -Wall -Wextra -Werror)
target_link_libraries(pty_modem_shim PRIVATE ${CMAKE_DL_LIBS})

add_test(NAME wheeltec_hold COMMAND ${PYTHON_EXECUTABLE}
  ${CMAKE_CURRENT_SOURCE_DIR}/ros_device_output_test.py
  --devel ${WHEELTEC_DEVEL_PREFIX} --helpers ${CMAKE_CURRENT_BINARY_DIR})
set_tests_properties(wheeltec_hold PROPERTIES TIMEOUT 240)
