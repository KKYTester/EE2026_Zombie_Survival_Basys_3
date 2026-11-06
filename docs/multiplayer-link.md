# Two-board link

`My_Top_Module` links two boards with `peer_link` (`FDP2026.srcs/sources_1/new/uart/peer_link.v`),
a symmetric link on top of the UART byte and packet modules. There is no host
and no client: both boards run the same bitstream and send the same packet.

## Packet

UART 115200 baud, 8 data bits, no parity, 1 stop bit. Framing from
`packet_tx`/`packet_rx`: `A5, type, length, payload, checksum`, with the 8-bit
checksum equal to the sum of type, length and payload.

| Type | Length | Payload | Rate |
|---|---:|---|---|
| `30` STATUS | 15 | Sequence byte, 14 status bytes | Every 20 ms from each board |
| `31` ZOMBIES | 26 | Sequence byte, 25 zombie bytes | Every 20 ms from the leader during a shared run |

`link_up` rises on the first valid STATUS packet and falls after 500 ms without
one. All periods are clock-cycle parameters (100 MHz defaults).

## Status word

| Bits | Field |
|---|---|
| `[2:0]` | Game state (0 title, 1 generating, 3 playing, 4 game over, 5 victory) |
| `[3]` | Current/last run is a 2-player run |
| `[4]` | This board is the leader (picked the map) |
| `[12:5]` | Game token: the leader's new token, or the token a follower joined |
| `[28:13]` | Start priority (random, breaks simultaneous starts) |
| `[44:29]` | Map seed (final once the leader is playing) |
| `[51:45]` | Wave |
| `[53:52]` | Hearts |
| `[69:54]` | Position x (Q4.12 tiles, east) |
| `[85:70]` | Position y (Q4.12 tiles, north) |
| `[95:86]` | View angle (1024 per turn, 0 = north, clockwise) |
| `[99:96]` | Shot counter (each change is one new shot) |
| `[101:100]` | Leader only: the follower's hearts (the leader tracks them) |
| `[108:102]` | Leader only: zombies left in the wave |

## Zombie word (leader to follower)

| Bits | Field |
|---|---|
| `[95:0]` | Eight zombie x positions, 12 bits each (Q4.8 tiles, x right) |
| `[191:96]` | Eight zombie y positions, 12 bits each (Q4.8 tiles, y down) |
| `[199:192]` | Active mask |

## Joining a game (`game_flow`)

- A board that starts 2 PLAYERS becomes the leader with a new token.
- A linked board on its title screen that sees a leader in GENERATING or
  PLAYING with a token it has not joined yet becomes its follower.
- A follower waits until the leader is PLAYING (its seed is then final),
  regenerates the map from that seed (the generator is deterministic, so the
  map and spawns match) and starts its own run.
- If both boards lead at once, the one with the lower start priority (or the
  one whose partner is already playing) becomes the follower.
- After a run, a board returning to the title keeps its token, so it never
  re-joins the run its partner is still playing.

## Shared run

The leader runs `wave_controller` and `enemy_manager` (`TWO_PLAYERS=1`) for
both players. Player 2 is the follower: its position (`player2_pos_*`,
`player2_tile`), its camera pose for shots (`camera2_*`), and a shot pulse for
each change of its shot counter. Zombies follow the two-goal BFS field, so each
one heads for the nearer player. The leader counts the follower's hearts from
`player_hit_p2` and returns them in the status word. The follower does not
spawn or move zombies; it draws the leader's zombie word and shows the leader's
wave and zombies-left count. A player with no hearts is frozen; the leader ends
the run when both are down or the last wave is won, and the follower's run ends
with the leader's. Both boards draw the other player from its position (sprite
slot 8 of `zombie_renderer`, `SLOTS=9`, `HAS_ALLY=1`) and as a yellow tile on
the SW0 map.

The older host/client `multiplayer_link` module remains in the source tree
with its own testbench but is not used by `My_Top_Module`.
