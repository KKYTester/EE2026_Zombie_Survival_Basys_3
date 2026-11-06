# Enemy subsystem interface - provisional v0.1

Owner: Fawaz. Recorded: 2026-11-03. Status: proposed for team review.

## Main integration update (2026-11-06)

Smooth movement adds `spawn_occupied`, which combines actual occupancy with
segment reservations. Feed it to `game_core` with `USE_SPAWN_OCCUPANCY=1`.
Continue using `occupied` for shooting. The packed render positions advance
in 32 Q8 substeps per tile. A live trip reserves its origin and destination
until it finishes or the zombie is removed. Reset clears all reservations.

`USE_PLAYER_POSITIONS=1` enables the supplied south-increasing Q8 player
positions for contact distance. The host supplies both players' positions
when using the two-player configuration. The integrated single-player top
converts its live Q12 pose at this boundary.

The integration branch is based on main `83d2f9a`. The current shared player
uses Q12 positions, north-increasing Y and 1024 clockwise angle units per turn.
The host converts its live tile to the map's south-increasing Y for navigation.
The sprite camera receives Q8 position in that map orientation. Camera combat
uses the original Q12 pose with the shared ray caster.

`USE_CAMERA_RAY=1` selects integrated single-player camera shooting. The opt-in
two-player mailboxes currently use the earlier tile/cardinal aiming contract.
Per-player camera poses must be added to that mailbox contract before enabling
camera aiming in a two-player board build.

`Map_Renderer.scene_start` snapshots pose, map and enemy positions together.
The renderer waits for `overlay_ready` before publishing, and exports
`display_bank` and `scene_valid` to the sprite renderer. Wall depths are Q5
tiles and convert to Q8 by appending three zeros. The sprite test fixture keeps
the earlier cardinal projection available for regression testing.

This is Task 1's interface specification, not an implemented enemy subsystem
or a claim of teammate approval. It allows single-player enemy management and
navigation to start while camera and multiplayer details are agreed. No HDL,
Vivado settings, constraints or existing module ports change in this task.

## Source baseline

These remote branch tips were checked on 2026-11-03. Feature sources are not
yet merged into main; their paths below describe those branches.

| Branch | Commit | Relevant sources under `FDP2026.srcs/sources_1/new/` |
|---|---|---|
| `main` | `6121513772f9e4164d2821616d77399b14781e33` | Starter project and project-generation workflow |
| `feature/chuanonn_map_gen` | `400da998e9cd81a7b6e6e90c98686c52a0a419f8` | `game/game_core.v`, `game/wave_controller.v`, `game/spawn_finder.v`, `demo/zombie_stub.v` |
| `raycaster-renderer` | `d564ef756e83ece9f5949d2b56aced01862bc44d` | `Player.v`, `Map_Renderer.v` |
| `feature/gokul_uart` | `c20a5c7076105f6e6458ba506d8de287332232c0` | `uart/packet_tx.v`, `uart/packet_rx.v` |

## Ownership

| Owner | Writes/maintains | Exchanges with enemy subsystem |
|---|---|---|
| Fawaz | Zombie records, navigation, enemy HP, target selection, enemy attacks, zombie sprite projection | Accepts spawns/shots; supplies occupancy, defeats, player hits and enemy state |
| Chuan Onn | Published map, wave scheduling, spawn selection, player health, weapon/reload control, menus/HUD and OLED output | Supplies map, session controls, spawn requests and accepted-shot events |
| Kiat Yang | Player movement/input, camera state and wall raycasting | Supplies player/camera state and wall depth; integrates zombie pixels into world pixels |
| Gokul | UART transport and game packet handling | Supplies remote inputs to the host and transports authoritative state to the client |

One module owns each state register. For example, Fawaz requests player damage;
Chuan Onn's health logic changes the heart count. The host owns enemy gameplay
state; the client may store snapshots and render them but does not simulate
independent enemy HP, movement or deaths.

## Decision register

The 18 entries are grouped interface decisions, not individual signal counts.
"Existing" means present in the inspected code, not formally approved by all
members. Proposed extensions below are not prerequisites for the first
single-player demo.

