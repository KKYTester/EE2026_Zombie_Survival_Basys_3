`timescale 1ns / 1ps
// game_core: everything Member 4 owns, behind the ports agreed in the team
// interface spec. Instantiate this once in My_Top_Module.
//
//  - Map: generator + validator (map_system), one new map per game.
//  - Game flow: title -> generating -> playing -> game over / victory.
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
    parameter [15:0] FIXED_MAP_SEED=16'h0000,
    parameter GEN_SHIFT=26, parameter OVER_SHIFT=27,
    parameter TINT_SHIFT=25, parameter BLINK_SHIFT=24,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23, parameter RELOAD_SHIFT=25,
    parameter WIN_WAVE=10)(
    input wire clk, input wire rst,
    // Board
    input wire btn_c,                             // raw button, debounced here
    input wire btn_d,                             // one-clock title-menu selection pulse
    input wire sw_map,                            // raw switch: map overlay
    output wire [7:0] oled_jb,                    // Pmod OLEDrgb on JB
    output wire [6:0] seg, output wire dp, output wire [3:0] an,
    output wire [15:0] led,
    // Mouse (from delta-packet pointer accumulator; clamped to the screen)
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
    output wire selected_2p,                      // title selection
    // Two-board play (ENABLE_2P): each board plays its own game on the same
    // map. Inputs are the other board's status (see game_flow); outputs are
    // this board's role for the status it sends back.
    input wire link_up,
    input wire [2:0] peer_state, input wire peer_2p, input wire peer_leader,
    input wire [7:0] peer_token, input wire [15:0] peer_priority,
    input wire [15:0] peer_seed,
    input wire [6:0] peer_wave, input wire peer_in_run,  // shown on end screens
    output wire two_player, output wire leader,
    output wire [7:0] game_token, output wire [15:0] start_priority,
    // Player (Member 1)
    input wire [7:0] player_tile,                 // {y,x} tile the player stands on
    // Player position for the minimap: tiles with 4 fractional bits, y down
    // (same orientation as the map rows); angle 1024 units per turn, 0 = up,
    // clockwise. {player_pos_y[7:4], player_pos_x[7:4]} should equal player_tile.
    input wire [7:0] player_pos_x, input wire [7:0] player_pos_y,
    input wire [9:0] player_angle,
    // Display (Members 1 and 2)
    input wire [15:0] world_pixel,
    output wire [6:0] pixel_x, output wire [5:0] pixel_y,
    output wire frame_begin,                      // one clk pulse per OLED frame
    output wire frame_idle,                       // safe window to present the next world frame
    // Enemies and combat (Member 2)
    input wire spawn_ack, input wire enemy_defeated,
    input wire [255:0] occupied, input wire player_hit,
    output wire spawn_req, output wire [7:0] spawn_tile, output wire spawn_busy,
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
    // btnU/btnL/btnR/btnD are left free for Member 1's movement controls.
    wire press_c;
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_filter(
        .clk(clk),.rst(rst),.button(btn_c),.pressed(press_c));

    // ---------------- Game flow, map and play state ----------------
    wire ready,busy;
    wire [2:0] retry_count;
    wire [15:0] seed;
    wire [2:0] flow_state;
    wire menu_sel,regenerate,over_ready;
    wire [5:0] progress;
    wire damage,tint,low_blink;
    wire wave_clear,game_won;
    wire [5:0] alive;
    wire [6:0] remaining;
    wire [255:0] zombies = occupied;
    wire playing_now = flow_state==3'd3;
    assign map_ready=ready; assign map_busy=busy; assign active_seed=seed;
    assign game_state=flow_state;
    assign selected_2p=menu_sel;
    assign enemies_clear = play_start || !playing_now;
    // Fire: a new left-click or btnC during play. The menu never sees play clicks.
    reg mouse_left_prev, mouse_right_prev;
    always @(posedge clk) begin
        mouse_left_prev <= rst ? 1'b0 : mouse_left;
        mouse_right_prev <= rst ? 1'b0 : mouse_right;
    end
    wire fire_request = playing_now && (press_c || (mouse_left && !mouse_left_prev));
    // Reload: a new right-click during play (no button, so btnL stays free for movement).
    wire reload_request = playing_now && mouse_right && !mouse_right_prev;
    wire weapon_flash, weapon_recoil, weapon_reloading;
    wire [2:0] ammo;
    wire [4:0] weapon_drop;
    wire [1:0] weapon_state, reload_phase;
    // Free-running seed source: the time spent on the title screen picks the map.
    reg [15:0] seed_counter;
    always @(posedge clk) if(rst) seed_counter<=1; else seed_counter<=seed_counter+1'b1;
    // A board joining a 2-player game builds the leader's map from its seed.
    wire use_peer_seed;
    wire [15:0] generator_seed = use_peer_seed ? peer_seed :
                                 (FIXED_MAP_SEED==16'h0000) ? seed_counter : FIXED_MAP_SEED;
    game_flow #(.ENABLE_2P(ENABLE_2P),.GEN_SHIFT(GEN_SHIFT),
        .OVER_SHIFT(OVER_SHIFT)) flow(
        .clk(clk),.rst(rst),.btn_c(press_c),.btn_d(btn_d),.btn_l(1'b0),.btn_r(1'b0),
        .mouse_x(mouse_x),.mouse_y(mouse_y),.mouse_left(mouse_left),.mouse_event(mouse_event),
        .map_ready(ready),.map_busy(busy),.health_zero(health==2'd0),.game_won(game_won),
        .random(seed_counter),.link_up(link_up),
        .peer_state(peer_state),.peer_2p(peer_2p),.peer_leader(peer_leader),
        .peer_token(peer_token),.peer_priority(peer_priority),
        .two_player(two_player),.leader(leader),.token(game_token),
        .start_priority(start_priority),.use_peer_seed(use_peer_seed),
        .state(flow_state),.sel(menu_sel),.regenerate(regenerate),.play_start(play_start),
        .progress(progress),.over_ready(over_ready));
    player_health hearts(.clk(clk),.rst(rst),.play_start(play_start),
        .playing(playing_now),.hit(player_hit),.health(health),.damage(damage));
    // Only the host spawns zombies; the Player 2 board shows the host's waves.
    wave_controller #(.SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT),.WIN_WAVE(WIN_WAVE)) waves(
        .clk(clk),.rst(rst),.play_start(play_start),.playing(playing_now),
        .map_bits(published_map),.occupied(zombies),.player_tile(player_tile),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.wave(wave),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.spawn_busy(spawn_busy),.alive(alive),
        .remaining(remaining),.wave_clear(wave_clear),.game_won(game_won));
    hud_effects_ctrl #(.TINT_SHIFT(TINT_SHIFT),
        .BLINK_SHIFT(BLINK_SHIFT)) effects_ctrl(
        .clk(clk),.rst(rst),.playing(playing_now),.damage(damage),
        .health(health),.tint(tint),.low_blink(low_blink));
    weapon_ctrl #(.FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT),
        .RELOAD_SHIFT(RELOAD_SHIFT)) weapon(
        .clk(clk),.rst(rst),.playing(playing_now),.fire(fire_request),.reload(reload_request),
        .flash(weapon_flash),.recoil(weapon_recoil),.shot_fired(shot_fired),
        .ammo(ammo),.reloading(weapon_reloading),.drop(weapon_drop),
        .state(weapon_state),.reload_phase(reload_phase));
    map_system #(.STAGE(STAGE)) core(.clk(clk),.rst(rst),.regenerate(regenerate),
        .seed_in(generator_seed),.published_map(published_map),.p1_addr(p1_addr),
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
    reg [12:0] request_index, ahead_index, row_index;
    reg [5:0] request_row;
    reg [6:0] request_x;
    reg [5:0] request_y;
    // Capture the OLED index before incrementing and converting coordinates.
    // A row is three groups of 32 pixels.
    wire [7:0] column_group = row_index[12:5] - (8'd3 * request_row);
    always @(posedge clk) begin
        if(rst) begin
            request_index<=13'd6143; ahead_index<=0; row_index<=0;
            request_row<=0; request_x<=0; request_y<=0;
        end else begin
            request_index<=sending_pixels ? pixel_index : 13'd6143;
            ahead_index<=request_index==6143 ? 13'd0 : request_index+1'b1;
            row_index<=ahead_index;
            request_row<=ahead_index[12:5] / 8'd3;
            request_x<={column_group[1:0],row_index[4:0]};
            request_y<=request_row;
        end
    end
    assign pixel_x = request_x;
    assign pixel_y = request_y;
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
                if(pixel_index==13'd6142) world_last<=world_pixel; // Tail bridge sends the final pixel.
            end
        end
    end
    // frame_begin for the other modules: one clk pulse per frame.
    reg frame_begin_prev;
    always @(posedge clk) frame_begin_prev <= rst ? 1'b0 : oled_frame_begin;
    assign frame_begin = oled_frame_begin && !frame_begin_prev;
    assign frame_idle = !sending_pixels && !oled_frame_begin;

    reg [255:0] frame_map;
    reg [7:0] frame_p1,frame_p2,frame_pos_x,frame_pos_y;
    reg [9:0] frame_angle;
    reg [15:0] frame_seed;
    reg [1:0] frame_health;
    reg [6:0] frame_wave,frame_remaining;
    reg [255:0] frame_zombies;
    reg frame_flash,frame_recoil,frame_reloading;
    reg [2:0] frame_ammo;
    reg [4:0] frame_drop;
    reg frame_ready,frame_busy,frame_mode;
    reg [2:0] frame_error;
    reg [2:0] frame_screen;
    reg frame_sel,frame_tint,frame_blink,frame_over_ready;
    reg frame_link,frame_two_player,frame_peer_in_run;
    reg [6:0] frame_peer_wave;
    reg [6:0] frame_cx; reg [5:0] frame_cy;
    reg [5:0] frame_progress;
    // Related clocks, explicitly constrained in XDC, not asynchronous CDC.
    // The supplied driver updates frame_begin on negedge; capture on posedge
    // so the next negedge samples a coherent frame and its first pixel.
    always @(posedge oled_clk) begin
        if(oled_reset) begin
            frame_map<={256{1'b1}}; frame_p1<=0; frame_p2<=0; frame_seed<=0;
            frame_pos_x<=0; frame_pos_y<=0; frame_angle<=0;
            frame_health<=3; frame_wave<=1; frame_remaining<=0; frame_zombies<=0;
            frame_flash<=0; frame_recoil<=0; frame_reloading<=0; frame_ammo<=6; frame_drop<=0;
            frame_ready<=0; frame_busy<=1; frame_mode<=0; frame_error<=0;
            frame_screen<=0; frame_sel<=0;
            frame_cx<=48; frame_cy<=40; frame_progress<=0;
            frame_tint<=0; frame_blink<=0; frame_over_ready<=0;
            frame_link<=0; frame_two_player<=0; frame_peer_in_run<=0; frame_peer_wave<=0;
        end else if(oled_frame_begin) begin
            frame_map<=published_map; frame_p1<=playing_now ? player_tile : p1_addr;
            frame_p2<=p2_addr;
            frame_pos_x<=player_pos_x; frame_pos_y<=player_pos_y; frame_angle<=player_angle;
            frame_health<=health;
            frame_wave<=wave;
            frame_remaining<=remaining; frame_zombies<=zombies;
            frame_flash<=weapon_flash; frame_recoil<=weapon_recoil;
            frame_reloading<=weapon_reloading; frame_ammo<=ammo; frame_drop<=weapon_drop;
            frame_seed<=seed; frame_ready<=ready; frame_busy<=busy;
            frame_mode<=switch_sync[1]; frame_error<=error_code;
            frame_screen<=flow_state;
            frame_sel<=menu_sel;
            frame_link<=link_up; frame_two_player<=two_player;
            frame_peer_in_run<=peer_in_run; frame_peer_wave<=peer_wave;
            frame_cx<=mouse_x; frame_cy<=mouse_y; frame_progress<=progress;
            frame_tint<=tint; frame_blink<=low_blink;
            frame_over_ready<=over_ready;
        end
    end
    // One drawing-chain definition, evaluated at the current and final pixels.
    wire [15:0] pixel_data,last_pixel_data;
    pixel_compositor #(.STAGE(STAGE),.ENABLE_2P(ENABLE_2P),.SHOW_CURSOR(SHOW_CURSOR)) compositor(
        .px(px),.py(py),.world_pixel(world_now),
        .game_state(frame_screen),.minimap_mode(frame_mode),
        .map_bits(frame_map),.p1_addr(frame_p1),.p2_addr(frame_p2),.seed(frame_seed),
        .player_x(frame_pos_x),.player_y(frame_pos_y),.player_angle(frame_angle),
        .map_ready(frame_ready),.map_busy(frame_busy),.error_code(frame_error),
        .health(frame_health),.low_blink(frame_blink),.wave(frame_wave),.remaining(frame_remaining),
        .zombie_tiles(frame_zombies),.tint(frame_tint),
        .weapon_recoil(frame_recoil),.weapon_flash(frame_flash),.weapon_reloading(frame_reloading),
        .ammo(frame_ammo),.weapon_drop(frame_drop),
        .menu_sel(frame_sel),.cursor_x(frame_cx),.cursor_y(frame_cy),
        .progress(frame_progress),.over_ready(frame_over_ready),
        .link_up(frame_link),.two_player(frame_two_player),
        .peer_wave(frame_peer_wave),.peer_in_run(frame_peer_in_run),.pixel_out(pixel_data));

    // The course OLED driver omits (95,63); the bridge sends this same composition.
    pixel_compositor #(.STAGE(STAGE),.ENABLE_2P(ENABLE_2P),.SHOW_CURSOR(SHOW_CURSOR)) last_pixel_compositor(
        .px(7'd95),.py(6'd63),.world_pixel(world_last),
        .game_state(frame_screen),.minimap_mode(frame_mode),
        .map_bits(frame_map),.p1_addr(frame_p1),.p2_addr(frame_p2),.seed(frame_seed),
        .player_x(frame_pos_x),.player_y(frame_pos_y),.player_angle(frame_angle),
        .map_ready(frame_ready),.map_busy(frame_busy),.error_code(frame_error),
        .health(frame_health),.low_blink(frame_blink),.wave(frame_wave),.remaining(frame_remaining),
        .zombie_tiles(frame_zombies),.tint(frame_tint),
        .weapon_recoil(frame_recoil),.weapon_flash(frame_flash),.weapon_reloading(frame_reloading),
        .ammo(frame_ammo),.weapon_drop(frame_drop),
        .menu_sel(frame_sel),.cursor_x(frame_cx),.cursor_y(frame_cy),
        .progress(frame_progress),.over_ready(frame_over_ready),
        .link_up(frame_link),.two_player(frame_two_player),
        .peer_wave(frame_peer_wave),.peer_in_run(frame_peer_in_run),.pixel_out(last_pixel_data));

    wire raw_cs,raw_sdin,raw_sclk,raw_dcn;
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
