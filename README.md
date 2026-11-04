# EE2026_Zombie_Survival_Basys_3

## Team integration

- [Provisional enemy subsystem interface](docs/enemy-interface.md): Fawaz's
  Task 1 specification, including existing connections, proposed conventions
  and open decisions for team review. It does not change the HDL.

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
   - Constraints: `Basys3_Master.xdc`.

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

## Fawaz: enemy movement and combat demo (Tasks 3–8)

`enemy_test_top` uses the map/game subsystem with `enemy_manager` replacing the
temporary zombie stub. It keeps eight stable slots, initializes position/HP/type/
state/cooldown, acknowledges each spawn once, and reports occupancy and deaths.
Zombies follow a shared breadth-first search field toward the fixed player
spawn on the minimap, with up to two tile steps per second. They wait when
another zombie occupies the next tile and stop short of the player. The first
slot checked rotates each sweep so lower slots do not always win a contest.

In your existing Vivado project:

1. Add `FDP2026.srcs/sources_1/new/enemy/flow_field.v`,
   `FDP2026.srcs/sources_1/new/enemy/enemy_combat.v`,
   `FDP2026.srcs/sources_1/new/enemy/enemy_manager.v` and
   `FDP2026.srcs/sources_1/new/demo/enemy_test_top.v` as design sources.
2. Set `enemy_test_top` as top, with `STAGE=3`. Keep `constraints/map_preview.xdc`
   enabled and the master XDC disabled. Add `constraints/enemy_aim.xdc` to
   assign SW1 and SW2 for `enemy_test_top`.
3. Build/program and start with btnC. Enable SW0 to see the minimap. Set
   SW2:SW1 to 00 for right, 01 for down, 10 for left, or 11 for up.
   Press btnC to fire along the selected direction. LD4 shows whether the most
   recent accepted shot hit. Each zombie takes three hits, and walls block shots.
   Adjacent zombies take one heart, then share a one-second damage cooldown.
   Use btnL to reload, btnR for debug removal, btnD for test damage, and btnU to reset.

Run the focused simulations from PowerShell with `./sim/enemy/run.ps1` (pass
`-VivadoBin` if Vivado is installed elsewhere). Tests cover allocation, held
requests, capacity, record reuse, reset, simultaneous events, and real wave
controller integration through two waves and restart. Testbenches belong in
Simulation Sources only.

For an independent full build, run Vivado in batch mode with
`-source sim/enemy/build_demo.tcl`. Reports and the bitstream go under
`build/enemy_verify/`. The script does not modify the existing project.

## Member 4: map and game subsystem

This branch includes a standalone map/game/UI demo for the Basys 3 and a
`game_core` wrapper for team integration. The demo uses a flat sky/floor world
view, a stationary player spawn tile and a temporary zombie stub. Raycasting,
player movement, real enemy AI/combat and multiplayer still need connecting.

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
| `ui/` | Pixel compositor, menus, HUD, weapon controller/sprite, overlays and display helpers |
| `demo/` | `map_preview_top` and temporary `zombie_stub` |

The course `Oled_Display.v`, `Mouse_Control.vhd` and `Ps2Interface.vhd` are
reused from the shared source folder. `constraints/map_preview.xdc` is the
standalone demo's pin/timing file.

### Run the standalone map/game demo

The general creation script above selects `My_Top_Module` and the master XDC
for team work. For this standalone demo:

1. Create/open the Vivado project and include all Verilog and VHDL design
   sources under `FDP2026.srcs/sources_1/new/`, including subfolders.
2. In an existing project, use Add Sources for any new file that has not been
   registered yet, especially `ui/pixel_compositor.v`.
3. Set the top module to `map_preview_top`, with the generic `STAGE=3`.
4. Add and enable `constraints/map_preview.xdc`. Disable
   `FDP2026.srcs/constrs_1/new/Basys3_Master.xdc` for this demo; do not enable
   both pin files together. Retain the generated-clock timing constraint.
5. Run synthesis, implementation and Generate Bitstream. Board programming is
   a separate action.

### Demo controls

| Control | Action |
|---|---|
| Mouse pointer + left-click | Select/confirm the enabled 1-player title option |
| btnC | Confirm 1-player start; fire during gameplay |
| Left-click during gameplay | Fire the pistol |
| Right-click or btnL during gameplay | Reload a partially used magazine |
| btnR during gameplay | Temporary test action: defeat the oldest stub zombie |
| btnD during gameplay | Temporary test action: lose one heart |
| btnU | Reset to the title and initialise the subsystem |
| SW0 off | World view with gameplay overlays |
| SW0 on | Add the whole 16x16 map as a 64x64 overlay at x=32..95 |
| Seven-segment display | Show the active map seed as four hexadecimal digits |

On either end screen, a new left-click or btnC returns to the title after the
input delay. The two-player option is disabled in the current demo. Shooting
provides a `shot_fired` event; actual targeting and enemy damage belong to the
combat integration. The minimap player markers currently show spawn locations.

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
| `frame_begin` | One 100 MHz-clock pulse per display frame; prepare the renderer's first pixel before it is sampled |
| `spawn_req`, `spawn_tile`, `spawn_ack` | Request and tile stay asserted/stable until the enemy module acknowledges acceptance |
| `occupied`, `enemy_defeated` | Enemy tile mask and one defeat pulse per killed enemy |
| `player_hit`, `shot_fired` | One-clock combat events; health is maintained by `game_core` |

Use the same published map for raycasting, player collision and enemy
navigation. Keep the OLED driver and tail bridge owned by `game_core` rather
than adding another OLED output driver during integration.

### Local verification and repository scope

Tests and detailed verification records are maintained in the separate local
`map_preview` project. `sim/map/`, `docs/map/` and the obsolete
`scripts/map/gen_weapon_overlay.py` are excluded from this branch's intended
source-only layout. Keep the working `ui/weapon_overlay.v` and sprite artwork;
the obsolete script does not regenerate the current reload-capable overlay.

The latest standalone regression passed all 16 simulation targets, including
five complete 6144-pixel OLED frames. Those checks cover the map, display,
controls, menus, spawning, wave progression, weapon/reload behaviour and
victory/restart. The latest RTL refactors still require fresh synthesis,
implementation, timing/resource checks and board verification; existing
bitstreams predate them.
