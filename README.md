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

### One player

Pick **1 PLAYER** and click (or BTN-C). No second board is needed and a new
random map is used each game.

### Two players

Connect JC1 (TX, K17) of each board to JC2 (RX, M18) of the other, and GND to
GND. LED15 and `LINKED` on the title show the link is up.

Each board plays its **own complete game** (own zombies, waves, hearts, gun
and controls) on the **same map**, like a survival race:

1. On either board select **2 PLAYERS** and start. Without the link the title
   shows `NO LINK TO P2` and will not start.
2. The other board, if it is on its title screen, joins automatically: it
   builds the same map from the starting board's seed and starts its own run.
   If both boards start at the same moment, one of them is picked to choose
   the map and the other joins it.
3. While both of you are playing you can see your partner: a blue-shirted
   figure in your 3D view (hidden behind walls like the zombies) and a yellow
   tile on the SW0 map. The seven-segment display shows your wave and your
   partner's wave, and LED14-12 show your partner's hearts. Zombies are not
   shared: each board's zombies only chase that board's player.
4. Each run ends on its own (game over or victory); the other board keeps
   playing. The end screen shows `PARTNER WAVE nn` (green while the partner
   is still playing).

The link only carries a status word every 20 ms (state, 2-player flag,
leader flag, game token, start priority, map seed, wave, hearts, position and
view angle). See
[docs/multiplayer-link.md](docs/multiplayer-link.md).

Menus, generating screen, hearts, ten waves,
weapon animation/ammo/reload, damage effects, victory/game-over screens and
return-to-title behavior are integrated into the game. Accepted shots trace from
the actual player pose at the camera angle. The first zombie before a wall takes
one damage, and three hits kill it. Adjacent zombies share a one-second player
damage cooldown. Enemies move at up to two tile steps per second, rotating slot
priority while following the live player's shared BFS field.

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

Run `./sim/enemy/run.ps1` for enemy lifecycle, combat, two-player host logic,
wave/reset and legacy sprite regression checks. Its cardinal wall helper lives
under `sim/enemy/` solely as a test fixture. The integrated board uses the
shared `Map_Renderer` and `Ray_Caster`.
