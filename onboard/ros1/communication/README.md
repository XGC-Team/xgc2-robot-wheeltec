# Wheeltec ROS1 communication

The official `swarm_ros_bridge` binary comes from APT
`ros-melodic-swarm-ros-bridge`. There is no vehicle YAML/launch wrapper
package. Autostart launches `bridge_node` with
`/etc/xgc2/wheeltec/ros_topics.yaml`, which `Wheeltec · configure network`
writes. systemd lives in `onboard/ros1/autostart`.
