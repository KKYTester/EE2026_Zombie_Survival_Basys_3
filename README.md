# EE2026_Zombie_Survival_Basys_3

## Set up the Vivado project

The Vivado project is generated locally using `create_project.tcl`. The repository
contains the HDL sources and constraints; generated project and build files are
ignored by Git.

### Prerequisites

- Install Vivado with support for Artix-7 devices. The current local setup uses
  Vivado 2025.2.
- Clone or download this repository, keeping `create_project.tcl` and
  `FDP2026.srcs/` together in the repository root.

### Create the project in Vivado

1. Open Vivado with no project open.
2. Open the **Tcl Console** at the bottom of the window. If it is hidden, select
   **Window > Tcl Console**.
3. Run the following command, replacing the example path with the full path to
   your copy of `create_project.tcl`:

   ```tcl
   source {C:/path/to/EE2026_Zombie_Survival_Basys_3/create_project.tcl}
   ```

   On Windows, use forward slashes (`/`) and keep the braces so paths containing
   spaces work. The script resolves all project files relative to itself, so you
   do not need to change Vivado's working directory.

4. Wait for the script to finish. It creates and opens the `FDP2026` project at
   `build/FDP2026/FDP2026.xpr` with:
   - FPGA part: `xc7a35tcpg236-1` (Basys 3).
   - Top module: `My_Top_Module`.
   - Sources: all `.v`, `.sv`, `.vhd`, `.vhdl`, `.vh`, and `.svh` files under
     `FDP2026.srcs/sources_1/new/`, including subfolders.
   - Constraints: the Basys 3 master pins plus the multiplayer and aim pins.

### Reopen or regenerate the project

For later sessions, open `build/FDP2026/FDP2026.xpr` directly in Vivado; you do
not need to run the script again. The script sets up the project only; run
synthesis, implementation, and bitstream generation from Vivado when needed.

If you need to regenerate the project, close it in Vivado first, preserve any
needed build results, then delete only the generated `build/FDP2026/` folder and
run the script again. The script does not overwrite an existing project.

Edit and commit the HDL and constraint files under `FDP2026.srcs/`. Put new HDL
source files under `FDP2026.srcs/sources_1/new/` (or its subfolders). The script
discovers them each time it creates a project, so you do not need to edit the
script when adding or removing HDL files.

An already-open project does not automatically refresh when files appear on disk.
Use Vivado's **Add Sources** to add new files to your existing project, or
regenerate the project using the steps above. Keep simulation-only testbenches
outside this design-source folder.

Design sources under `FDP2026.srcs/sources_1/new/` are grouped as follows:

- `map_renderer/`: `Map_Renderer.v` and `Ray_Caster.v`.
- `player_state/`: `Player.v` and `Player_Controller.v`.
- The source root holds the top module, peripheral modules, and shared headers.
  `Game_Config.vh` and `Ray_Tables.vh` are used by both groups.

After pulling this reorganization, remove the four old source paths from an
existing Vivado project and add the files from these subfolders, or regenerate
the project using the steps above. The simulation runner discovers sources
recursively, and the hardware validation script uses the grouped paths.

See [DeveloperGuide.md](DeveloperGuide.md) for prototype details, controls,
rendering, and validation instructions.

## Game and two-board play

`My_Top_Module` is the whole game: Fawaz map generator, title/HUD/OLED
pipeline, raycaster, flow-field zombie AI, camera-ray combat and first-person
zombie sprites. Every board gets the **same bitstream**; there are no roles.

### Build and program

In Vivado's Tcl Console run `create_project.tcl` (or
`create_zombie_multiplayer.tcl`), then Synthesis, Implementation and Generate
Bitstream. Program the same bitstream onto every board.

### Controls (every board)

| Control | Action |
|---|---|
| Mouse move | Turn (menu cursor on the title) |
| BTN-U / BTN-D / BTN-L / BTN-R | Walk forward / back / strafe left / strafe right |
| Left-click or BTN-C | Fire; click/BTN-C also confirms menus |
| Right-click | Reload |
| BTN-D on the title | Toggle 1 PLAYER / 2 PLAYERS |
| SW0 | Toggle the full map overlay |
| SW13 / SW14, each flip | Test damage / defeat the lowest active zombie slot |
| SW15 up, then down | Reset to title |
| Seven-segment display | Map seed; in a 2-player game: own wave (left) and partner wave (right) |
| LED15 / LED14-12 | Link up / partner's hearts during a 2-player game |
| LED10 / LED9 | UART or packet error / status sequence gap, latched until reset |

### One player

Pick **1 PLAYER** and click (or BTN-C). No second board is needed and a new
random map is used each game.

### Two players

