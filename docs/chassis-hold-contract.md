# Chassis hold v1

The private UDP Hub is retired. The platform control route uses the installed
`XgcChassisHold::Server` component and the actual XRPC HTTP SDK.
One native chassis process owns one Unix endpoint; world embedding shares its
framework's existing endpoint and instance. `hold_robot_id` and `hold_socket`
are explicit launch inputs. The systemd unit owns `/run/xgc2-wheeltec-chassis` (0700),
and its socket is `/run/xgc2-wheeltec-chassis/hold.sock`. The process exports a fresh
instance ID; a caller must discover and bind that instance before mutations.

`GET /v1/chassis/descriptor` is the explicit discovery method. It returns the
ServiceRef (`target_id`, service `chassis.hold`, API version `1`, instance ID,
profile `http.v1`, Unix address), fixed robot roster, batch and queue bounds,
and completion capability. Empty/wildcard robot IDs are rejected.

`POST /v1/chassis/hold` accepts exactly this JSON schema, with unsigned integer
CAS revision and 1..16 distinct registered robot IDs:

```json
{"expected_revision":0,"changes":[{"robot_id":"site-robot-01","held":true}]}
```

`GET /v1/chassis/hold` observes the native state after earlier admitted queue
entries. The initial revision is 0 and gates are open. A successful POST returns
200 only after the sole native command owner masks the complete affected batch,
applies zero for every affected robot, and returns from those command writes.
Release (`held:false`) also writes zero before opening the gate. A receipt is:

```json
{"stage":"applied","revision":1,"completion":"command-gated","physical_stop_confirmed":false,"robots":[{"robot_id":"site-robot-01","held":true}],"changes":[{"robot_id":"site-robot-01","requested_held":true,"zero_applied":true}]}
```

A stale revision returns 409 without a command write. Schema failures return
400, oversized payloads 413, and full admission returns 429 or SDK connection
rejection. A native write failure returns 503 (`stage:failed`); all affected
gates stay held, individual `zero_applied` values expose partial writes, and
the revision advances because hardware effects cannot be rolled back. A queued
deadline/cancellation produces `not-applied` (504/499) when a response remains
possible. A caller that disconnects or times out after execution starts has
unknown delivery and must observe the instance/revision; the client must not
replay a mutation automatically. Transport receipt, physical velocity zero,
and board acknowledgement are separate facts. This provider supports only
`command-gated`, always reports `physical_stop_confirmed:false`, and exposes
`physical_stop_supported:false` in discovery.

The provider's one IO owner performs HTTP/JSON/identity work. It passes only
fixed plain commands through 32 retained slots to one fixed native executor.
The native tick processes at most 16 queue entries by default, with no socket,
JSON, transport reply, allocation, or new thread. Cancelled callers retain
admission until their native work terminates. Embedded providers create no
listener or worker: the framework IO owner calls `handle` and `finish`, and
its native owner calls `control_tick` and `held(index)` against a fixed roster.
Native command work must quiesce before destroying the provider; queued work
is then aborted, IO is joined, retained replies are released, and the endpoint
lease ends after the native output context has stopped. An executing request
keeps the old source owner fenced even if its caller leaves.

The composition root captures only explicit reserved `XGC2_XRPC_*` environment
settings once. `GET /v1/chassis/runtime-policy` reports the actually resolved
SDK policy and source; this provider exposes no live policy mutation. Product
ceilings are 32 connections/inflight, 4096 header/request bytes, 8192 response
bytes, and 250 ms call time. Unknown, unsupported, and over-ceiling settings
fail before opening an endpoint. Embedded routes consume their existing
framework policy, still enforcing their own 4096-byte and 250-ms domain bounds.
The hold roster, revision, queue and replies are process-local memory; this
route adds no durable state or history store. The only transport filesystem
writes are the SDK-owned lease/socket in the explicitly owned runtime directory.

`test/CMakeLists.txt` consumes installed dependencies and exercises real Unix
HTTP, CAS, batch masking, partial native failure, release zero, native output
thread ownership, allocation-free gate/idle queries, malformed payloads, stale instance,
deadline, retained cancellation, overload, queued/executing shutdown lifetime,
and framework embedding. The workflow tests amd64/arm64 plain and ASan/UBSan,
including the installed SDK libraries. The workflow pins exact XRPC,
state-machine and chassis-hold source revisions and uses the controlled Focal
build image. HOLD is supplied by xgc2-chassis-hold, without a robotics-interfaces
dependency.

Installed-consumer build:

```sh
cmake -S test -B build/chassis-hold-test -DCMAKE_PREFIX_PATH=/path/to/installed/prefix
cmake --build build/chassis-hold-test --parallel 2
ctest --test-dir build/chassis-hold-test --output-on-failure
```

The State and Server public APIs require C++17. Rpc integration and the SDK
implementation require C++20. Controlled Focal builds use clang++-10 with the
matching libstdc++ runtime. JSON-HTTP encoding belongs to XRPC; JsonCpp >=1.7.4
is used only by the independent test peer. State-machine transitions may
allocate in their bounded diagnostics; native gate/idle queries do not allocate.
No maintained Bionic XRPC package or vehicle-compatible Bionic toolchain/ABI
has been validated. Source and isolated Focal tests do not establish a vehicle
installation or measured physical stop.
The existing native CAN/serial protocol and user ROS topics remain their device
and algorithm interfaces.

Wheeltec wiring: `Control` drains the management queue before its bounded serial
sensor read; `ros::spinOnce` and `Cmd_Vel_Callback` use the same native owner.
The zero sink calls the original `WriteMotion` and reports success only when
all 11 bytes of the native zero frame are written. Serial read timeout is
10 ms and write timeout is 100 ms. Shutdown writes zero and closes serial
before releasing the provider. This write result is not a board receipt or
proof of physical stop.

Optional isolated device-output fixture (both built device targets required):

```sh
. /path/to/isolated-catkin/devel/setup.bash
/usr/bin/python3 test/ros_device_output_test.py \
  --devel /path/to/isolated-catkin/devel --helpers build/chassis-hold-test
```

The fixture owns a random-port ROS master and private temporary ROS home/logs,
pauses ROS time, and tests the actual simulated Scout messenger plus actual
Wheeltec serial frames through a PTY. A fixture-only DTR/RTS ioctl shim permits
PTY modem operations; data bytes still use the actual serial library. It
checks hold masking under ongoing nonzero ROS commands, stale CAS, release,
normal SIGINT and socket cleanup. No CAN, real serial device, physical chassis
or existing ROS master is used. The actual Scout worker lifetime also has a
catkin CTest entry `chassis_worker_lifetime`, without opening any device.
