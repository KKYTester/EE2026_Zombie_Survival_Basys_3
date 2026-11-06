# Multiplayer link interface

`multiplayer_link` is the game-facing link layer on top of the tested UART
byte and packet modules. `My_Top_Module` uses it to
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
| `10` INPUT | Client | 1 + `INPUT_BYTES` | Sequence byte, controls |
| `20` STATE | Host | 16 | Sequence byte, then 15 snapshot bytes |
| `21` ZOMBIES | Host | 10 | Sequence byte, active mask, eight tile-coordinate bytes |

`INPUT_BYTES` is a module parameter (default 1). The control bytes are passed
through unchanged to `remote_controls`; `remote_controls_valid` pulses when a
valid input packet arrives. `client_snapshot_valid` pulses when a state packet
arrives.

## Use in My_Top_Module

`My_Top_Module` uses `INPUT_BYTES=7` and 20 ms input/state periods. SW1 low
selects the host (Player 1), SW1 high the Player 2 board.

Player 2 input (56 bits): x `[15:0]` and y `[31:16]` (north-up Q4.12 tile
coordinates), view angle `[41:32]`, shot counter `[45:42]` (each change is a
new shot), playing flag `[46]`. The host ignores packets whose playing flag is
low, so poses from a previous or not-yet-started run never move Player 2.

Host snapshot (low 46 bits used): game state `[2:0]`, 2-player run `[3]`,
wave `[10:4]`, zombies left `[17:11]`, Player 1 hearts `[19:18]`, Player 2
hearts `[21:20]`, map seed `[37:22]`, Player 1 tile `[45:38]`. The ZOMBIES
payload is the active mask followed by eight `{y,x}` tile bytes.

The Player 2 board follows the host's state only while bit `[3]` is set and the
link is up. When the host is PLAYING, its seed is final; Player 2 regenerates
the map from that seed (the generator is deterministic, so the map and spawns
match) and starts its own run.