Connect JC1 (TX, K17) of each board to JC2 (RX, M18) of the other, and GND to
GND. LED15 and `LINKED` on the title show the link is up.

Both players are in **one shared game**: the same map, the same zombies.

1. On either board select **2 PLAYERS** and start. Without the link the title
   shows `NO LINK TO P2` and will not start.
2. The other board, if it is on its title screen, joins automatically: it
   builds the same map from the starting board's seed and spawns on the map's
   second spawn tile. If both boards start at the same moment, one of them is
   picked to run the game and the other joins it.
3. The starting board runs the waves and the zombies for both players. Each
   zombie chases the visible player with the shortest walkable route and
   keeps its current target on a tie. Shots from both boards hit zombies.
   The other board draws the same zombies and sends its position, view
   angle and shots.
4. You see your partner as a blue-shirted figure in your 3D view (hidden
   behind walls like the zombies) and as a yellow tile on the SW0 map.
   LED14-12 show your partner's hearts.
5. Each player has three hearts. A player who is down is frozen (cannot move
   or shoot) while the partner fights on. The run ends for both boards when
   both players are down (GAME OVER) or after the last wave (VICTORY).
6. If the link is lost, the starting board carries on alone and the other
   board ends its run.

The link carries a CRC-protected status word from each board every 20 ms,
plus a matching zombie snapshot from the leader during a shared run. Follower
shots retain their firing pose and are retried until acknowledged. Both
boards must use the same updated game bitstream. See
[docs/multiplayer-link.md](docs/multiplayer-link.md).

Menus, generating screen, hearts, ten waves,
weapon animation/ammo/reload, damage effects, victory/game-over screens and
return-to-title behavior are integrated into the game. Accepted shots trace from
the actual player pose at the camera angle. The first zombie before a wall takes
one damage, and three hits kill it. Adjacent zombies share a one-second player
damage cooldown. Enemies update 32 times per second and rotate slot priority.
Each zombie checks sight in all directions using tile centres, up to six
tiles along either axis. Walls block sight, including either side of an exact
corner crossing. If sight is lost, the zombie follows its last seen tile and
scans from there for about 0.75 seconds. Idle zombies wander one tile at a
time while scanning. They use the map seed to pick among the four cardinal
directions and try other neighbors if the first choice is blocked.
After roughly two to three seconds of wandering, a zombie follows a route
toward the farther of the map's two spawn tiles. It resumes wandering after
arrival or two seconds without crossing into a new tile. Sight and hearing
can interrupt the patrol. A zombie gives up on a last-seen tile if it cannot
reach it before its memory expires, about eight seconds after losing sight.

When a zombie sees neither player, it can hear an accepted shot up to six
walkable steps away. Sound goes around corners through open paths. Walls and
blocked diagonals stop it. The zombie heads to the original firing
tile, then scans there just as it does at a last-seen tile. A visible player
takes priority. Between sweeps, the latest shot from each player is kept.
If both are audible in the same sweep, the shorter path wins and equal paths
favor P1. A new audible shot can redirect an investigation.

The zombies share a BFS engine that searches all eight neighbors with equal
hop cost. Diagonals require
the destination and both side tiles to be floor, with no wrapping at map edges.
The 256-entry queue visits each tile once; a full rebuild takes at most 4,357
100 MHz clocks (about 44 microseconds), including two-player seeding.
Fractional movement travels at one tile per second on straight cardinal
segments and steers toward a point 0.25 tile ahead along the
planned center-to-center path (`enemy_manager.LOOKAHEAD`, in coordinate units).
Both direction components blend near turns; a blocked lookahead segment or a
turn sharper than 90 degrees falls back to the current waypoint. Diagonal
lookahead distances use 181/256 and 362/256 approximations to 1/sqrt(2) and
sqrt(2), so straight diagonal travel has approximately the same speed as
cardinal travel. Its next tile is reserved before steering begins,
and every proposed substep must remain on the current segment's floor tiles.
Steering arithmetic is pipelined. An eight-slot sweep can rebuild the field
twice per slot when a hearing check falls back to a remembered destination.
Those rebuilds take at most about 0.7 ms at 100 MHz.
A blended waypoint completes within one substep of its endpoint
plane, retaining lateral motion. The proportional steering can slow movement
at corners; Q8 substep rounding also slightly reduces diagonal speed. Sprites and minimap
dots use the fractional positions. A trip reserves both endpoints until arrival;
a diagonal also reserves both side tiles, covering its entire 2x2 swept square.
The lookahead segment uses the same reservation footprint. These conservative
reservations prevent swaps and crossing diagonals, and may make nearby zombies
wait. The reservation union is registered and updated atomically with each owner's
trip; arrival, death and reset release the owned reservations. Shots intersect circles at the actual fractional
positions, using `enemy_manager.HIT_RADIUS` (in coordinate fixed-point units),
which defaults to 0.25 tile. The first circle intersection takes damage; walls
block hits using a bounded grid DDA, including zero-component rays. The shared
solver checks one slot at a time with a 28-cycle integer square root, then visits
at most 31 tile boundaries. Movement and spawning stay locked until damage
commits, keeping the shot snapshot consistent. Cardinal test-mode shots use the
same circles.
The spawn selector excludes those reservations. Contact damage uses the
existing Manhattan distance (|dx| + |dy|) between actual player/enemy positions;
enemies stop when within one tile of the player.
Fractional contact checks include diagonal neighbors and reject side-wall
corners, so a zombie already in range can attack after a diagonal approach.

