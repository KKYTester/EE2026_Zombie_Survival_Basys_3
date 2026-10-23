# Map generation, validation, map overlay and HUD (Member 4)

Procedural 16x16 map generator with BFS validation, an OLED map overlay and HUD, and a seven-segment seed display. It is not yet instantiated in `My_Top_Module`; that happens at team integration. `map_preview_top` is a standalone demo of this subsystem.

## Where the files are

| Folder | Contents |
|---|---|
| `FDP2026.srcs/sources_1/new/map/` | `map_system` (the module to instantiate), `map_generator`, `map_storage`, `map_validator`, `lfsr16` |
| `FDP2026.srcs/sources_1/new/ui/` | `map_display_mux`, `hud_overlay`, `font3x5`, `seven_seg_hex`, `button_debounce`, `oled_tail_bridge` |
| `FDP2026.srcs/sources_1/new/demo/` | `map_preview_top` (standalone demo top) |
| `sim/map/` | Self-checking testbenches |
| `constraints/map_preview.xdc` | Pins for the standalone demo only; deliberately outside `constrs_1` |

## Interface for teammates

- `published_map[255:0]`: tile at index `{y[3:0], x[3:0]}`; 1 = wall, 0 = floor. x increases to the right, y increases downward; the outer edge is always wall.
- Valid only while `map_ready` = 1. It changes only when a new map is requested, never during gameplay.
- `p1_addr`, `p2_addr`: spawn tiles in the same `{y,x}` format. `active_seed[15:0]`: seed of the current map (send this between boards so both regenerate the same map).
- The first-person image enters the display chain through `fp_pixel_data`; HUD and map overlay are drawn on top. See "Display integration" for the bottom-right pixel.


## 1. Module hierarchy and ports

`map_preview_top` synchronises controls, debounces regeneration, makes the 6.25 MHz OLED clock, and instantiates `map_system`. A `seven_seg_hex` driver displays the current active seed on the board's four digits. That subsystem sequences `map_generator`, its `lfsr16`, register-based `map_storage`, and `map_validator`, publishing a coherent map only after the selected stage's checks succeed. The top captures map/status/mode and synchronized HUD switches at frame boundaries. Pixels pass through `hud_overlay` before `map_display_mux` overlays the minimap. The repository's course-supplied `Oled_Display.v` serialises these pixels unmodified. An `oled_tail_bridge` preserves its commands and inserts the final pixel omitted by this version of the driver. The generator, validator and core run at 100 MHz; the display frame registers, driver and bridge use the related, constrained 6.25 MHz clock.

All widths below are bits. Signals are synchronous to `clk` unless stated otherwise. Reset `rst` is synchronous, active high.

