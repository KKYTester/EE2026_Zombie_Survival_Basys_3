# Map generation, validation, map overlay and HUD (Member 4)

Procedural 16x16 map generator with BFS validation, a title screen and single-player game flow (mouse or buttons) with game over, wave progression with zombie spawn selection, an OLED map overlay and HUD (wave, zombies left, 3 hearts, low-health flash, damage tint, wave banners, first-person pistol with recoil and muzzle flash), and a seven-segment seed display. It is not yet instantiated in `My_Top_Module`; that happens at team integration. `map_preview_top` is a standalone demo of this subsystem.

## Where the files are

| Folder | Contents |
|---|---|
| `FDP2026.srcs/sources_1/new/map/` | `map_system` (the module to instantiate), `map_generator`, `map_storage`, `map_validator`, `lfsr16` |
| `FDP2026.srcs/sources_1/new/game/` | `game_flow` (title -> play -> game over), `wave_controller` (waves and spawn handshake), `spawn_finder` (far, free spawn tile) |
| `FDP2026.srcs/sources_1/new/ui/` | `menu_screens`, `weapon_overlay`, `weapon_ctrl`, `hud_overlay`, `hud_effects_ctrl`, `play_effects`, `zombie_overlay`, `wave_digits`, `map_display_mux`, `font3x5`, `seven_seg_hex`, `button_debounce`, `oled_tail_bridge` |
| `FDP2026.srcs/sources_1/new/` (team files) | `Mouse_Control.vhd` (`MouseCtl`) and `Ps2Interface.vhd`, Digilent mouse controller used by the title screen |
| `FDP2026.srcs/sources_1/new/demo/` | `map_preview_top` (standalone demo top); temporary stand-ins `play_test_inputs` (3-heart health, btnD) and `zombie_stub` (enemy side of the spawn handshake, btnR defeats) |
| `sim/map/` | Self-checking testbenches (`weapon_golden.hex` is test data for `tb_weapon`) |
| `scripts/map/` | `gun_sprite.py` (the pistol drawing) and `gen_weapon_overlay.py`, which regenerates `weapon_overlay.v` and the golden test frames from it |
| `constraints/map_preview.xdc` | Pins for the standalone demo only; deliberately outside `constrs_1` |

## Interface for teammates

- `published_map[255:0]`: tile at index `{y[3:0], x[3:0]}`; 1 = wall, 0 = floor. x increases to the right, y increases downward; the outer edge is always wall.
- Valid only while `map_ready` = 1. It changes only when a new map is requested, never during gameplay.
- `p1_addr`, `p2_addr`: spawn tiles in the same `{y,x}` format. `active_seed[15:0]`: seed of the current map (send this between boards so both regenerate the same map).
- The first-person image enters the display chain through `fp_pixel_data`; HUD and map overlay are drawn on top. See "Display integration" for the bottom-right pixel.
- Player health for the HUD and game over is 0..3 hearts plus a one-clock `damage` pulse per heart lost. In the demo `play_test_inputs` provides these from btnD; with combat integrated, Member 2's authoritative health replaces it.
- **Spawn handshake (Member 2):** `wave_controller` raises `spawn_req` with `spawn_tile[7:0]` ({y,x}) and holds both until `spawn_ack` (one clock). The enemy module pulses `enemy_defeated` once per zombie killed and reports occupied tiles as a 256-bit mask (`occupied`) so new zombies never spawn on existing ones. At most n+2 zombies are requested at once in wave n, up to 8 (`MAX_ALIVE`). In the demo `zombie_stub` plays this role.
- **Shots (Member 2):** `weapon_ctrl` pulses `shot_fired` once per accepted shot (left-click or btnC during play, at most about 12 per second). Combat decides whether a zombie is hit; the gun animation is feedback only.
- **Player tile (Member 1):** `wave_controller.player_tile` ({y,x}) is the P1 spawn in the demo; connect the player's current tile once movement exists so spawns stay far from the player.


## 1. Module hierarchy and ports

