# Multiplayer link interface

`multiplayer_link` is the game-facing link layer on top of the tested UART
byte and packet modules. The standalone two-board `enemy_test_top` uses it to
relay controls, game state, and zombie render positions.

## Roles and rates

Both boards use the same RTL and select a role through `host_mode`:

- Host (`host_mode=1`) accepts client controls, replies to the protocol
  handshake, and sends its current snapshot every 50 ms.
- Client (`host_mode=0`) sends its controls every 20 ms and sends a handshake
  every 250 ms until the host replies.
- Either side drops `link_up` after 500 ms without a valid packet. The client
  then resumes its handshake attempts.

All intervals are clock-cycle parameters. Defaults assume a 100 MHz Basys 3
clock. UART settings remain 115200 baud, 8 data bits, no parity, 1 stop bit.

## Packet payloads

The existing packet format is `A5, type, length, payload, checksum`, with the
8-bit checksum equal to the sum of type, length, and payload.

| Type | Sender | Length | Payload |
|---|---|---:|---|
| `03` HELLO | Client | 1 | Protocol version `01` |
| `04` HELLO_ACK | Host | 1 | Protocol version `01` |
| `10` INPUT | Client | 2 | Sequence byte, controls byte |
| `20` STATE | Host | 16 | Sequence byte, then 15 snapshot bytes |
| `21` ZOMBIES | Host | 10 | Sequence byte, active mask, eight tile-coordinate bytes |

The control byte is passed through unchanged to `remote_controls`; its bit
assignment belongs to the game top. `remote_controls_valid` pulses when a
valid input packet arrives. `client_snapshot_valid` pulses when a state packet
arrives.

The 15-byte state snapshot is intentionally opaque to this module. In the demo,
the low 88 bits contain game state `[87:85]`, wave `[84:78]`, player tiles
`[77:70]` and `[69:62]`, health `[61:60]` and `[59:58]`, aim `[57:56]` and
`[55:54]`, active-zombie mask `[53:46]`, shot counters `[45:42]` and `[41:38]`,
and map seed `[37:22]`; mode bit `[21]` reports the host's 2-player selection.
The upper 32 bits are zero. The `ZOMBIES` payload carries
the same active mask followed by eight 8-bit tile coordinates (Y nibble then X
nibble); the client uses these to render the host's enemy positions. Both
boards use fixed seed `1ACE`, so they generate the same map without transferring
all 256 map bits.

Snapshot bit `[21]` carries the host's selected 2-player mode. The host only
activates Player 2 in enemy targeting and combat when this bit's source mode is
selected and the client link is up.

## Current repository integration status

The local `feature/gokul_uart` branch includes the map/game/UI and enemy modules
from `fawaz-zombie-ai` and a standalone `enemy_test_top` build target. Both
boards run the deterministic map. The host owns zombie simulation and sends
the state and render positions; controls and shot events from the client are
used by the host's two-player enemy simulation. The raw-byte UART test remains
available as a wiring diagnostic. Physical gameplay still needs to be checked
after programming the generated bitstream on both boards.