| Module | Inputs | Outputs / parameters |
|---|---|---|
| `map_preview_top` | `clk`, `sw0`, `sw_wave[4:1]`, `sw_health[15:9]`, `btnC`, `btnU` | `led[15:0]`, `JB[7:0]`, `seg[6:0]`, `dp`, `an[3:0]`; `STAGE=3`, `DEBOUNCE_CYCLES=1000000` |
| `seven_seg_hex` | `clk` (100 MHz), `rst`, `value[15:0]` | Active-low `seg[6:0]` (bit 0=CA, bit 6=CG), `dp`, `an[3:0]` |
| `map_system` | `clk`, `rst`, `regenerate`, `seed_in[15:0]` | `published_map[255:0]`, `p1_addr[7:0]`, `p2_addr[7:0]`, `map_ready`, `busy`, `error_code[2:0]`, `active_seed[15:0]`, `retry_count[2:0]`; `STAGE`, `INITIAL_SEED=16'h1ACE`, `GEN_LIMIT=4096`, `VALIDATE_LIMIT=4096` |
| `map_generator` | `clk`, `rst`, `start`, `seed[15:0]` | `write_en`, `write_addr[7:0]`, `write_wall`, `busy`, `done`; `FIXED_MAP=0` |
| `map_storage` | `clk`, `rst`, `write_en`, `write_addr[7:0]`, `write_wall` | `map_bits[255:0]` |
| `lfsr16` | `clk`, `rst`, `load`, `advance`, `seed[15:0]` | `value[15:0]` |
| `map_validator` | `clk`, `rst`, `start`, `map_bits[255:0]` | `busy`, `done`, `passed`, `error_code[2:0]`, `p1_addr[7:0]`, `p2_addr[7:0]`, `floor_count[8:0]`, `reachable_count[8:0]`; `CHECK_CONNECTIVITY=1`, `MAX_CYCLES=4096` |
| `button_debounce` | `clk`, `rst`, `button` | `pressed` (one clock); `STABLE_CYCLES=1000000` |
| `map_display_mux` | `px[6:0]`, `py[5:0]`, `minimap_mode`, `fp_pixel_data[15:0]`, `map_bits[255:0]`, `p1_addr[7:0]`, `p2_addr[7:0]`, `seed[15:0]`, `map_ready`, `busy`, `bfs_enabled`, `error_code[2:0]` | `pixel_data[15:0]`; purely combinational |
| `hud_overlay` | `px[6:0]`, `py[5:0]`, `minimap_mode`, `health[6:0]`, `wave[6:0]`, `pixel_in[15:0]` | `pixel_out[15:0]`; combinational, inputs clamped to 99 |
| `font3x5` | `character[7:0]` (ASCII), `gx[1:0]`, `gy[2:0]` | `pixel`; combinational 3x5 glyph ROM, blank for unsupported characters |
| `oled_tail_bridge` | `clk` (6.25 MHz, falling edge), `rst`, `raw_cs`, `raw_sdin`, `raw_dcn`, `last_pixel_data[15:0]` | `cs`, `sdin`, `d_cn`, `sclk`; 64-entry serial-bit/marker queue |
| `Oled_Display` (unchanged) | `clk` (6.25 MHz), `reset`, `pixel_data[15:0]` | `frame_begin`, `sending_pixels`, `sample_pixel`, `pixel_index[12:0]`, `cs`, `sdin`, `sclk`, `d_cn`, `resn`, `vccen`, `pmoden`; `ClkFreq=6250000` |

### Stage behaviour (rule set C)

| STAGE | Generation | Validation before publication |
|---|---|---|
| 1 | Original fixed map | Boundary/floor/spawn scan; BFS bypassed |
| 2 | Seeded rule-C recursive division | Boundary/floor/spawn scan; BFS bypassed |
| 3 | Same rule-C generator | Boundary/spawn scan plus unchanged four-neighbour BFS |

All stages boot with seed `1ACE`. Stage 3 is the intended build; stages 1 and 2 remain selectable through the `STAGE` parameter for debugging.

### Rule C and connectivity

- Map storage remains `reg [15:0] map_row [0:15]` in registers. Address is `{y[3:0],x[3:0]}`; 1 means wall, 0 means floor. Boundaries remain walls.
- The explicit eight-entry depth-first stack uses three-bit depths and stops at depth 4. A binary depth-first traversal needs at most depth+1 = **5 occupied entries**, leaving three spare entries.
- Split the longer side; ties use LFSR bit 0. At depth >=2, bits [2:1] equal to 00 stop early (nominal 25% decision); depth 4 always stops.
- Even wall coordinates satisfy `lower+2 <= wall` and `wall+2 <= upper`.
- Choose the first odd door as before. Bit 3 sampled at S_DOOR_INIT requests a second door (nominal 50% decision). A bounded scan chooses a different odd coordinate inside the same span; omit it if no alternative exists.
- Every split joins its child rooms through at least one door. Child walls have even coordinates and cannot seal an ancestor's odd doorway. Additional doors and early stopping preserve connectivity. BFS still validates the finished map before publication.
- LFSR B400, its advance points (S_ORIENT and S_DOOR_INIT), min/max x+y spawn rules, retry logic, error codes and map interface are unchanged. Seed decisions are deterministic; exact layout probabilities are not claimed to be uniform.
- The generator draws at most one tile per clock. With at most 31 visited regions and 15 splits, a conservative generation bound is **1344 clocks**: 256 initial writes + 31*(POP+ORIENT) + 15*(17 wall scan + 1 door init + 17 first-door scan + 17 second-door scan + 1 draw init + 14 draw + 1 push) + start/finish allowance.
- Generation and validation watchdogs are each **4096 clocks**. A conservative terminal bound for initial attempt plus four retries is **41000 clocks = 5*(4096+4096+8)**, allowing eight control/handshake clocks per attempt. This is 410 us at 100 MHz, excluding debounce and OLED startup/refresh.
- `published_map` updates only after a pass. Busy presses are ignored; holding btnC produces one request. The validator and error handling are unchanged.