`map_preview_top` synchronises controls, debounces btnC/btnL/btnR/btnD, reads the mouse through `MouseCtl`, makes the 6.25 MHz OLED clock, and instantiates `game_flow` and `map_system`. `game_flow` runs title -> generating -> countdown -> playing -> game over and requests one new map per game; `menu_screens` draws the full-screen screens; `hud_effects_ctrl` times the damage tint, wave banner and low-health flash that `play_effects` and `hud_overlay` draw. `wave_controller` runs the waves and asks `spawn_finder` for each spawn tile. A `seven_seg_hex` driver displays the current active seed on the board's four digits. That subsystem sequences `map_generator`, its `lfsr16`, register-based `map_storage`, and `map_validator`, publishing a coherent map only after the selected stage's checks succeed. The top captures map, status, mode, health, wave and effect flags at frame boundaries. Play pixels pass through `weapon_overlay`, then `hud_overlay`, then `map_display_mux`, then `zombie_overlay`, then `play_effects`. The repository's course-supplied `Oled_Display.v` serialises these pixels unmodified. An `oled_tail_bridge` preserves its commands and inserts the final pixel omitted by this version of the driver. The generator, validator and core run at 100 MHz; the display frame registers, driver and bridge use the related, constrained 6.25 MHz clock.

All widths below are bits. Signals are synchronous to `clk` unless stated otherwise. Reset `rst` is synchronous, active high.