| ID | Decision | Status and action |
|---|---|---|
| E1 | Map representation | Existing: keep 16x16, 256 bits, 1 = wall, 0 = floor |
| E2 | Tile address | Existing: keep 8-bit `{y[3:0], x[3:0]}`, x right, y down |
| E3 | Map validity | Existing: keep `map_ready`/`map_busy`; published map is immutable during gameplay |
| E4 | Gameplay clock/reset | Existing: keep 100 MHz rising-edge clock and synchronous active-high reset; leave the existing OLED clock arrangement to its owner |
| E5 | Session lifecycle | Existing: playing is `game_state == 3`; honour `enemies_clear` |
| E6 | Spawn handshake | Existing: stable request/tile until acceptance, one acknowledgement per accepted spawn |
| E7 | Occupancy | Existing: keep 256-bit live enemy tile mask |
| E8 | Combat events | Existing: keep one-cycle shot, player-hit and enemy-defeated events; serialize deaths if necessary |
| E9 | Capacity | Existing: retain default eight living enemies; total wave size is a separate limit |
| E10 | Display boundary | Existing: retain 96x64, RGB565, requested pixel coordinates and frame-start signal |
| P1 | Position encoding | Partly specified: 32-bit ports exist; propose the fixed-point convention below |
| P2 | Angle encoding | Partly specified: 32-bit radians, zero north in comments; fractional precision, wrap and rotation direction still require Kiat's agreement |
| P3 | Wall-depth interface | Missing: jointly define camera-depth encoding, per-column access and timing before sprite implementation |
| P4 | Enemy record interface | Incomplete: replace tile-only stub with stable slots and the proposed record fields below |
| P5 | Multiplayer payload | Missing: transport framing exists; agree game packet fields, ordering, identity and snapshot handling with Gokul |
| X1 | Per-player combat | Extend single shot/hit/health/weapon path to distinguish two active players |
| X2 | Spawn avoidance | Extend one-player distance checks to both active players in two-player mode |
| X3 | Shared player state/tick | Expose state and coordinate update timing currently internal to the renderer; initially retain its approximately 24 Hz game tick |

## Existing single-player connections

Directions are relative to Fawaz's enemy/combat subsystem. These are existing
signals to preserve, not a declaration that one new module must contain all
enemy, combat and rendering logic.

| Signal | Width | Direction | Meaning |
|---|---:|---|---|
| `clk` | 1 | In | 100 MHz system clock |
| `rst` | 1 | In | Synchronous active-high reset |
| `published_map` | 256 | In | Tile `16*y+x` is 1 for wall; use only when ready and not busy |
| `map_ready`, `map_busy` | 1 each | In | Published-map validity / generation status |
| `game_state` | 3 | In | Value 3 enables playing |
| `play_start` | 1 | In | New-game initialization pulse |
| `enemies_clear` | 1 | In | Existing expression is `play_start || !playing`; may remain high for many cycles |
| `p1_addr`, `p2_addr` | 8 each | In | Validated initial spawn tiles; these are not moving player positions |
| `spawn_req` | 1 | In | Held spawn request |
| `spawn_tile` | 8 | In | Tile held stable with the request |
| `spawn_ack` | 1 | Out | One-clock acceptance event, only after a slot is allocated |
| `occupied` | 256 | Out | Bit is high if at least one live enemy occupies that tile |
| `shot_fired` | 1 | In | One-clock accepted shot from weapon control, not raw mouse/button level |
| `enemy_defeated` | 1 | Out | Exactly one one-clock event per gameplay death |
| `player_hit` | 1 | Out | One-clock request to remove one player heart |

### Timing rules for the replacement enemy module

- Reset/clear takes priority over spawning, movement and combat. It clears
  active slots, occupancy, cooldowns, pending events and handshake state.
  Clearing enemies does not emit defeat events. Output event signals are low
  while reset/clear is applied.
- At edge N, accept a high `spawn_req` only if playing, map valid, and a free
  slot exists. Store the tile and raise registered `spawn_ack` after that edge.
  At edge N+1, the wave controller samples the acknowledgement and lowers its
  request. Do not accept again until a low request has been sampled. This
  prevents allocating twice while the original request is still high.