### LEDs and errors

LD0 = map_ready; LD3:LD1 = error (0 OK, 1 OPEN_BOUNDARY, 2 DISCONNECTED, 3 BAD_SPAWN, 4 TIMEOUT); LD15 = busy. Remaining LEDs are zero. There is no on-screen status strip.

### Seed display and controls

The board's four seven-segment digits show the current `active_seed`, including leading zeros, independently of SW0. After boot/reset the digits read `1ACE` left to right. btnC regenerates and the digits follow the active seed, including any automatic retry seed. btnU resets to the boot seed. LD0/error/busy LEDs and the OLED modes are unchanged.

`seven_seg_hex` uses an 18-bit free-running counter on the existing 100 MHz clock. Bits [17:16] select an[0], an[1], an[2], an[3] in that order. an[0] shows value[3:0]; an[3] shows value[15:12]. Glyphs are 0-9, A, b, C, d, E, F; all segments and anodes are active-low. DP is held high (off); synchronous reset clears the counter and blanks the digits.

**ASSUMPTION:** the explicitly requested counter bits take precedence over the approximate 1.3 ms description: each digit lasts 65536 clocks = 0.65536 ms at 100 MHz; one full scan is 2.62144 ms (381.47 Hz). No new clock, IP, divider or modulo operator is introduced for this display.

## 2. Source notes

The authored RTL uses Verilog-2001 constructs. The course `Oled_Display.v` (already in this repository, unchanged) contains `$clog2` expressions, which Vivado accepts. No SystemVerilog or external IP is used.

### Display integration

- SW0=0: first-person pixels with wave, health and crosshair HUD; no map.
- SW0=1: whole map at x=32..95, y=0..63, 4x4 pixels per tile, right-aligned. x=0..31 still shows first-person pixels with the wave/health HUD; the crosshair is hidden. A one-pixel white outline is drawn inside the outermost wall tiles.
- Colours: wall 4AD1, floor 0841, P1 spawn green 07E0, P2 spawn yellow FFE0. The map area is black until `map_ready`.
- The demo top supplies a placeholder first-person image (sky 1084 above y=32, floor 3166 below). Replace it with the raycaster's pixel and match its pixel latency.
- Composition order for every pixel: first-person pixel, then `hud_overlay`, then `map_display_mux`.
- Pixel (95,63): the course driver omits the last pixel, so `oled_tail_bridge` sends it separately, computed by a second HUD/mux instance (`last_hud`, `last_pixel_mux`). The raycaster must also supply its pixel for (95,63) to that path.
- SW0 is synchronised and captured at frame boundaries; it never regenerates the map or changes the seed.
- HUD text uses `font3x5` (includes H and W). Decimal conversion uses compare/subtract logic, with no division/modulo, new clocks, IP or BRAM.

### HUD layout and test controls

HUD glyphs are white FFFF, 3x5 pixels, one OLED pixel per font pixel; numbers always show two digits. The overlay is combinational and adds no pixel delay.

| Element | Pixel coordinates / behaviour |
|---|---|
| Wave | W at (2,2); tens at (8,2), ones at (12,2) |
| Health | H at (2,51), P at (6,51); tens at (12,51), ones at (16,51) |
| Health bar | x=2..26, y=58..60; background 4208; fill from x=2 for clamped health[6:2] pixels |
| Fill colour | F800 below 25 health, otherwise 07E0 |
| Crosshair | White plus centred at (48,32), two-pixel arms; hidden with SW0=1 |

In the demo, switches stand in for game state: SW15:SW9 = health (SW15 is the MSB; 100..127 shows 99) and SW4:SW1 = wave (0..15). Each switch is synchronised with two flip-flops and captured at the frame boundary. `hud_overlay` accepts 0..99 for both, ready for real health/wave signals.

### Supplied OLED driver compatibility