| Module | Inputs | Outputs / parameters |
|---|---|---|
| `map_preview_top` | `clk`, `sw0`, `btnC`, `btnU`, `btnL`, `btnR`, `btnD`, `PS2Clk`/`PS2Data` (inout) | `led[15:0]`, `JB[7:0]`, `seg[6:0]`, `dp`, `an[3:0]`; `STAGE=3`, `DEBOUNCE_CYCLES=1000000`, `USE_MOUSE=1`, `ENABLE_2P=0`, `GEN_SHIFT=26`, `COUNT_SHIFT=26`, `OVER_SHIFT=27`, `TINT_SHIFT=25`, `BANNER_SHIFT=27`, `BLINK_SHIFT=24`, `SPAWN_SHIFT=26`, `CLEAR_SHIFT=27`, `FLASH_SHIFT=22`, `RECOIL_SHIFT=23` |
| `game_flow` | `clk`, `rst`, `btn_c`/`btn_l`/`btn_r` (pulses), `mouse_x[6:0]`, `mouse_y[5:0]`, `mouse_left`, `mouse_event`, `map_ready`, `map_busy`, `health_zero` | `state[2:0]` (0 title, 1 generating, 2 countdown, 3 playing, 4 game over), `sel`, `regenerate`, `play_start`, `count_digit[1:0]`, `progress[5:0]`, `over_ready`; `ENABLE_2P`, `GEN_SHIFT`, `COUNT_SHIFT`, `OVER_SHIFT` |
| `menu_screens` | `px`, `py`, `screen[1:0]` (0 title, 1 generating, 2 countdown, 3 game over), `sel`, `cursor_x[6:0]`, `cursor_y[5:0]`, `show_cursor`, `count_digit[1:0]`, `progress[5:0]`, `wave_tens[3:0]`, `wave_ones[3:0]`, `over_ready` | `pixel[15:0]`; combinational; `ENABLE_2P` |
| `hud_effects_ctrl` | `clk`, `rst`, `playing`, `play_start`, `damage`, `wave[6:0]`, `health[1:0]` | `tint`, `banner`, `low_blink`; `TINT_SHIFT`, `BANNER_SHIFT`, `BLINK_SHIFT` |
| `play_effects` | `px`, `py`, `pixel_in[15:0]`, `tint`, `banner`, `clear`, `wave_tens[3:0]`, `wave_ones[3:0]` | `pixel_out[15:0]`; combinational |
| `wave_controller` | `clk`, `rst`, `play_start`, `playing`, `map_bits[255:0]`, `occupied[255:0]`, `player_tile[7:0]`, `spawn_ack`, `enemy_defeated` | `wave[6:0]`, `spawn_req`, `spawn_tile[7:0]`, `alive[5:0]`, `remaining[6:0]`, `wave_clear`; `MAX_ALIVE=8` (per-wave limit n+2), `MAX_WAVE_SIZE=21`, `SPAWN_SHIFT=26`, `CLEAR_SHIFT=27`, `MIN_DIST=8` |
| `spawn_finder` | `clk`, `rst`, `start`, `map_bits[255:0]`, `occupied[255:0]`, `player_tile[7:0]`, `random_start[7:0]` | `busy`, `done`, `found`, `tile[7:0]`; `MIN_DIST=8` |
| `zombie_overlay` | `px`, `py`, `minimap_mode`, `zombies[255:0]`, `pixel_in[15:0]` | `pixel_out[15:0]`; combinational |
| `weapon_overlay` | `px`, `py`, `show`, `recoil`, `flash`, `pixel_in[15:0]` | `pixel_out[15:0]`; combinational 28x24 pistol sprite ROM (generated) |
| `weapon_ctrl` | `clk`, `rst`, `playing`, `fire` | `flash`, `recoil`, `shot_fired`; `FLASH_SHIFT=22`, `RECOIL_SHIFT=23` |
| `zombie_stub` (temporary) | `clk`, `rst`, `clear`, `spawn_req`, `spawn_tile[7:0]`, `defeat` | `spawn_ack`, `enemy_defeated`, `occupied[255:0]`; `SLOTS=8` |
| `wave_digits` | `value[6:0]` | `tens[3:0]`, `ones[3:0]` (values above 99 show 99) |
| `play_test_inputs` (temporary) | `clk`, `rst`, `play_start`, `playing`, `btn_d` | `health[1:0]`, `damage` |
| `MouseCtl` (team file, Digilent) | `clk`, `rst`, `value[11:0]`, `setx`, `sety`, `setmax_x`, `setmax_y`, `ps2_clk`, `ps2_data` | `xpos[11:0]`, `ypos[11:0]`, `zpos`, `left`, `middle`, `right`, `new_event` |
| `seven_seg_hex` | `clk` (100 MHz), `rst`, `value[15:0]` | Active-low `seg[6:0]` (bit 0=CA, bit 6=CG), `dp`, `an[3:0]` |
| `map_system` | `clk`, `rst`, `regenerate`, `seed_in[15:0]` | `published_map[255:0]`, `p1_addr[7:0]`, `p2_addr[7:0]`, `map_ready`, `busy`, `error_code[2:0]`, `active_seed[15:0]`, `retry_count[2:0]`; `STAGE`, `INITIAL_SEED=16'h1ACE`, `GEN_LIMIT=4096`, `VALIDATE_LIMIT=4096` |
| `map_generator` | `clk`, `rst`, `start`, `seed[15:0]` | `write_en`, `write_addr[7:0]`, `write_wall`, `busy`, `done`; `FIXED_MAP=0` |
| `map_storage` | `clk`, `rst`, `write_en`, `write_addr[7:0]`, `write_wall` | `map_bits[255:0]` |
| `lfsr16` | `clk`, `rst`, `load`, `advance`, `seed[15:0]` | `value[15:0]` |
| `map_validator` | `clk`, `rst`, `start`, `map_bits[255:0]` | `busy`, `done`, `passed`, `error_code[2:0]`, `p1_addr[7:0]`, `p2_addr[7:0]`, `floor_count[8:0]`, `reachable_count[8:0]`; `CHECK_CONNECTIVITY=1`, `MAX_CYCLES=4096` |
| `button_debounce` | `clk`, `rst`, `button` | `pressed` (one clock); `STABLE_CYCLES=1000000` |
| `map_display_mux` | `px[6:0]`, `py[5:0]`, `minimap_mode`, `fp_pixel_data[15:0]`, `map_bits[255:0]`, `p1_addr[7:0]`, `p2_addr[7:0]`, `seed[15:0]`, `map_ready`, `busy`, `bfs_enabled`, `error_code[2:0]` | `pixel_data[15:0]`; purely combinational |
| `hud_overlay` | `px[6:0]`, `py[5:0]`, `minimap_mode`, `health[1:0]`, `low_blink`, `wave[6:0]`, `zombies[6:0]`, `pixel_in[15:0]` | `pixel_out[15:0]`; combinational, numbers clamped to 99 |
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
- Wall and door positions are chosen uniformly among the legal candidates: index = (8 random bits x count) >> 8 (an 8x3-bit multiply, no scan).
- A second door (50%) is kept only if it is at least 4 tiles from the first, so no single wall tile is left floating between two gaps.
- Early stopping (25%, depth >= 2) applies only to rooms whose sides are both <= 10 tiles, so there are no giant empty halls.
- The finished map is mirrored in x, in y and/or transposed according to seed bits [15:13] (8 symmetries), by remapping write addresses. Spawns stay in opposite corners.
- Every split joins its child rooms through at least one door. Child walls have even coordinates and cannot seal an ancestor's odd doorway. Additional doors and early stopping preserve connectivity. BFS still validates the finished map before publication.
- LFSR B400, its advance points (S_ORIENT and S_DOOR_INIT), min/max x+y spawn rules, retry logic, error codes and map interface are unchanged. The same seed always produces the same map.
- The generator draws at most one tile per clock. With at most 31 visited regions and 15 splits it needs about 600 clocks (256 initial writes + 31x2 + 15x19); 500 tested seeds finish in under 700 clocks before validation.
- Generation and validation watchdogs are each **4096 clocks**. A conservative terminal bound for initial attempt plus four retries is **41000 clocks = 5*(4096+4096+8)**, allowing eight control/handshake clocks per attempt. This is 410 us at 100 MHz, excluding debounce and OLED startup/refresh.
- `published_map` updates only after a pass. Busy presses are ignored; holding btnC produces one request. The validator and error handling are unchanged.

