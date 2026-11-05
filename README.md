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
## First-person movement prototype

The OLED now displays a first-person view of the fixed, enclosed 16 by 16 room:
grey walls, a dark ceiling, and a dark floor. The player starts at `(8.5, 8.5)`,
looking northeast (angle 128). Buttons move the player and horizontal mouse
movement controls orientation. The view stays still when there is no input.
There are no zombies, firing, or restart controls yet; reconfiguration restores
the startup viewpoint. This is a movement/rendering prototype, not the complete
game. The existing 6.25 MHz `Oled_Display` and JB wiring remain.
The top supplies a startup reset lasting 255 board clocks; unused `JB[2]` is low.

The north (top) edge has a solid five-by-five wall block at `x=6..10`,
`y=10..14`, attached to the outer wall. Viewed from above, with north at the top,
the first six rows are:

```text
################
#     #####    #
#     #####    #
#     #####    #
#     #####    #
#     #####    #
```

The remaining interior rows retain only the side walls, with a solid bottom
boundary. The player spawn at `(8.5, 8.5)` remains in open space.

`Game_Config.vh` defines the map and spawn centrally. Map bit `x + 16*y` is 1 for
a wall, 0 for open space. The lowest 16 bits are row `y=0`, and each row's lowest
bit is `x=0`. World x increases east and y increases north. World coordinates
have 12 fractional bits (one cell = 4096); the ray engine uses signed 18-bit
coordinates, with a range of -32 to just under +32 cells. Valid map coordinates
are 0 to just under 16. Angles use 1024 units per turn, clockwise from north:
0 north, 256 east, 512 south, 768 west. `Player` retains 32-bit increment/state
ports; the renderer consumes the low 18 position bits and low 10 angle bits.
`Player_Controller` supplies collision-checked position increments and angles;
`Player` stores the committed state. Angles explicitly wrap modulo 1024.
The renderer snapshots all three state values once per scan.

### Controls and mouse wiring

| Input | Action |
| --- | --- |
| BtnU | Move forward relative to the view |
| BtnD | Move backward relative to the view |
| BtnL / BtnR | Strafe left / right relative to the view |
| Mouse horizontal movement | Move right to turn right, left to turn left; continuous wraparound |
| Mouse left / middle / right button | Light LED 15 / 14 / 13 respectively |

Buttons are active high, synchronized through two registers, and debounced for
10 ms on both press and release. Holding a button repeats movement at 24 Hz.
Opposite buttons cancel on their respective axis. Diagonal movement uses a
3/4 scale, approximately 6% faster than single-axis movement. Single-axis speed
is approximately three cells per second (1/8 cell per tick); direction vectors
reuse the ray engine's rounded sine table. `Game_Config.vh` holds movement step,
body radius, and debounce constants. Keep the maximum step below one cell.

The player has a square collision body with a 1/8-cell half-width. Each update
checks its four corners against the central map, treating out-of-map positions
as solid. X movement is checked first, then y movement at the accepted x,
allowing sliding along walls. Each movement update occupies six 100 MHz cycles:
latch direction/buttons, compute movement vector, add position, check x, check y,
commit position and angle together. The renderer
snapshots the previous complete state while this update runs; it never sees a
partially updated viewpoint. The shared `game_tick` comes from `Map_Renderer`.

`My_Top_Module` instantiates the VHDL entity `Mouse_Control_Delta` from
`Mouse_Control_Delta.vhd`, with its unchanged `Ps2Interface.vhd` dependency, on
the 100 MHz board clock. The original `MouseCtl` in `Mouse_Control.vhd` remains
in the repository but is no longer instantiated. There is no `Top_Student.v` in
this project. Mouse outputs and game logic share one clock; the supplied PS/2
interface filters and samples the external lines. The XDC excepts asynchronous
pad-input timing only.

`x_delta` is a signed 9-bit horizontal count from -256 to +255 (right positive,
left negative). Sample it
once on the 100 MHz clock when its one-cycle `new_event` pulse is high, including
zero-delta/button-only packets. The value holds between events and clears on
reset. X overflow saturates that packet's delta to -256 or +255 according to
its sign. There are no accumulated positions or position-setting/limit inputs;
Y and wheel bytes are consumed but ignored. Mouse button outputs and the PS/2
ports remain. Mouse clicks are indicators only; combat is not added.

The top connects `x_delta` through a `signed [8:0]` wire to the controller's
`mouse_x_delta` input. On each `mouse_event`, `Player_Controller` sign-extends
the delta and adds it to its pending angle modulo 1024. One x count remains
0.3515625 degrees. Turning wraps continuously in either direction, including
left from startup, with no absolute-position clamp. Every packet is accumulated
between game ticks and during movement updates; a held delta is not replayed
without a new event. Each game tick snapshots the pending angle and commits it
with position through the existing six-cycle pipeline. A packet arriving on the
same clock as the tick, or during that pipeline, affects the following update.
Reset restores the spawn angle and clears pending movement.