The course driver ends each frame after 6,143 pixels, omitting pixel (95,63). `oled_tail_bridge` queues the driver's serial bits and inserts that final 16-bit pixel at the data-to-command boundary; commands keep their order and values, and the driver source is unchanged. If the team switches to a driver that sends all 6,144 pixels, bypass the bridge and connect that driver's SPI pins directly.

## 3. Constraints and building the demo

Demo constraints: `constraints/map_preview.xdc` (Pmod OLEDrgb on **JB**).

| Port | Pin |
|---|---|
| clk | W5, 100 MHz |
| sw0 | V17 |
| sw_wave[1..4] = SW1..SW4 | V16, W16, W17, W15 |
| sw_health[9..15] = SW9..SW15 | V2, T3, T2, R3, W2, U1, R2 |
| btnC / btnU | U18 / T18 |
| JB[0..7] | A14, A16, B15, B16, A15, A17, C15, C16 |
| seg[0..6] = CA..CG | W7, W6, U8, V8, U5, V5, U7 |
| dp | V7 |
| an[0..3] (rightmost to leftmost) | U2, U4, V4, W4 |

The XDC also holds the 6.25 MHz generated-clock constraint, input-synchroniser exceptions and an assumed 20 ns output budget for the OLED SPI pins. Keep the generated-clock constraint when merging into the team XDC.

To build the demo, in a separate or temporary Vivado project:
1. Add all `.v` files under `FDP2026.srcs/sources_1/new/` (including subfolders).
2. Add `constraints/map_preview.xdc` and **do not** enable `Basys3_Master.xdc` at the same time; both drive the same pins.
3. Set the top module to `map_preview_top` (generic `STAGE=3`) and generate the bitstream.

Stage-3 demo build result: no latches or multi-driven nets, timing met, about 3.1k LUTs and 3.8k flip-flops, 0 BRAM and 0 DSP. Recheck timing and resources after integration.

## 4. Self-checking testbenches

Add the files in `sim/map/` to a Vivado simulation set together with the design sources and run the desired top (`tb_stage3`, `tb_display`, `tb_hud`, `tb_sevenseg`, `tb_controls`, `tb_oled`, `tb_stage1`, `tb_stage2`). Each prints `PASS ...` on success and `FAIL ...` on any mismatch. `tb_stage_common.v` and `hud_reference.v` are helpers, not tops.

| Testbench | Coverage |
|---|---|
| `tb_stage1.v` / `tb_stage2.v` / `tb_stage3.v` | Same-seed replay, 50 seeds, independent flood-fill connectivity check, zero seed, reset during generation; stage 3 gates publication on hardware BFS |
| `tb_stage_common.v` | Shared: depth-3 splits, second doors, stack bound; validator fault injection (isolated tile, boundary hole, no floor, one floor, timeout, retry exhaustion) |
| `tb_display.v` | Every pixel in both SW0 modes, HUD then map priority, border |
| `tb_hud.v` | 245,760 pixels across health/wave cases, clamping and both modes against an independent reference |
| `tb_sevenseg.v` | All 16 glyphs on all four digits, scan order and timing, reset, 1ACE left to right |
| `tb_controls.v` | Debounce, one request per held press, seed latch, switch sync, mode change without regeneration, reset |
| `tb_oled.v` | Real driver startup and two full 6,144-pixel serial frames decoded from the Pmod pins |

## 5. On-board checklist

All of the following passed on a Basys 3 on 2026-10-23, including rule C, the 64x64 map view, the HUD and the seven-segment seed display.

1. Program the demo bitstream with the OLED on JB; the digits show `1ACE`.
2. SW0=0: W and two digits, HP and two digits, the health bar and a centred crosshair over sky/floor.
3. SW0=1: the 64x64 whole map with green/yellow spawns and a thin border; wave/health stay on the left; no crosshair.
4. btnC: a new map and seed (more rooms, sometimes two doors per wall); LD0 on, LD3:LD1 off; holding btnC gives one new map.
5. Toggling SW0 never changes the map or the seed. btnU returns to `1ACE` and the same map.
6. Health 0 / 24 / 25 / 99 / 127 (bar empty, red, green, full, shows 99); wave 00, 07, 15.