### LEDs and errors

LD0 = map_ready; LD3:LD1 = error (0 OK, 1 OPEN_BOUNDARY, 2 DISCONNECTED, 3 BAD_SPAWN, 4 TIMEOUT); LD15 = busy. Remaining LEDs are zero. There is no on-screen status strip.

### Seed display and controls

The board boots to the title screen. Point at **1 PLAYER** with the mouse and left-click, or press btnC, to start: the current value of a free-running counter becomes the seed, one map is generated (the GENERATING screen shows for about 0.7 s), then a 3-2-1 countdown (about 0.7 s per digit) leads to the playing view. **2 PLAYERS** is shown greyed out and cannot be selected until two-player mode exists (`ENABLE_2P`). btnL/btnR move the selection when 2P is enabled. Menu clicks and btnC are consumed by the menu and never fire the gun.

Every game starts at wave 1 with 3 hearts. Wave n has 3 + 2(n-1) zombies (up to 21), spawned on floor tiles at least 8 walking steps from the player. Waves get more intense: at most n+2 zombies are alive at once (up to 8), and spawns come about 0.7 s apart in waves 1-2, 0.34 s in waves 3-4 and 0.17 s from wave 5. When all of a wave's zombies are defeated, WAVE CLEAR shows for about 1.3 s and the next wave starts. A pistol is held at the bottom of the view; **left-click or btnC fires** (the gun kicks down and a muzzle flash shows; about 12 shots per second at most). Until combat exists, two test buttons stand in during play: **btnD** loses a heart and **btnR** defeats the oldest zombie. Losing the last heart shows **GAME OVER** with the wave reached; after about 1.3 s, CLICK TO RETRY appears and a click or btnC returns to the title. btnU resets to the title screen and the boot seed `1ACE`. The four seven-segment digits always show the current `active_seed`.

`seven_seg_hex` uses an 18-bit free-running counter on the existing 100 MHz clock. Bits [17:16] select an[0], an[1], an[2], an[3] in that order. an[0] shows value[3:0]; an[3] shows value[15:12]. Glyphs are 0-9, A, b, C, d, E, F; all segments and anodes are active-low. DP is held high (off); synchronous reset clears the counter and blanks the digits.

**ASSUMPTION:** the explicitly requested counter bits take precedence over the approximate 1.3 ms description: each digit lasts 65536 clocks = 0.65536 ms at 100 MHz; one full scan is 2.62144 ms (381.47 Hz). No new clock, IP, divider or modulo operator is introduced for this display.

## 2. Source notes

The authored RTL uses Verilog-2001 constructs. The course `Oled_Display.v` (already in this repository, unchanged) contains `$clog2` expressions, which Vivado accepts. No SystemVerilog or external IP is used.

### Display integration