- If full, leave `spawn_ack` low and wait. Make a new allocation visible in
  occupancy by the edge where the wave controller samples its acknowledgement.
  Choose an explicit equivalent latency for occupancy updates on moves/deaths.
- Each death is reported once. If multiple deaths are possible in one cycle,
  retain and emit them on successive clocks; never OR several deaths into one
  event. New-game clear discards pending events from the previous session.
- Sample/capture spawn and combat events on every system clock. Movement may
  use a slower enable, but gating all event handling by that enable loses pulses.
- Use nonblocking assignments for clocked state. Both sides sample pre-edge
  values, as in the controller/timer example from the course notes.

## Provisional conventions for starting development

These are Fawaz-side proposals. Keep conversion at module boundaries so a
teammate can use another representation without rewriting the navigation FSM.
Do not silently reinterpret a teammate's existing outputs.

### Coordinates and update timing (P1, X3)

- Retain 32-bit coordinate ports. Propose unsigned positions with
  `COORD_FRAC_BITS = 8`: one tile is 256 stored units; 3.5 tiles is 896.
  The map origin is its top-left corner; x increases right and y down.
- Tile centers are `(tile_index << 8) + 128` for each axis. Valid map coordinates
  are at least zero and less than `16 << 8` (4096). Validate the full integer
  part before extracting its low four bits; otherwise out-of-bounds values wrap.
- Movement deltas are signed two's-complement values at the same scale, per
  game tick. Widen unsigned positions with a leading zero before signed
  subtraction/addition; use at least 33-bit signed coordinate intermediates.
  Check bounds before narrowing. Later products need their own width analysis.
- Kiat's current comments use metres. The proposal is one tile per world unit;
  the metres-to-tiles relationship and velocity interpretation need confirmation.
- Initially retain `GAME_HZ = 24` and a one-system-clock enable pulse. Share the
  tick or define a common snapshot boundary; do not create independent counters
  and assume their phases match. Multi-cycle algorithms latch their input state
  when starting an update and publish a coherent result when done.
- The player update exposes current positions and active-player flags. The
  existing `p1_addr`/`p2_addr` only initialize positions. In the first demo a
  fixed test player is acceptable and must be identified as a stand-in.

### Angles and rendering (P2, P3)

Keep the existing 32-bit angle port and the documented north-zero/radian intent
until Kiat agrees a binary encoding. Do not assume the earlier 4096-steps-per-turn
example is an implemented or approved format. Tile-based navigation can proceed
without angle data; aim-based combat and projection need this resolved first.

Before implementing sprites, jointly specify:

1. Angle fractional bits, full-turn wrap, positive rotation direction and field
   of view (or the camera direction/plane vectors that replace angle inputs).
2. Wall depth for each of the 96 columns, including width, scale, invalid/no-hit
   value, lookup latency and validity. Recommend perpendicular camera-space
   depth for both walls and zombies, not a comparison of different distances.
3. A coherent camera/enemy snapshot for each rendered frame, including when
   preparation finishes relative to pixel sampling. `frame_begin` alone does
   not guarantee enough time to calculate the first pixel.
4. Zombie sprite colour/transparency and depth composition into `world_pixel`
   before `game_core` adds weapon/HUD overlays. Preserve the core's existing
   pixel look-ahead/sample deadline, including pixel (95,63), and OLED ownership.

### Enemy records and multiplayer (P4, P5, X1, X2)

Task 11 adds an opt-in host interface on `enemy_manager`. Set
`TWO_PLAYERS=1` and provide the two tile positions and active flags. The host
derives each flag from connection and health state. The flow field seeds both
eligible floor tiles before expanding either. Equal routes favor P1.

- Present each accepted weapon shot with its position and aim when that
  player's `shot_ready` or `shot_ready_p2` is high. Each player has one
  pending slot. Simultaneous shots are resolved P1 first, with each shot's
  origin and aim captured at acceptance. Damage uses the occupancy left by
  the preceding shot. `shot_hit_player` identifies the shooter on `shot_hit`.
