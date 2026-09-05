# Chassis Hold UDP lifetime and framing

The v1 endpoint accepts exactly 44 bytes. A longer datagram is rejected as a
whole even when its first 44 bytes resemble a valid command; the receive buffer
has one extra byte so truncation cannot masquerade as an exact-size frame.
The port, ACK fields, exact robot matching and empty-id fallback are unchanged.

`Hub::remove(gate)` is a lifetime barrier for dispatches made by the Hub. The
Gate and its ZeroFn context must remain alive until remove returns. The Hub
holds its registration mutex while applying a request and running the synchronous
zero callback, so removal waits for an in-progress callback. ZeroFn must not
synchronously call Hub::add/remove and must finish in bounded time. External
users of Gate::setHeld/fireZero remain responsible for their own lifetime.

Shutdown sets the stop flag, wakes the receive thread with shutdown, joins it,
and only then closes or changes the descriptor. Destruction must not race with
new Hub registrations.

These guarantees do not provide sender authentication, replay prevention,
cmd_vel/hold arbitration, actuator acknowledgment, or a physical emergency stop.
A protocol ACK is not proof of zero chassis velocity. Driver-level command
serialization and hardware safety must be validated separately.

The `Chassis Hold regression` workflow compiles the actual header as C++11 and
runs loopback-only UDP framing and callback-removal tests on amd64/arm64, both
plain and with ASan/UBSan. No ROS, serial port, CAN interface or robot is used.