- Title, generating and countdown screens fill the whole OLED (`menu_screens`). The views below apply only in the playing state.
- SW0=0: first-person pixels with wave, health and crosshair HUD; no map.
- SW0=1: whole map at x=32..95, y=0..63, 4x4 pixels per tile, right-aligned. x=0..31 still shows first-person pixels with the wave/health HUD; the crosshair is hidden. A one-pixel white outline is drawn inside the outermost wall tiles.
- Colours: wall 4AD1, floor 0841, P1 spawn green 07E0, P2 spawn yellow FFE0. The map area is black until `map_ready`.
- The demo top supplies a placeholder first-person image (sky 1084 above y=32, floor 3166 below). Replace it with the raycaster's pixel and match its pixel latency.
- Composition order for every play pixel: first-person pixel, then `weapon_overlay`, then `hud_overlay`, then `map_display_mux`, then `play_effects` (wave banner, then damage tint over everything).
- Pixel (95,63): the course driver omits the last pixel, so `oled_tail_bridge` sends it separately, computed by second instances of the same chain (`last_gun`, `last_hud`, `last_pixel_mux`, `last_effects`, `last_menu`). The raycaster must also supply its pixel for (95,63) to that path.
- SW0 is synchronised and captured at frame boundaries; it never regenerates the map or changes the seed.
- HUD text uses `font3x5` (includes H and W). Decimal conversion uses compare/subtract logic, with no division/modulo, new clocks, IP or BRAM.

### HUD layout and effects

The HUD is combinational and adds no pixel delay. Text is white FFFF, 3x5 pixels.

| Element | Pixel coordinates / behaviour |
|---|---|
| Wave | W at (2,2); tens at (8,2), ones at (12,2) |
| Zombies left | Z at (2,9); tens at (8,9), ones at (12,9): zombies of this wave not yet defeated |
| Health | Three 5x5 hearts at x=2, 8, 14, y=56..60; remaining hearts red F800, lost hearts grey 4208 |
| Low health | With one heart left, the last heart flashes red/grey about 3 times a second (`BLINK_SHIFT=24`) |
| Damage | Every heart lost tints the whole play view red for about 0.34 s (`TINT_SHIFT=25`): red channel r/2+16, green and blue halved |
| Wave banner | "WAVE n" at 2x size, yellow F645 on a dark band at y=22..35, for about 1.3 s when play starts and whenever the wave changes (`BANNER_SHIFT=27`); "WAVE CLEAR" during the pause between waves |
| Zombies on the map | Red 2x2 dots on the SW0 map at their tiles (`zombie_overlay`) |
| Crosshair | White plus centred at (48,32), two-pixel arms; hidden with SW0=1 |
| Pistol | 28x24 sprite at x=41..68, y=40..63 (hand and sleeve from the bottom-right), under the HUD; hidden with SW0=1 |
| Firing | Gun kicks down 2 px for about 84 ms and a muzzle flash shows above the slide for about 42 ms |
| Game over | Full screen: GAME OVER (2x, red), WAVE n, then CLICK TO RETRY once input is accepted |

With the map overlay on, the wave text and hearts stay left of x=32.

### Supplied OLED driver compatibility

The course driver ends each frame after 6,143 pixels, omitting pixel (95,63). `oled_tail_bridge` queues the driver's serial bits and inserts that final 16-bit pixel at the data-to-command boundary; commands keep their order and values, and the driver source is unchanged. If the team switches to a driver that sends all 6,144 pixels, bypass the bridge and connect that driver's SPI pins directly.

## 3. Constraints and building the demo

Demo constraints: `constraints/map_preview.xdc` (Pmod OLEDrgb on **JB**).

| Port | Pin |
|---|---|
| clk | W5, 100 MHz |
| sw0 | V17 |
| btnC / btnU | U18 / T18 |
| btnL / btnR | W19 / T17 |
| btnD (test: lose a heart) | U17 |
| btnR during play (test: defeat a zombie) | T17 |
| PS2Clk / PS2Data (USB mouse) | C17 / B17, with pull-ups |
| JB[0..7] | A14, A16, B15, B16, A15, A17, C15, C16 |
| seg[0..6] = CA..CG | W7, W6, U8, V8, U5, V5, U7 |
| dp | V7 |
| an[0..3] (rightmost to leftmost) | U2, U4, V4, W4 |

The XDC also holds the 6.25 MHz generated-clock constraint, input-synchroniser exceptions and an assumed 20 ns output budget for the OLED SPI pins. Keep the generated-clock constraint when merging into the team XDC.

To build the demo, in a separate or temporary Vivado project:
1. Add all `.v` and `.vhd` files under `FDP2026.srcs/sources_1/new/` (including subfolders); the mouse controller is VHDL.
2. Add `constraints/map_preview.xdc` and **do not** enable `Basys3_Master.xdc` at the same time; both drive the same pins.
3. Set the top module to `map_preview_top` (generic `STAGE=3`) and generate the bitstream.