- Route `player_hit` and `player_hit_p2` to separate health controllers. Each
  active player has an independent contact cooldown. Losing eligibility
  removes that player from targeting and disables their contact damage.
- The host's spawn selector must exclude both active player tiles. The enemy
  manager leaves an invalid request unacknowledged, so the host must reselect
  if a player moves onto the pending spawn tile.
- The host can snapshot the packed `render_x`, `render_y` and `active` buses
  by slot. The record lookup exposes HP and type if the packet needs them.
  The demo remains single-player. Per-player weapons, the spawn selector
  update and the UART game packet layout belong to full host integration.

Propose a fixed slot pool rather than shifting surviving zombies on death:

| Field | Provisional representation | Purpose |
|---|---|---|
| Slot ID | 3 bits with eight slots; derive width if capacity changes | Stable identity during one zombie's lifetime |
| Active | 1 bit per slot | Slot allocation / visibility |
| X, Y | 32 bits each, proposed coordinate scale above | Movement, aiming and drawing |
| HP | 8-bit unsigned; damage saturates at zero | Enemy health; initial HP remains a tunable gameplay parameter |
| Type | 2 bits; initially only type 0 used | Allows later behaviour/appearance variants |
| Behaviour | 2 bits: 0 idle, 1 chase, 2 attack, 3 reserved | Internal state; transmit only if the client needs it |
| Attack cooldown | 16-bit unsigned tick counter | Internal rate limiting; duration to be tuned during combat work |

Use `MAX_ENEMIES = 8` initially and match the wave controller's living cap.
Inactive status represents death/removal. A reused slot identifies a new zombie;
it must not inherit the previous occupant's HP or timers.

Gokul's existing packet framing is `A5, type, length, payload, checksum`; the
generic payload limit defaults to 16 bytes and is parameterized. Preserve that
transport initially. Do not assume the full enemy pool fits one packet.
Agree compact record encoding, packet types, byte ordering, snapshot/session
identifiers, fragment completeness and stale-update handling before integration.
In particular, a delayed update must not resurrect an old occupant of a reused
slot. Packet layouts are still open, not prescribed by this document.

For two players, propose player-indexed shot/hit events and active flags, plus
separate health and weapon state. Define simultaneous-hit policy and temporary
damage protection during combat work. Spawn selection must consider both active
players. Disconnected/inactive players must not remain enemy targets.

## File plan and review checklist

Task 1 adds this document and a README link only. Future implementation files
below are proposed, not created by this task:

| File | Future responsibility |
|---|---|
| `FDP2026.srcs/sources_1/new/enemy/enemy_manager.v` | Slot lifecycle, records, occupancy and existing spawn/death interface |
| `FDP2026.srcs/sources_1/new/enemy/flow_field.v` | Shared map navigation; consume tiles rather than camera angles |
| `FDP2026.srcs/sources_1/new/enemy/enemy_combat.v` | Shot targeting, damage and attack scheduling; final split may change |
| `FDP2026.srcs/sources_1/new/enemy/zombie_renderer.v` | Sprite projection and depth comparison once camera contract is agreed |
| `sim/enemy/` | Simulation-only testbenches, outside design sources |

No common Verilog header is introduced until its first consumer exists. Keep
configurable numeric choices in named parameters at implementation time, with
one consistent configuration supplied by the integration top.

- [ ] Kiat: confirm world units/position scale, signed deltas and shared state/tick (P1, X3).
- [ ] Kiat + Fawaz: resolve angle and camera-depth contracts before aim/projection work (P2, P3).
- [ ] Chuan Onn + Fawaz: confirm replacement handshake, event accounting and reset priority (E5-E8).
- [ ] Chuan Onn + Gokul + Fawaz: agree per-player combat and spawn avoidance (X1, X2).
- [ ] Gokul + Fawaz: agree enemy snapshots, record identity and packet layout (P4, P5).

These boxes intentionally remain unchecked. Task 1's provisional deliverable
is ready when this specification is reviewable; team agreement remains pending.
Task 2 should bring the required map/game branch into a separate implementation
branch and establish its demo baseline before adding enemy behaviour. Update
this document alongside later agreed changes; recheck adapters and dependent
simulations when widths, scales or timing change.
