# Wheeltec ROS1 autostart workspace

Owns compose launches and (later) every onboard systemd unit. Sibling of
`chassis`, `communication`, and `sensors`.

Site identity lives in `/etc/xgc2/wheeltec/onboard.env`. Units only
`EnvironmentFile` that path. Copy packaged `config/onboard.env` there on
first install if missing.

Install-only by default: the package does not enable or start any unit.

Set `XGC2_CHASSIS_ROBOT_ID` to the registered robot id before enabling
`xgc2-wheeltec-chassis.service`. `start-chassis` passes that id to
`chassis.launch`, which includes the driver and its `udp.v1` HOLD endpoint.
`wheeltec.launch` passes the same HOLD arguments through to `chassis.launch`.

| Setting in `onboard.env` | Launch argument | Default |
| --- | --- | --- |
| `XGC2_CHASSIS_HOLD_PORT` | `hold_port` | `19530` |
| `XGC2_CHASSIS_HOLD_KEY_FILE` | `hold_key_file` | `/etc/xgc2/chassis-hold.key` |
| `XGC2_CHASSIS_HOLD_BOOT_HELD` | `hold_boot_held` | `false` |
| `XGC2_CHASSIS_HOLD_REQUIRED` | `hold_required` | `true` |

Provision the key before starting the service. The unit runs as `wheeltec`,
so a root-owned 0600 key is unreadable by it; site setup must resolve that
ownership conflict. See the [driver HOLD contract](../../../docs/chassis-hold-contract.md).
An unusable required key or an unrecoverable serial fault ends the driver;
the unit's existing `Restart=always` and `RestartSec=5` restart the launch.

```text
src/wheeltec_onboard_autostart
  launch/chassis.launch
  launch/swarm.launch
  launch/lidar.launch
  launch/wheeltec.launch     # chassis + swarm; lidar optional
  systemd/xgc2-wheeltec-roscore.service
  systemd/xgc2-wheeltec-chassis.service
  systemd/xgc2-wheeltec-swarm-ros-bridge.service
  systemd/xgc2-wheeltec-lidar.service
```
