# Two-board link

`My_Top_Module` links two boards with `peer_link` (`FDP2026.srcs/sources_1/new/uart/peer_link.v`),
a symmetric link on top of the UART byte and packet modules. There is no host
and no client: both boards run the same bitstream and send the same packet.

## Packet

UART 115200 baud, 8 data bits, no parity, 1 stop bit. The game uses
`A5, type, length, payload, CRC high, CRC low`. CRC-16/CCITT-FALSE covers type,
length and payload (polynomial `0x1021`, initial value `0xffff`). Program both
boards with the updated bitstream; the earlier game protocol is incompatible.

| Type | Length | Payload | Rate |
|---|---:|---|---|
| `30` STATUS | 25 | Sequence byte, 24 status bytes | Every 20 ms from each board |
| `31` ZOMBIES | 30 | Same sequence byte, 29 zombie bytes | After the leader's STATUS during a shared run |

The two payloads are sampled together. The receiver accepts a zombie update
only once, after the STATUS with the same sequence, and renders it only for
the current game token. New STATUS frames refresh `link_up`; duplicate STATUS
frames and orphan zombie frames do not. The link times out after 500 ms
without a new valid STATUS. Status sequence gaps and UART/CRC faults are
counted separately and latched on LED9 and LED10 respectively until reset.

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
| `[99:96]` | Local shot count (diagnostic only; wraps every 16 shots) |
| `[101:100]` | Leader only: the follower's hearts (the leader tracks them) |
| `[108:102]` | Leader only: zombies left in the wave |
| `[112]` | Follower only: queued shot is valid |
| `[120:113]` | Follower only: queued shot event ID |
| `[136:121]`, `[152:137]`, `[162:153]` | Follower only: shot X, Y and angle captured when fired, in the same units as pose |
| `[170:163]` | Leader only: most recently accepted follower shot ID |
| `[171]`, `[173:172]` | Leader only: wave-clear pause and follower hit counter |
| `[182:176]`, `[189:183]` | Leader only: P1 and P2 kill scores |

## Zombie word (leader to follower)

| Bits | Field |
|---|---|
| `[95:0]` | Eight zombie x positions, 12 bits each (Q4.8 tiles, x right) |
| `[191:96]` | Eight zombie y positions, 12 bits each (Q4.8 tiles, y down) |
| `[199:192]` | Active mask |
| `[207:200]` | Game token |
| `[223:208]` | Two-bit health value per zombie |
| `[231:224]` | One attack-warning bit per zombie, slot 0 in bit 224 |

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
both players. It uses the follower's live position for movement and contact
checks, and the firing pose from each shot event for combat. The follower
holds up to four shots in a FIFO and retransmits its head in every STATUS
until the leader acknowledges it. The leader accepts only the next expected
ID while its Player 2 combat mailbox is ready. IDs wrap modulo 256. A reset
follower resumes after the leader's retained ACK, without replaying an old
shot. If the FIFO is full, the weapon does not spend a round until a new fire
press can be accepted. Queued shots are cleared on leaving the shared run.

Zombies follow the shortest walkable route to a living player. The shared field
rebuilds when a living player changes tiles or goes down. Each movement update
checks the route for the zombie's current tile and can reverse an ongoing move
within its reserved footprint.

Successful spawns alternate which player's side gets priority, using walking
distance to define the sides. The search prefers at least eight hops from both
living players. If the preferred side has no such tile, it tries the farthest
free tile on that side, with a two-hop minimum, before using the other side.
With one survivor, the search uses that player alone.

The leader starts and resolves zombie attacks. An attacker pauses and turns
amber for about a quarter-second, then checks range and walls against the
original target. A miss or a hit is followed by a brief recovery. Both boards
draw the warning from the leader's snapshot.

The leader counts the follower's hearts from
`player_hit_p2` and returns them in the status word. The follower does not
spawn or move zombies; it draws the leader's zombie word and shows the leader's
wave and zombies-left count. A player with no hearts is frozen; the leader ends
the run when both are down or the last wave is won, and the follower's run ends
with the leader's. Both boards draw the other player from its position (sprite
slot 8 of `zombie_renderer`, `SLOTS=9`, `HAS_ALLY=1`) and as a yellow tile on
the SW0 map.

The older host/client `multiplayer_link` module remains in the source tree
with its own testbench but is not used by `My_Top_Module`.
