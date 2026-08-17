# Wheeltec ROS1 autostart workspace

Owns compose launches and (later) every onboard systemd unit. Sibling of
`chassis`, `communication`, and `sensors`.

Site identity lives in `/etc/xgc2/wheeltec/onboard.env`. Units only
`EnvironmentFile` that path. Copy packaged `config/onboard.env` there on
first install if missing.

Install-only by default: the package does not enable or start any unit.

```text
src/wheeltec_onboard_autostart
  launch/chassis.launch
  launch/swarm.launch
  launch/lidar.launch
  launch/wheeltec.launch     # chassis + swarm; lidar optional
  systemd/xgc2-wheeltec-chassis.service
  systemd/xgc2-wheeltec-swarm-ros-bridge.service
  systemd/xgc2-wheeltec-lidar.service
```