Run `./tests/run_mouse_delta_checks.ps1` for the isolated byte-level controller
simulation (optional `-VivadoBin` as below). It tests all 512 signed encodings in
both three- and four-byte packet modes, overflow, ignored Y/wheel movement,
button outputs, event timing, repeated movement, and partial-packet error/reset.
The test substitutes the PS/2 byte transport; it does not simulate physical PS/2
signalling. Its stand-in belongs only in the simulation fileset, separately from
the real `Ps2Interface.vhd`.

Connect a wired mouse to the Basys 3 upper-right USB host port. The constraints
enable C17 for `ps2_clk`, B17 for `ps2_data`, pull-ups, all LED pins, and the four
directional button pins, matching the
[Digilent master constraints](https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc).
The top-level ports are `clk`, `btnU`, `btnL`, `btnR`, `btnD`, `ps2_clk`,
`ps2_data`, `led[15:0]`, and `JB[7:0]`.

`Ray_Caster.v` implements one ray as a bounded state machine on the 100 MHz
board clock. It snapshots its inputs on `start`, obtains the direction from a
quarter-wave sine lookup table, then advances by approximately 1/32 cell per
cycle using additions. Each direction component is rounded to 1/4096 cell.
It checks the starting cell and every subsequent sample, stopping at the first
wall, an out-of-map coordinate, or 768 steps (24 cells). `done` pulses for one
cycle; `hit` distinguishes walls from an unsuccessful traversal. A ROM supplies
`min(64, floor(2048/steps))`, including height 64 for zero distance. All division
in this ROM's initialization is constant elaboration work, not a runtime divider.
No wall returns height 0 and distance sentinel 1023. A wall at zero distance
returns distance 0 and height 64.

`Map_Renderer.v` snapshots the player once per scan and casts 96 rays spanning
angle offsets -85 to +85 (~59.77 degrees). This deliberately keeps the proposed
`64/distance` projection, equal angular spacing, and fisheye distortion. Walls
are vertically centred in the 64-pixel display. Fixed stepping can miss a wall
cell grazed near a corner; grid DDA is a future replacement if needed.

Rendering reuses one ray engine. A worst-case full scan takes less than 75,000
board cycles (0.75 ms at 100 MHz), including setup and column storage. It starts
immediately after reset and subsequently on the approximately 24 Hz game enable
when idle. Display acknowledgement can postpone the next scan; no request queue
is needed for this prototype. The retained `pixel_tick` defaults to
25 MHz (every 4 board cycles), but ray work and OLED colour lookup do not use it.
`Player_Controller` begins an update on `game_tick`; `Player` commits its
collision-checked increments five board clocks later.

Two banks each store 96 heights (7 bits each) and 96 raw ray distances (10 bits
each), totalling 3,264 bits before synthesis optimization. The height lookup is
1,024 by 7 bits; direction and column-angle tables are small constants. No full
RGB framebuffer is needed. Unused depth storage may be removed by synthesis
until a sprite renderer consumes `column_depth` (units of 1/32 cell; no fisheye
correction). Pixel coordinates use the OLED's row-major `pixel_index`.

The renderer writes only the back bank and freezes it after publishing a toggle.
Two-register synchronizers carry publication and acknowledgement between board
and OLED domains. At a rising OLED clock edge with `frame_begin` high, the display
switches to the completed bank, then acknowledges it. Only after acknowledgement
may the renderer reuse the old bank. This keeps column data stable across the
display frame; until the first complete scan is published, output is black.
Pixel colour is combinational and settles before the OLED's falling-edge SPI
load. The XDC now constrains the existing divided clock as `oled_clk` (160 ns
period, first rising edge 70 ns after the first board edge). Both clock domains
sample the startup reset; the OLED driver itself is unchanged.

### Run the checks

Add `Button_Debounce.v`, `Player_Controller.v`, `Mouse_Control_Delta.vhd`, and
`Ps2Interface.vhd` alongside the existing renderer files to an already-open
Vivado project, or regenerate the project. Use mixed-language simulation.
Set the source include directory to
`FDP2026.srcs/sources_1/new/` if adding files manually. `create_project.tcl` now
sets it automatically. Keep testbenches in the simulation fileset only.

From PowerShell in the repository root:

```powershell
./tests/run_renderer_checks.ps1
# For a different Vivado installation:
./tests/run_renderer_checks.ps1 -VivadoBin 'C:/path/to/Vivado/bin'
# Also run synthesis, placement, routing, and reports (no bitstream):
./tests/run_renderer_checks.ps1 -Hardware
```

The runner generates numerical references with Python's standard library, then
uses Vivado's `xvlog`, `xelab`, and `xsim`. It requires both process success and
an explicit `PASS` from each simulation. Generated outputs stay under `build/`.

