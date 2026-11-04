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

## Fixed-step raycasting prototype

The OLED now displays a first-person view of the fixed, enclosed 16 by 16 room:
grey walls, a dark ceiling, and a dark floor. The player starts at `(8.5, 8.5)`,
looking north. There are no movement, mouse, firing, or restart controls yet;
reconfiguration restores the startup viewpoint. This is a renderer prototype,
not the playable game. The existing 6.25 MHz `Oled_Display` and JB wiring remain.
The top supplies a startup reset lasting 255 board clocks; unused `JB[2]` is low.

`Game_Config.vh` defines the map and spawn centrally. Map bit `x + 16*y` is 1 for
a wall, 0 for open space. The lowest 16 bits are row `y=0`, and each row's lowest
bit is `x=0`. World x increases east and y increases north. World coordinates
have 12 fractional bits (one cell = 4096); the ray engine uses signed 18-bit
coordinates, with a range of -32 to just under +32 cells. Valid map coordinates
are 0 to just under 16. Angles use 1024 units per turn, clockwise from north:
0 north, 256 east, 512 south, 768 west. `Player` retains 32-bit increment/state
ports; the renderer consumes the low 18 position bits and low 10 angle bits.
Player collision and input handling are still pending; increments are zero.

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
is needed for this static prototype. The retained `pixel_tick` defaults to
25 MHz (every 4 board cycles), but ray work and OLED colour lookup do not use it.
`Player` updates only on `game_tick`; its inputs are increments per tick.

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

Add the new `Ray_Caster.v`, `Game_Config.vh`, and `Ray_Tables.vh` to an already-open
Vivado project, or regenerate the project. Set the source include directory to
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
- `clock_enable_tb`: existing player/enable/startup-reset regression, updated
  for the new spawn and existing 25 MHz parameter default. It simulates 83.34 ms.
- `oled_renderer_tb`: checks actual top-level OLED SPI pixel loads and colours,
  including pixel zero. It also explicitly records a supplied-driver limitation:
  `Oled_Display.v` exits `SendPixel` when `pixel_index` reaches 6143, so it sends
  indices 0 through 6142 and skips the bottom-right pixel. All 6,144 renderer
  pixels are tested separately. The driver is labelled `DO NOT MODIFY` and has
  been left unchanged; the final physical pixel is not guaranteed by this prototype.

`-Hardware` writes utilization, setup/hold timing, DRC, and CDC reports plus a
routed checkpoint to `build/renderer_hardware/`. Inspect these reports before
generating a bitstream. Physical OLED appearance and board operation still need
hardware testing. Regenerate the constant angle tables, if deliberately changing
their definition, with `python tests/generate_ray_tables.py`.

### Validation recorded for this prototype

Vivado 2025.2 compiled and elaborated the design; all four simulations above
reported `PASS`. Synthesis and full placement/routing completed for
`xc7a35tcpg236-1`. The implemented top uses 542 LUTs (2.61%), 287 flip-flops
(0.69%), one RAMB18, and no DSPs. This includes the existing OLED interface;
constant player inputs and the unused depth output allow synthesis optimization.
Routed worst setup slack is +1.807 ns and worst hold slack is +0.098 ns, with
zero failing endpoints. There are no unconstrained internal endpoints, the DRC
report has zero violations, and CDC classifies the related-clock crossings as
safely timed. Synthesis warnings concern the existing OLED zero-width replication,
the deliberately unused pixel-enable counter, and the constant unused JB pin.

The constraints still lack external output delays for the seven active OLED
signals. Thus passing internal timing is not external-interface timing signoff.
No board test or bitstream generation was performed; the supplied OLED sender's
skipped final pixel remains as documented above. Vivado's Tcl file discovery was
unusable inside the Codex sandbox, so synthesis/implementation ran outside it,
with reports and checkpoints confined to `build/renderer_hardware/`.