`My_Top_Module.MOVE_PERIOD` is the interval between substeps at 100 MHz.
The default 3,125,000 clocks gives 32 updates per second with
`enemy_manager.MOVE_SUBSTEPS=32`. One-step mode remains available for the
earlier tile-movement regression tests.

SW0 hides/shows the map over the first-person scene. The sprite and wall
renderers snapshot the same pose, prepare the back bank, and publish together.
Sprite depth and wall depth use perpendicular camera distance. Horizontal sprite
projection uses a pinhole approximation to the renderer's evenly spaced angle
columns, so placement near the edges may differ by a small number of pixels.

The generated map and UI use `{y,x}`, x right and y down, 1 wall / 0 floor.
The integration reverses rows for the existing north-increasing renderer/player
coordinates and converts the validated P1 spawn to the center of its tile in
Q*.12. Movement and rays share that converted map. Each new game resets the
view to angle 128 (northeast). Each scan snapshots map and pose; completed
column banks publish only during `game_core.frame_idle`. The renderer reads
the core's look-ahead X/Y directly, including pixel (95,63), without putting a
row-index division on the integrated pixel path.

### Current behaviour

- Seeded 16x16 recursive-division maps with enclosed boundaries and one or two
  doorway gaps per dividing wall. The validator checks boundaries, player
  spawns and floor connectivity before publishing the map in STAGE 3.
- Session flow: title -> generating -> playing -> game over or victory.
  There is no countdown screen or large wave/wave-clear banner. The small HUD
  wave/zombie counts and the between-wave pause remain.
- Three player hearts. Losing all hearts ends the game. Clearing all ten waves
  leads to victory after the final between-wave pause. Both end screens wait
  for an input delay and then a new click or btnC returns to the title.
- A six-round pistol with muzzle flash, recoil, manual reload and automatic
  reload after the last round's recoil. Reload requests during recoil are
  remembered. The five weapon states are READY, FIRING, LOWER, SWAP and RAISE;
  existing status ports are preserved as combinational decodes.
- One reusable `pixel_compositor` defines the gameplay drawing order:
  world -> weapon -> HUD -> ammo -> map -> zombie dots -> damage tint.
  Outside gameplay, a full-screen menu is selected instead. `game_core` uses
  the same compositor definition for normal pixels and pixel (95,63), which
  the unchanged `oled_tail_bridge` inserts after the course OLED driver.

### Source layout

Design folders are under `FDP2026.srcs/sources_1/new/`:

| Folder | Responsibility |
|---|---|
| `map/` | Map system, generator, register storage, validator and LFSR |
| `game/` | Game core, session flow, player health, waves and spawn selection |
| `enemy/` | Shared navigation, host enemy records, camera combat and sprite rendering |
| `ui/` | Pixel compositor, menus, HUD, weapon controller/sprite, overlays and display helpers |

The course `Oled_Display.v` and `Ps2Interface.vhd` and the relative-motion
`Mouse_Control_Delta.vhd` are reused from the shared source folder.
`Mouse_Pointer` accumulates signed X/Y packet deltas into a 96x64 cursor;
PS/2 positive Y moves the pointer upward.

### Integration contract

Instantiate `game_core` from the final team top and connect the renderer and
real player/enemy modules to its ports:

| Interface | Contract |
|---|---|
| `published_map[255:0]` | Tile address `{y[3:0], x[3:0]}`; 1 = wall, 0 = floor; x increases right and y increases down |
| `map_ready`, `map_busy` | Consumers use the published map only while ready; the map stays unchanged during gameplay |
| `p1_addr`, `p2_addr` | Validated spawn tiles in the same address format |
| `play_start`, `game_state` | New-game initialisation pulse; state 3 means playing |
| `player_tile` | Connect the player's current tile so spawn-distance checks follow movement |
| `pixel_x`, `pixel_y`, `world_pixel` | The core requests a world pixel ahead of transmission; the renderer supplies RGB565 colour before its sample deadline, including the final pixel |
| `frame_begin` | One 100 MHz-clock pulse per display frame |
| `frame_idle` | Safe window for the integrated renderer to publish a completed column bank before the next frame |
| `spawn_req`, `spawn_tile`, `spawn_ack` | Request and tile stay asserted/stable until the enemy module acknowledges acceptance |
| `occupied`, `enemy_defeated` | Enemy tile mask and one defeat pulse per killed enemy |
| `player_hit`, `shot_fired` | One-clock combat events; health is maintained by `game_core` |

