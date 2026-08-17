# Wheeltec ROS1 sensors

Optional hardware drivers only. This tree currently has **lidar**.
No camera package until `/dev/video*` exists on a vehicle.

```text
src/lidar/lslidar_msgs
src/lidar/lslidar_driver
src/lidar/lslidar          (metapackage)
```

Serial LeiShen driver. Live vehicle: CP2102 `10c4:ea60` serial `0001`
→ `/dev/wheeltec_lidar`. Launch `lslidar_serial.launch` uses
`lidar_name=M10` and publishes `/scan`. Not part of the chassis install set.
