`timescale 1ns / 1ps
// game_core: everything Member 4 owns, behind the ports agreed in the team
// interface spec. Instantiate this once in My_Top_Module.
//
//  - Map: generator + validator (map_system), one new map per game.
//  - Game flow: title -> generating -> countdown -> playing -> game over / victory.
//  - Waves and spawn selection (spawn handshake to the enemy module).
//  - Player health (3 hearts; one heart per player_hit pulse), weapon (6-round
//    magazine, reload FSM), shot_fired to combat.
//  - Display: gun, HUD, ammo, map overlay, zombie dots, effects and menus drawn
//    over world_pixel, then the Pmod OLEDrgb on JB through the course driver.
//
// world_pixel timing: pixel_x/pixel_y name the pixel AFTER the one being sent.
// The OLED needs 16 of its 6.25 MHz clocks (256 clk cycles) per pixel, and
// world_pixel is sampled on the 16th of them, so the world renderer has well
// over 128 clk cycles to answer. While no frame is being sent, (0,0) is asked.
//
// All signals are in the 100 MHz clk domain; rst is synchronous, active high.
module game_core #(parameter STAGE=3, parameter DEBOUNCE_CYCLES=1000000,
    parameter ENABLE_2P=0, parameter SHOW_CURSOR=1,
    parameter GEN_SHIFT=26, parameter COUNT_SHIFT=26, parameter OVER_SHIFT=27,
    parameter TINT_SHIFT=25, parameter BANNER_SHIFT=27, parameter BLINK_SHIFT=24,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23, parameter RELOAD_SHIFT=25,
    parameter WIN_WAVE=10)(
    input wire clk, input wire rst,
    // Board
    input wire btn_c, input wire btn_l,           // raw buttons, debounced here
    input wire sw_map,                            // raw switch: map overlay
    output wire [7:0] oled_jb,                    // Pmod OLEDrgb on JB
    output wire [6:0] seg, output wire dp, output wire [3:0] an,
    output wire [15:0] led,
    // Mouse (from Member 1's MouseCtl; pointer clamped to the screen)
    input wire [6:0] mouse_x, input wire [5:0] mouse_y,
    input wire mouse_left, input wire mouse_right, input wire mouse_event,
    // Map
    output wire [255:0] published_map,
    output wire map_ready, output wire map_busy,
    output wire [7:0] p1_addr, output wire [7:0] p2_addr,
    output wire [15:0] active_seed, output wire [2:0] error_code,
    // Game state
    output wire [2:0] game_state, output wire play_start,
    output wire [6:0] wave, output wire [1:0] health,
    // Player (Member 1)
    input wire [7:0] player_tile,
    // Display (Members 1 and 2)
    input wire [15:0] world_pixel,
    output wire [6:0] pixel_x, output wire [5:0] pixel_y,
    output wire frame_begin,                      // one clk pulse per OLED frame
    // Enemies and combat (Member 2)
    input wire spawn_ack, input wire enemy_defeated,
    input wire [255:0] occupied, input wire player_hit,
    output wire spawn_req, output wire [7:0] spawn_tile,
    output wire enemies_clear, output wire shot_fired);

    (* ASYNC_REG="TRUE" *) reg [1:0] switch_sync=0;
    reg [3:0] clk_div=0;
    wire oled_clk=clk_div[3];
    reg [5:0] oled_reset_hold=63;
    wire oled_reset=oled_reset_hold!=0;
    always @(posedge clk) begin
        switch_sync<={switch_sync[0],sw_map};
        // Never stop/reset the divided clock while resetting its consumers.
        clk_div<=clk_div+1'b1;
        if(rst) oled_reset_hold<=63;
        else if(oled_reset_hold!=0) oled_reset_hold<=oled_reset_hold-1'b1;
    end

    // ---------------- Buttons ----------------
    wire press_c,press_l;
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_filter(
        .clk(clk),.rst(rst),.button(btn_c),.pressed(press_c));
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_left(
        .clk(clk),.rst(rst),.button(btn_l),.pressed(press_l));

    // ---------------- Game flow, map and play state ----------------
    wire ready,busy;
    wire [2:0] retry_count;
    wire [15:0] seed;
    wire [2:0] flow_state;
    wire [1:0] count_digit;
    wire menu_sel,regenerate,over_ready;
    wire [5:0] progress;
    wire damage,tint,banner,low_blink;
    wire wave_clear,game_won;
    wire [5:0] alive;
    wire [6:0] remaining;
    wire [255:0] zombies = occupied;
    wire playing_now = flow_state==3'd3;
    assign map_ready=ready; assign map_busy=busy; assign active_seed=seed;
    assign game_state=flow_state;
    assign enemies_clear = play_start || !playing_now;
    // Fire: a new left-click or btnC during play. The menu never sees play clicks.
    reg mouse_left_prev, mouse_right_prev;
    always @(posedge clk) begin
        mouse_left_prev <= rst ? 1'b0 : mouse_left;
        mouse_right_prev <= rst ? 1'b0 : mouse_right;
    end
    wire fire_request = playing_now && (press_c || (mouse_left && !mouse_left_prev));
    wire reload_request = playing_now && (press_l || (mouse_right && !mouse_right_prev));
    wire weapon_flash, weapon_recoil, weapon_reloading;
    wire [2:0] ammo;
    wire [4:0] weapon_drop;
    wire [1:0] weapon_state, reload_phase;
    // Free-running seed source: the time spent on the title screen picks the map.
    reg [15:0] seed_counter;
    always @(posedge clk) if(rst) seed_counter<=1; else seed_counter<=seed_counter+1'b1;
    game_flow #(.ENABLE_2P(ENABLE_2P),.GEN_SHIFT(GEN_SHIFT),.COUNT_SHIFT(COUNT_SHIFT),
        .OVER_SHIFT(OVER_SHIFT)) flow(
        .clk(clk),.rst(rst),.btn_c(press_c),.btn_l(press_l),.btn_r(1'b0),
        .mouse_x(mouse_x),.mouse_y(mouse_y),.mouse_left(mouse_left),.mouse_event(mouse_event),
        .map_ready(ready),.map_busy(busy),.health_zero(health==2'd0),.game_won(game_won),
        .state(flow_state),.sel(menu_sel),.regenerate(regenerate),.play_start(play_start),
        .count_digit(count_digit),.progress(progress),.over_ready(over_ready));
    player_health hearts(.clk(clk),.rst(rst),.play_start(play_start),
        .playing(playing_now),.hit(player_hit),.health(health),.damage(damage));
    wave_controller #(.SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT),.WIN_WAVE(WIN_WAVE)) waves(
        .clk(clk),.rst(rst),.play_start(play_start),.playing(playing_now),
        .map_bits(published_map),.occupied(zombies),.player_tile(player_tile),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.wave(wave),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.alive(alive),
        .remaining(remaining),.wave_clear(wave_clear),.game_won(game_won));
    hud_effects_ctrl #(.TINT_SHIFT(TINT_SHIFT),.BANNER_SHIFT(BANNER_SHIFT),
        .BLINK_SHIFT(BLINK_SHIFT)) effects_ctrl(
        .clk(clk),.rst(rst),.playing(playing_now),.play_start(play_start),.damage(damage),
        .wave(wave),.health(health),.tint(tint),.banner(banner),.low_blink(low_blink));
    weapon_ctrl #(.FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT),
        .RELOAD_SHIFT(RELOAD_SHIFT)) weapon(
        .clk(clk),.rst(rst),.playing(playing_now),.fire(fire_request),.reload(reload_request),
        .flash(weapon_flash),.recoil(weapon_recoil),.shot_fired(shot_fired),
        .ammo(ammo),.reloading(weapon_reloading),.drop(weapon_drop),
        .state(weapon_state),.reload_phase(reload_phase));
    map_system #(.STAGE(STAGE)) core(.clk(clk),.rst(rst),.regenerate(regenerate),
        .seed_in(seed_counter),.published_map(published_map),.p1_addr(p1_addr),
        .p2_addr(p2_addr),.map_ready(ready),.busy(busy),.error_code(error_code),
        .active_seed(seed),.retry_count(retry_count));
    assign led={busy,11'b0,error_code,ready};
    seven_seg_hex seed_display(.clk(clk),.rst(rst),.value(seed),
        .seg(seg),.dp(dp),.an(an));

    // ---------------- Display ----------------
    wire oled_frame_begin,sending_pixels,sample_pixel;
    wire [12:0] pixel_index;
    // The only pixel-index coordinate conversions. Tile lookup below uses slices.
    wire [6:0] px=pixel_index % 96;
    wire [5:0] py=pixel_index / 96;
    // World pixel look-ahead: ask for the next pixel, sample it on the last
    // OLED clock of the current one (phase 15), use it when that pixel is sent.
    wire [12:0] ahead_index = !sending_pixels ? 13'd0 :
                              (pixel_index==13'd6143) ? 13'd0 : pixel_index+1'b1;
    assign pixel_x = ahead_index % 96;
    assign pixel_y = ahead_index / 96;
    reg [3:0] pixel_phase;
    reg [15:0] world_now, world_last;
    always @(posedge oled_clk) begin
        if(oled_reset) begin
            pixel_phase<=0; world_now<=0; world_last<=0;
        end else begin
            // Phase = the driver's 16-clock bit counter: 0 on a pixel's sample
            // clock, 1 on the first clock of a frame's pixel stream.
            pixel_phase <= (!sending_pixels || sample_pixel) ? 4'd1 : pixel_phase+1'b1;
            if(!sending_pixels) world_now<=world_pixel;         // pixel 0 of the next frame
            else if(pixel_phase==4'd15) begin
                world_now<=world_pixel;
                if(ahead_index==13'd6143) world_last<=world_pixel;  // sent by the tail bridge
            end
        end
    end
    // frame_begin for the other modules: one clk pulse per frame.
    reg frame_begin_prev;
    always @(posedge clk) frame_begin_prev <= rst ? 1'b0 : oled_frame_begin;
    assign frame_begin = oled_frame_begin && !frame_begin_prev;

    reg [255:0] frame_map;
    reg [7:0] frame_p1,frame_p2;
    reg [15:0] frame_seed;
    reg [1:0] frame_health;
    reg [6:0] frame_wave,frame_remaining;
    reg [255:0] frame_zombies;
    reg frame_clear,frame_flash,frame_recoil,frame_reloading;
    reg [2:0] frame_ammo;
    reg [4:0] frame_drop;
    reg frame_ready,frame_busy,frame_mode;
    reg [2:0] frame_error;
    reg [2:0] frame_screen;
    reg [1:0] frame_digit;
    reg frame_sel,frame_tint,frame_banner,frame_blink,frame_over_ready;
    reg [6:0] frame_cx; reg [5:0] frame_cy;
    reg [5:0] frame_progress;
    // Related clocks, explicitly constrained in XDC, not asynchronous CDC.
    // The supplied driver updates frame_begin on negedge; capture on posedge
    // so the next negedge samples a coherent frame and its first pixel.
    always @(posedge oled_clk) begin
        if(oled_reset) begin
            frame_map<={256{1'b1}}; frame_p1<=0; frame_p2<=0; frame_seed<=0;
            frame_health<=3; frame_wave<=1; frame_remaining<=0; frame_zombies<=0; frame_clear<=0;
            frame_flash<=0; frame_recoil<=0; frame_reloading<=0; frame_ammo<=6; frame_drop<=0;
            frame_ready<=0; frame_busy<=1; frame_mode<=0; frame_error<=0;
            frame_screen<=0; frame_digit<=3; frame_sel<=0;
            frame_cx<=48; frame_cy<=40; frame_progress<=0;
            frame_tint<=0; frame_banner<=0; frame_blink<=0; frame_over_ready<=0;
        end else if(oled_frame_begin) begin
            frame_map<=published_map; frame_p1<=p1_addr; frame_p2<=p2_addr;
            frame_health<=health; frame_wave<=wave;
            frame_remaining<=remaining; frame_zombies<=zombies; frame_clear<=wave_clear;
            frame_flash<=weapon_flash; frame_recoil<=weapon_recoil;
            frame_reloading<=weapon_reloading; frame_ammo<=ammo; frame_drop<=weapon_drop;
            frame_seed<=seed; frame_ready<=ready; frame_busy<=busy;
            frame_mode<=switch_sync[1]; frame_error<=error_code;
            frame_screen<=flow_state; frame_digit<=count_digit; frame_sel<=menu_sel;
            frame_cx<=mouse_x; frame_cy<=mouse_y; frame_progress<=progress;
            frame_tint<=tint; frame_banner<=banner; frame_blink<=low_blink;
            frame_over_ready<=over_ready;
        end
    end
    wire playing = frame_screen==3'd3;
    // Menu screen numbers: 0 title, 1 generating, 2 countdown, 3 game over, 4 victory.
    wire [2:0] menu_screen = (frame_screen==3'd4) ? 3'd3 : (frame_screen==3'd5) ? 3'd4 : frame_screen;
    wire [3:0] wave_tens,wave_ones;
    wave_digits frame_wave_digits(.value(frame_wave),.tens(wave_tens),.ones(wave_ones));
    wire [15:0] gun_pixel_data,hud_pixel_data,ammo_pixel_data,map_pixel_data,zombie_pixel_data,play_pixel_data,menu_pixel_data;
    weapon_overlay gun(.px(px),.py(py),.show(!frame_mode),.recoil(frame_recoil),.flash(frame_flash),
        .drop(frame_drop),.pixel_in(world_now),.pixel_out(gun_pixel_data));
    hud_overlay hud(.px(px),.py(py),.minimap_mode(frame_mode),.health(frame_health),
        .low_blink(frame_blink),.wave(frame_wave),.zombies(frame_remaining),
        .pixel_in(gun_pixel_data),.pixel_out(hud_pixel_data));
    ammo_overlay ammo_hud(.px(px),.py(py),.show(!frame_mode),.ammo(frame_ammo),
        .reloading(frame_reloading),.pixel_in(hud_pixel_data),.pixel_out(ammo_pixel_data));
    map_display_mux display_mux(.px(px),.py(py),.minimap_mode(frame_mode),
        .fp_pixel_data(ammo_pixel_data),.map_bits(frame_map),.p1_addr(frame_p1),
        .p2_addr(frame_p2),.seed(frame_seed),.map_ready(frame_ready),
        .busy(frame_busy),.bfs_enabled(STAGE==3),.error_code(frame_error),
        .pixel_data(map_pixel_data));
    zombie_overlay zombie_dots(.px(px),.py(py),.minimap_mode(frame_mode),.zombies(frame_zombies),
        .pixel_in(map_pixel_data),.pixel_out(zombie_pixel_data));
    play_effects effects(.px(px),.py(py),.pixel_in(zombie_pixel_data),.tint(frame_tint),
        .banner(frame_banner),.clear(frame_clear),.wave_tens(wave_tens),.wave_ones(wave_ones),
        .pixel_out(play_pixel_data));
    menu_screens #(.ENABLE_2P(ENABLE_2P)) menu(.px(px),.py(py),.screen(menu_screen),
        .sel(frame_sel),.cursor_x(frame_cx),.cursor_y(frame_cy),.show_cursor(SHOW_CURSOR!=0),
        .count_digit(frame_digit),.progress(frame_progress),.wave_tens(wave_tens),
        .wave_ones(wave_ones),.over_ready(frame_over_ready),.pixel(menu_pixel_data));
    wire [15:0] pixel_data = playing ? play_pixel_data : menu_pixel_data;
    wire raw_cs,raw_sdin,raw_sclk,raw_dcn;
    wire [15:0] last_gun_pixel_data,last_hud_pixel_data,last_ammo_pixel_data,last_map_pixel_data,last_zombie_pixel_data,last_play_pixel_data,last_menu_pixel_data;
    // Pixel (95,63) is sent separately by oled_tail_bridge: evaluate it through
    // the same HUD, map, effects and menu logic for a single source of truth.
    weapon_overlay last_gun(.px(7'd95),.py(6'd63),.show(!frame_mode),.recoil(frame_recoil),
        .flash(frame_flash),.drop(frame_drop),.pixel_in(world_last),.pixel_out(last_gun_pixel_data));
    hud_overlay last_hud(.px(7'd95),.py(6'd63),.minimap_mode(frame_mode),.health(frame_health),
        .low_blink(frame_blink),.wave(frame_wave),.zombies(frame_remaining),
        .pixel_in(last_gun_pixel_data),.pixel_out(last_hud_pixel_data));
    ammo_overlay last_ammo(.px(7'd95),.py(6'd63),.show(!frame_mode),.ammo(frame_ammo),
        .reloading(frame_reloading),.pixel_in(last_hud_pixel_data),.pixel_out(last_ammo_pixel_data));
    map_display_mux last_pixel_mux(.px(7'd95),.py(6'd63),.minimap_mode(frame_mode),
        .fp_pixel_data(last_ammo_pixel_data),.map_bits(frame_map),.p1_addr(frame_p1),
        .p2_addr(frame_p2),.seed(frame_seed),.map_ready(frame_ready),
        .busy(frame_busy),.bfs_enabled(STAGE==3),.error_code(frame_error),
        .pixel_data(last_map_pixel_data));
    zombie_overlay last_zombie_dots(.px(7'd95),.py(6'd63),.minimap_mode(frame_mode),
        .zombies(frame_zombies),.pixel_in(last_map_pixel_data),.pixel_out(last_zombie_pixel_data));
    play_effects last_effects(.px(7'd95),.py(6'd63),.pixel_in(last_zombie_pixel_data),
        .tint(frame_tint),.banner(frame_banner),.clear(frame_clear),.wave_tens(wave_tens),.wave_ones(wave_ones),
        .pixel_out(last_play_pixel_data));
    menu_screens #(.ENABLE_2P(ENABLE_2P)) last_menu(.px(7'd95),.py(6'd63),.screen(menu_screen),
        .sel(frame_sel),.cursor_x(frame_cx),.cursor_y(frame_cy),.show_cursor(SHOW_CURSOR!=0),
        .count_digit(frame_digit),.progress(frame_progress),.wave_tens(wave_tens),
        .wave_ones(wave_ones),.over_ready(frame_over_ready),.pixel(last_menu_pixel_data));
    wire [15:0] last_pixel_data = playing ? last_play_pixel_data : last_menu_pixel_data;
    Oled_Display oled(.clk(oled_clk),.reset(oled_reset),.frame_begin(oled_frame_begin),
        .sending_pixels(sending_pixels),.sample_pixel(sample_pixel),
        .pixel_index(pixel_index),.pixel_data(pixel_data),
        .cs(raw_cs),.sdin(raw_sdin),.sclk(raw_sclk),.d_cn(raw_dcn),
        .resn(oled_jb[5]),.vccen(oled_jb[6]),.pmoden(oled_jb[7]));
    oled_tail_bridge tail_bridge(.clk(oled_clk),.rst(oled_reset),
        .raw_cs(raw_cs),.raw_sdin(raw_sdin),.raw_dcn(raw_dcn),
        .last_pixel_data(last_pixel_data),.cs(oled_jb[0]),.sdin(oled_jb[1]),
        .d_cn(oled_jb[4]),.sclk(oled_jb[3]));
    assign oled_jb[2]=1'b0;
endmodule