Use the same published map for raycasting, player collision and enemy
navigation. Keep the OLED driver and tail bridge owned by `game_core` rather
than adding another OLED output driver during integration.

### Integration validation

Run `./tests/run_mouse_delta_checks.ps1` and `./tests/run_renderer_checks.ps1`
for packet, pointer, ray, player, runtime-map, integrated-flow and complete OLED
stream checks. Add `-Hardware` to the renderer runner for synthesis, placement,
routing, utilization, timing and CDC reports under `build/renderer_hardware/`.
No board verification is implied by these simulations. See DeveloperGuide.md
for the current integration results and remaining hardware checks.

Run `./tests/run_priority_one_checks.ps1` for UART and packet regressions,
two-player spawn distances, shot queue ordering, and a two-board simulation
that drops shot and acknowledgement packets. The hardware check uses both
game constraint files and reports hierarchical usage and the worst paths.

Run `./sim/enemy/run.ps1` for enemy lifecycle, combat, two-player host logic,
wave/reset and legacy sprite regression checks, plus circle tangencies and
misses, lookahead turns, diagonal BFS against an independent shortest-hop
reference, blocked corners, diagonal speed, swept-square reservations, swaps,
crossing-path waits, cached ownership, high-precision coordinates and diagonal
contact/wall blocking. Select a subset with, for example,
`./sim/enemy/run.ps1 -Tests tb_flow_diagonal,tb_enemy_diagonal`. Its cardinal
wall helper lives under `sim/enemy/` solely as a test fixture. The integrated board uses the
shared `Map_Renderer` and `Ray_Caster`.


### Enemy-change validation (6 November 2026)

All 12 enemy XSim testbenches pass, including circular shooting, lookahead,
diagonal shortest-hop routes, reservation ownership, swaps/crossings, diagonal
contact and Q24 arithmetic. The raycaster (1,800 reference rays), player
controller (16,384 movement references), runtime-map and integrated zombie/wall
renderer checks also pass.

Vivado 2025.2 synthesis, placement and routing of `My_Top_Module` for
`xc7a35tcpg236-1` complete with setup slack **+0.062 ns** and hold slack
**+0.040 ns**, zero failing paths and no unconstrained internal endpoints.
Routed utilization is **15,770 LUTs (75.82%)**, 10,296 registers (24.75%),
20 DSPs and two RAMB18s. Reports and the routed checkpoint are generated under
`build/renderer_hardware/` and are not committed.

DRC has no errors; 34 DSP pipelining advisories remain. CDC reports all
sys-clock/OLED crossings as safely timed, with 12 unknown endpoints on existing
asynchronous external inputs requiring board/peripheral review. No bitstream
was generated and no board test was performed; mouse, OLED and gameplay checks
on the physical Basys 3 remain outstanding. The routed timing margin is small,
so repeat implementation checks after further RTL or constraint changes.

### Priority-one validation (7 November 2026)

Vivado 2025.2 routed `My_Top_Module` at 100 MHz with both game constraint
files. The baseline is `timing-fix` at `7444b0f`; the comparison includes
the timing, fair spawning and reliable shot changes together.

| Routed metric | Baseline | With fixes |
|---|---:|---:|
| Worst setup slack | -2.430 ns | +0.123 ns |
| Worst hold slack | +0.003 ns | +0.055 ns |
| Failing setup endpoints | 107 | 0 |
| Slice LUTs | 17,787 (85.51%) | 15,403 (74.05%) |
| Slice registers | 11,994 (28.83%) | 8,220 (19.76%) |
| Block RAM tiles | 1 (2%) | 2.5 (5%) |
| DSPs | 20 | 21 |

The BFS queues for enemy navigation, map validation and spawn search use
block RAM. Timing fixes also register session-timer control, weapon requests
and enemy steering and contact data. No internal timing paths were removed
from analysis; the routed timing report has no unconstrained internal endpoints.

The 12 enemy simulations, packet and spawn checks, two-board loss and rejoin
test, and affected gameplay and OLED checks passed. Baseline and final reports
are in `build/priority_one_baseline/reports/` and `build/priority_one_r4/reports/`.
Physical board testing remains to be done.