Stage-3 demo build (2026-10-24, before the hearts/game-over update): no latches or multi-driven nets, timing met, about 4.0k LUTs and 4.2k flip-flops, 0 BRAM and 0 DSP. Recheck timing and resources after integration.

## 4. Self-checking testbenches

Add the files in `sim/map/` to a Vivado simulation set together with the design sources and run the desired top (`tb_stage3`, `tb_display`, `tb_hud`, `tb_sevenseg`, `tb_controls`, `tb_menu`, `tb_oled`, `tb_spawn`, `tb_wave`, `tb_weapon`, `tb_stage1`, `tb_stage2`). Each prints `PASS ...` on success and `FAIL ...` on any mismatch. `tb_stage_common.v` and `hud_reference.v` are helpers, not tops.

| Testbench | Coverage |
|---|---|
| `tb_stage1.v` / `tb_stage2.v` / `tb_stage3.v` | Same-seed replay, 50 seeds, independent flood-fill connectivity check, zero seed, reset during generation; stage 3 gates publication on hardware BFS |
| `tb_stage_common.v` | Shared: depth-3 splits, second doors, stack bound; validator fault injection (isolated tile, boundary hole, no floor, one floor, timeout, retry exhaustion) |
| `tb_display.v` | Every pixel in both SW0 modes, HUD then map priority, border |
| `tb_hud.v` | 393,216 pixels: 0-3 hearts with and without the low-health flash, wave cases incl. clamping, both modes, against an independent reference |
| `tb_sevenseg.v` | All 16 glyphs on all four digits, scan order and timing, reset, 1ACE left to right |
| `tb_controls.v` | A whole game: title, debounce, one map per game, countdown, wave banner, zombies spawn, btnR defeats them, WAVE CLEAR, wave 2, btnD damage with tint, low-health flash, SW0 without regeneration, game over with input delay, retry, reset |
| `tb_weapon.v` | Idle and firing frames against golden frames generated from the sprite drawing, hidden with the map, one continuous flash and recoil per shot, one `shot_fired` per shot, fire ignored during recoil and outside play. Add `weapon_golden.hex` to the simulation sources |
| `tb_spawn.v` | 141 spawn searches on 20 generated maps plus a tiny map, against an independent BFS: every tile is floor, free and at least 8 steps away; "not found" only when none exists |
| `tb_wave.v` | Waves 1-5: sizes 3/5/7/9/11, alive limits 3/4/5/6/7 reached but never exceeded, spawn gaps halving at waves 3 and 5, spawns on free floor, WAVE CLEAR pauses, restart, spurious kills ignored |
| `tb_menu.v` | Menu pixels (title, highlight, greyed 2P, cursor, progress bar, countdown digit, game over and retry hint); mouse hover and click start; clicks outside the options or on 2P ignored |
| `tb_oled.v` | Real driver startup; title, generating/countdown and playing frames (including wave banner, damage tint and zombie dots on the map) decoded pixel by pixel from the Pmod pins |

## 5. On-board checklist

Passed on a Basys 3: map generation, map view and seed display (2026-10-23); title screen, mouse, game flow and polished generator (2026-10-24). Hearts, effects, game over, waves with rising intensity, zombie spawning and the pistol passed on the board on 2026-10-24 (timing met; about 6.4k LUTs, 5.3k flip-flops, 0 BRAM, 0 DSP).

1. Plug a USB mouse into the board's USB host port and program the bitstream with the OLED on JB.
2. Click 1 PLAYER (or btnC) -> GENERATING MAP -> 3, 2, 1 -> play view with "WAVE 1", three red hearts, W 01 and Z 03.
3. SW0 on: red dots appear on the map one by one (up to 3 in wave 1), never right next to the green player dot.
4. btnR removes the oldest red dot and Z counts down. After the last one, WAVE CLEAR shows, then "WAVE 2" with Z 05; at most 4 dots at once, the 5th appears after one is removed. Later waves allow more dots at once (5 in wave 3, up to 8) and they appear faster.
5. Left-click or btnC: the gun kicks and a muzzle flash shows; holding the button does not auto-fire.
6. btnD: a heart turns grey with a red flash; one heart left flashes; the last heart gives GAME OVER with the wave reached, then CLICK TO RETRY.
7. A new game starts again at wave 1 with three hearts, no dots and a new seed. btnU returns to the title with `1ACE`.
8. Without a mouse plugged in, btnC still starts and retries.