- `ray_caster_tb`: 1,308 reference rays, including every angle, random walkable
  positions, cardinal rays with zero direction components, wall/edge starts,
  negative/out-of-map positions, zero distance, an interior wall occluding the
  boundary wall, traversal cap, input snapshot, and mid-ray reset.
- `map_renderer_tb`: all 96 heights/depths and all 6,144 pixels against numerical
  references for two viewpoints, player changes during a scan, no premature bank
  publication, stable front bank during rendering, invalid pixel indices, and
  reset/restart. It exports the first simulated image to
  `build/renderer_checks/prototype.ppm`.
- `clock_enable_tb`: player/enable/startup-reset regression and existing 25 MHz
  parameter default. Checks the player stays at spawn without input across two
  real 24 Hz updates. It simulates 83.34 ms.
- `player_controller_tb`: 16,384 numerical movement cases (all 1024 angles and
  16 button combinations), button bounce, opposing inputs, diagonal scaling,
  all 512 signed mouse deltas, continuous turns in both directions, zero/held
  deltas, event retention on every update stage, wrap, atomic updates,
  outer/interior walls, wall sliding, bounds with an unenclosed map, and reset
  during each update stage.
- `mouse_top_tb`: actual mixed-language top elaboration, mouse click LEDs,
  signed delta accumulation, orientation wiring, and controlled renderer snapshot.
  Stimuli are injected at the synchronous mouse output boundary; PS/2 packet
  exchange is not simulated.
- `oled_renderer_tb`: checks actual top-level OLED SPI pixel loads and colours,
  including pixel zero, with no input for the reference image.
  It also explicitly records a supplied-driver limitation:
  `Oled_Display.v` exits `SendPixel` when `pixel_index` reaches 6143, so it sends
  indices 0 through 6142 and skips the bottom-right pixel. All 6,144 renderer
  pixels are tested separately. The driver is labelled `DO NOT MODIFY` and has
  been left unchanged; the final physical pixel is not guaranteed by this prototype.

`-Hardware` writes utilization, setup/hold timing, DRC, and CDC reports plus a
routed checkpoint to `build/renderer_hardware/`. Inspect these reports before
generating a bitstream. Physical OLED appearance and board operation still need
hardware testing. Regenerate the constant angle tables, if deliberately changing
their definition, with `python tests/generate_ray_tables.py`.

After a successful hardware run, generate the bitstream from its routed
checkpoint (the script refuses failing internal setup/hold timing):

```powershell
& 'C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat' -mode batch -source tests/write_bitstream.tcl
```

In Vivado Hardware Manager, open the connected Basys 3 target and program
`build/renderer_hardware/My_Top_Module.bit`. Check each mouse-button LED,
continuous horizontal turning through several full turns in both directions,
view-relative movement, and collisions against both the
outside walls and the north block. Test simultaneous mouse turning/movement and
long button holds. Reconfigure to restore the spawn; BtnC is not connected.

### Validation

After delta integration, Vivado 2025.2 compiled and elaborated the mixed
Verilog/VHDL design. `player_controller_tb`, `mouse_top_tb`, and the isolated
`mouse_delta_tb` reported `PASS`, including 16,384 movement reference cases,
all signed deltas, multi-turn wraparound, and packet retention during updates.
The other four renderer regressions passed before this integration and were
not rerun for this change.
Synthesis and full placement/routing completed for `xc7a35tcpg236-1`. The final
design uses 1,304 LUTs (6.27%), 861 flip-flops (2.07%), one RAMB18, and no DSPs.
Routed setup slack is +0.182 ns and hold slack is +0.065 ns, with no failing
endpoints, no unconstrained internal endpoints, and no DRC violations.
No bitstream was generated or board programmed for the delta integration.
Any existing `build/renderer_hardware/My_Top_Module.bit` may contain the earlier
absolute-position design; regenerate it from the updated routed checkpoint
using the command above before programming and checking continuous turning.
Synthesis warnings include unused high state-port bits, the unused pixel-enable
counter, constant output pins, and the existing OLED zero-width replication.

The CDC report classifies the OLED crossings as safely timed and recognizes the
four button synchronizers. It also flags 12 input paths as unknown/critical in
the supplied PS/2 driver's filtering logic: that driver uses raw pad inputs to
control debounce counters before its final sampling registers. The supplied
drivers are labelled `DO NOT MODIFY` and remain unchanged. These warnings are
unresolved; input false paths do not certify those crossings as safe.

There are 12 external output-delay warnings (OLED, PS/2, and mouse-button LEDs).
Passing internal timing is not external-interface timing signoff. Physical
mouse/button behavior and OLED appearance still need board verification; PS/2
packet exchange was not simulated. The supplied OLED sender's skipped final
pixel remains as documented above. Vivado's Tcl file discovery was unusable
inside the Codex sandbox, so synthesis/implementation ran outside it, with
reports and checkpoints confined to `build/renderer_hardware/`.
