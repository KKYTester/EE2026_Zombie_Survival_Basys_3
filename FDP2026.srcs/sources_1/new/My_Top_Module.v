`timescale 1ns / 1ps
// Zombie survival, one bitstream for every board.
//
// 1 PLAYER: the board plays alone; the UART link is not needed.
// 2 PLAYERS: two linked boards each play their OWN complete game (own
//   zombies, waves, hearts and controls) on the SAME map. Either board can
//   start; a linked board on its title screen joins automatically. The link
//   carries each board's status and position, so each player sees the other
//   player walking around (a blue figure in the 3D view, a yellow tile on the
//   SW0 map) and their progress: seven-segment = own wave | partner wave,
//   LED14-12 = partner hearts, end screens = partner's wave.
//
// Controls: mouse turns, BTN-U/D/L/R move, left-click or BTN-C fires,
// right-click reloads, BTN-D toggles 1P/2P on the title, SW0 shows the map,
// SW15 resets. Wiring: JC1 (TX) of each board to JC2 (RX) of the other, GND to GND.
module My_Top_Module #(
    parameter DEBOUNCE_CYCLES=1000000,
    parameter GEN_SHIFT=26, parameter OVER_SHIFT=27,
    parameter TINT_SHIFT=25, parameter BLINK_SHIFT=24,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23, parameter RELOAD_SHIFT=25,
    parameter WIN_WAVE=10,
    parameter integer MOVE_PERIOD=50_000_000,
    parameter integer CLK_FREQ=100_000_000,
    parameter integer LINK_PERIOD=2_000_000,      // status every 20 ms
    parameter integer LINK_TIMEOUT=50_000_000     // link lost after 500 ms of silence
)(
    input wire clk,
    input wire btnC, btnU, btnL, btnR, btnD,
    input wire sw0, sw13, sw14, sw15,
    inout wire ps2_clk, ps2_data,
    output wire [15:0] led,
    output wire [7:0] JB,
    output wire [6:0] seg, output wire dp, output wire [3:0] an,
    output wire uart_tx_pin,
    input wire uart_rx_pin
);
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync=2'b11;
    wire reset=reset_sync[1];
    always @(posedge clk) reset_sync <= {reset_sync[0],sw15};

    // ---------------- Mouse ----------------
    wire signed [8:0] mouse_x_delta, mouse_y_delta;
    wire mouse_left, mouse_middle, mouse_right, mouse_event;
    wire [2:0] game_state;
    wire playing = game_state==3'd3;
    wire [6:0] mouse_x;
    wire [5:0] mouse_y;
    Mouse_Control_Delta u_Mouse_Control_Delta (
        .clk(clk), .rst(reset), .x_delta(mouse_x_delta), .y_delta(mouse_y_delta),
        .left(mouse_left), .middle(mouse_middle), .right(mouse_right),
        .new_event(mouse_event), .ps2_clk(ps2_clk), .ps2_data(ps2_data)
    );
    // Keep the menu cursor where it was during gameplay; X controls the view.
    Mouse_Pointer pointer(.clk(clk),.reset(reset),
        .mouse_event(mouse_event && !playing),.x_delta(mouse_x_delta),.y_delta(mouse_y_delta),
        .x(mouse_x),.y(mouse_y));
    // BTN-D toggles 1P/2P on the title screen (it moves backwards in play).
    wire press_d;
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) title_toggle(
        .clk(clk),.rst(reset),.button(btnD),.pressed(press_d));

    wire [255:0] published_map, occupied;
    wire [7:0] p1_addr, p2_addr, spawn_tile;
    wire [15:0] active_seed;
    wire [6:0] wave;
    wire [1:0] health;
    wire [2:0] error_code;
    wire map_ready, map_busy, play_start, frame_begin, frame_idle;
    wire spawn_req, spawn_ack, enemy_defeated, enemies_clear, shot_fired;
    wire spawn_busy, zombie_hit;
    reg enemy_playing, enemy_clear;
    always @(posedge clk) begin
        if(reset) begin enemy_playing<=0; enemy_clear<=1; end
        else begin enemy_playing<=playing; enemy_clear<=enemies_clear; end
    end
    wire test_kill, test_hit;
    switch_toggle #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) kill_switch(
        .clk(clk),.rst(reset),.switch_in(sw14),.flipped(test_kill));
    switch_toggle #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) hit_switch(
        .clk(clk),.rst(reset),.switch_in(sw13),.flipped(test_hit));

    // ---------------- Two-board status link ----------------
    // Status word (14 bytes): state[2:0], 2-player run[3], leader[4],
    // game token[12:5], start priority[28:13], map seed[44:29], wave[51:45],
    // hearts[53:52], position x[69:54] and y[85:70] (north-up Q4.12 tiles),
    // view angle[95:86]. The leader's seed is final once it is PLAYING.
    wire two_player, leader;
    wire [7:0] game_token;
    wire [15:0] start_priority;
    wire [31:0] player_x, player_y, player_angle;
    wire [111:0] local_status = {16'd0, player_angle[9:0], player_y[15:0], player_x[15:0],
                                 health, wave, active_seed, start_priority,
                                 game_token, leader, two_player, game_state};
    wire [111:0] peer_status;
    wire link_up;
    peer_link #(.CLK_FREQ(CLK_FREQ),.PERIOD_CYCLES(LINK_PERIOD),
        .TIMEOUT_CYCLES(LINK_TIMEOUT),.STATUS_BYTES(14)) link(
        .clk(clk),.rst(reset),.uart_rx_pin(uart_rx_pin),.uart_tx_pin(uart_tx_pin),
        .local_status(local_status),.peer_status(peer_status),.peer_status_valid(),
        .link_up(link_up),.packet_error(),.frame_error());
    wire [2:0] peer_state = peer_status[2:0];
    wire peer_2p = peer_status[3];
    wire peer_leader = peer_status[4];
    wire [7:0] peer_token = peer_status[12:5];
    wire [6:0] peer_wave = peer_status[51:45];
    wire [1:0] peer_health = peer_status[53:52];
    // The partner is in the same 2-player game as this board.
    wire same_game = link_up && two_player && peer_2p && peer_token==game_token &&
                     peer_state!=3'd0 && game_state!=3'd0;
    wire peer_in_run = same_game && peer_state==3'd3;
    // The partner walks the same map: show it while both boards are playing.
    wire partner_visible = peer_in_run && playing;
    wire [15:0] partner_x = peer_status[69:54];
    wire [15:0] partner_y = peer_status[85:70];
    wire [7:0] partner_tile = {4'd15 - partner_y[15:12], partner_x[15:12]};

    // ---------------- Player ----------------
    // Map/UI: x right, y down. Renderer/controller: x east, y north.
    // Reverse rows once at this boundary. All geometry uses this same map.
    wire [255:0] world_map;
    genvar row;
    generate for(row=0;row<16;row=row+1) begin : g_map_rows
        assign world_map[row*16 +: 16] = published_map[(15-row)*16 +: 16];
    end endgenerate
    wire [3:0] spawn_north = 4'd15 - p1_addr[7:4];
    wire [31:0] spawn_x = {16'd0,p1_addr[3:0],12'h800};
    wire [31:0] spawn_y = {16'd0,spawn_north,12'h800};
    wire [3:0] player_row = 4'd15 - player_y[15:12];
    wire [7:0] player_tile = {player_row,player_x[15:12]};
    wire game_tick;
    Player_Controller #(.USE_RUNTIME_MAP(1),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_Player_Controller (
        .clk(clk),.reset(reset || !playing || play_start),.game_tick(game_tick && playing),
        .map_bits(world_map),.spawn_x(spawn_x),.spawn_y(spawn_y),
        .btnU(btnU),.btnL(btnL),.btnR(btnR),.btnD(btnD),
        .mouse_x_delta(mouse_x_delta),.mouse_event(mouse_event && playing),
        .x_coord(player_x),.y_coord(player_y),.theta(player_angle)
    );

    // ---------------- Renderer ----------------
    wire [6:0] pixel_x;
    wire [5:0] pixel_y;
    // game_core supplies look-ahead coordinates, including the tail pixel.
    wire [15:0] world_pixel;
    wire [15:0] wall_pixel;
    wire [9:0] column_depth;
    wire scene_start, display_bank, scene_valid, sprites_ready;
    wire [7:0] render_active;
    wire [95:0] render_x, render_y;
    // Sprite slot 8 is the partner (Q8 coordinates, y down like the zombies).
    wire [8:0] sprite_active = {partner_visible, render_active};
    wire [107:0] sprite_x = {partner_x[15:4], render_x};
    wire [107:0] sprite_y = {12'd0 - partner_y[15:4], render_y};
    // Give the player one clock to load a newly published spawn before scan 0.
    reg map_valid_delayed=0;
    always @(posedge clk) map_valid_delayed <= !reset && map_ready && !map_busy;
    // Completed banks swap only during the display's idle window. The bank
    // and map/player snapshot stay immutable throughout transmission.
    wire renderer_reset = reset || !map_ready || map_busy || !map_valid_delayed;
    Map_Renderer #(.USE_RUNTIME_MAP(1),.USE_PIXEL_COORDS(1),.USE_ENEMY_OVERLAY(1)) u_Map_Renderer (
        .clk(clk),.reset(renderer_reset),.map_bits(world_map),
        .x_coord(player_x),.y_coord(player_y),.theta(player_angle),.game_tick(game_tick),
        .display_clk(clk),.frame_begin(frame_idle),.pixel_index(13'd0),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .pixel_data(wall_pixel),.column_depth(column_depth),
        .overlay_ready(sprites_ready),.scene_start(scene_start),
        .display_bank(display_bank),.scene_valid(scene_valid)
    );
    // Q12 north-up player coordinates become Q8 south-down enemy coordinates.
    wire [11:0] camera_south = 12'd0-player_y[15:4];
    zombie_renderer #(.USE_CAMERA_POSE(1),.FOCAL_X(83),.FOCAL_Y(64),
        .SLOTS(9),.HAS_ALLY(1)) sprites(
        .clk(clk),.reset(renderer_reset),.prepare(scene_start),
        .display_bank(display_bank),.scene_valid(scene_valid),
        .camera_x(player_x[15:4]),.camera_y(camera_south),.camera_angle(player_angle[9:0]),
        .facing(2'd0),.active(sprite_active),.zombie_x(sprite_x),.zombie_y(sprite_y),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.wall_depth({column_depth,3'b0}),
        .background(wall_pixel),.done(sprites_ready),.pixel(world_pixel));

    // ---------------- Game core ----------------
    wire [15:0] game_led;
    game_core #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.ENABLE_2P(1),.GEN_SHIFT(GEN_SHIFT),.OVER_SHIFT(OVER_SHIFT),
        .TINT_SHIFT(TINT_SHIFT),.BLINK_SHIFT(BLINK_SHIFT),
        .SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT),
        .FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT),.RELOAD_SHIFT(RELOAD_SHIFT),
        .WIN_WAVE(WIN_WAVE)) game (
        .clk(clk),.rst(reset),.btn_c(btnC),.btn_d(press_d),.sw_map(sw0),
        .oled_jb(JB),.seg(),.dp(),.an(),.led(game_led),
        .mouse_x(mouse_x),.mouse_y(mouse_y),.mouse_left(mouse_left),
        .mouse_right(mouse_right),.mouse_event(mouse_event),
        .published_map(published_map),.map_ready(map_ready),.map_busy(map_busy),
        .p1_addr(p1_addr),.p2_addr(p2_addr),.active_seed(active_seed),.error_code(error_code),
        .game_state(game_state),.play_start(play_start),.wave(wave),.health(health),
        .selected_2p(),
        .link_up(link_up),.peer_state(peer_state),.peer_2p(peer_2p),.peer_leader(peer_leader),
        .peer_token(peer_token),.peer_priority(peer_status[28:13]),.peer_seed(peer_status[44:29]),
        .peer_wave(peer_wave),.peer_in_run(peer_in_run),
        .partner_tile(partner_tile),.partner_visible(partner_visible),
        .two_player(two_player),.leader(leader),.game_token(game_token),.start_priority(start_priority),
        .player_tile(player_tile),
        // Minimap marker: 4.4 tiles, y down (16 - y north); angle 0 = north, clockwise.
        .player_pos_x(player_x[15:8]),.player_pos_y(8'd0 - player_y[15:8]),.player_angle(player_angle[9:0]),
        .world_pixel(world_pixel),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.frame_begin(frame_begin),.frame_idle(frame_idle),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(occupied),
        .player_hit(zombie_hit || test_hit),.spawn_req(spawn_req),.spawn_tile(spawn_tile),.spawn_busy(spawn_busy),
        .enemies_clear(enemies_clear),.shot_fired(shot_fired)
    );

    // ---------------- Zombies (this board's own) ----------------
    localparam integer MOVE_BITS = MOVE_PERIOD>1 ? $clog2(MOVE_PERIOD) : 1;
    reg [MOVE_BITS-1:0] move_counter;
    wire move_tick = enemy_playing && move_counter==MOVE_PERIOD-1;
    always @(posedge clk) begin
        if(reset || enemy_clear || move_tick) move_counter<=0;
        else move_counter<=move_counter+1'b1;
    end
    enemy_manager #(.USE_CAMERA_RAY(1)) enemies(
        .clk(clk),.rst(reset),.clear(enemy_clear),.playing(enemy_playing),
        .map_ready(map_ready && !map_busy),.map_bits(published_map),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.spawn_ack(spawn_ack),
        .spawn_busy(spawn_busy),.enemy_defeated(enemy_defeated),.occupied(occupied),
        .debug_defeat(test_kill),.move_tick(move_tick),.player_tile(player_tile),
        .shot_fired(shot_fired),.aim(2'd0),.camera_x(player_x),.camera_y(player_y),
        .camera_angle(player_angle[9:0]),
        .shot_hit(),.player_hit(zombie_hit),
        .player_active(1'b1),.player2_active(1'b0),.player2_tile(8'd0),
        .shot_fired_p2(1'b0),.aim_p2(2'd0),.shot_ready(),.shot_ready_p2(),
        .shot_hit_player(),.player_hit_p2(),.active(render_active),
        .render_x(render_x),.render_y(render_y),.read_id(3'd0),
        .read_active(),.read_x(),.read_y(),.read_hp(),.read_type(),.read_state(),.read_cooldown());

    // ---------------- Board displays ----------------
    // Seven-segment: map seed, or "own wave | partner wave" in a 2-player game.
    wire [3:0] own_tens, own_ones, peer_tens, peer_ones;
    wave_digits own_digits(.value(wave),.tens(own_tens),.ones(own_ones));
    wave_digits peer_digits(.value(peer_wave),.tens(peer_tens),.ones(peer_ones));
    wire [15:0] seg_value = same_game ? {own_tens,own_ones,peer_tens,peer_ones} : active_seed;
    seven_seg_hex board_display(.clk(clk),.rst(reset),.value(seg_value),
        .seg(seg),.dp(dp),.an(an));
    // LED15 link up, LED14-12 partner hearts (2-player game), LED11 map busy,
    // LED3-1 map error code, LED0 map ready.
    wire [2:0] peer_hearts = !same_game ? 3'b000 :
                             peer_health==2'd3 ? 3'b111 :
                             peer_health==2'd2 ? 3'b011 :
                             peer_health==2'd1 ? 3'b001 : 3'b000;
    assign led = {link_up, peer_hearts, game_led[15], 7'd0, error_code, map_ready};
endmodule
