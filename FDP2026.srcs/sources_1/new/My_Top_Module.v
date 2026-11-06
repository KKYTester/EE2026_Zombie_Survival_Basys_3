`timescale 1ns / 1ps
// Zombie survival, one bitstream for both boards.
//
// SW1 down = HOST board (Player 1). The title menu offers 1 PLAYER and
//   2 PLAYERS. 1 PLAYER needs nothing else: the UART link is ignored.
//   2 PLAYERS can start once the other board is linked; the host then runs
//   the waves and all zombies for both players.
// SW1 up = PLAYER 2 board. It has no menu: it follows the host's game state,
//   generates the same map from the host's seed and plays its own first-person
//   view with its own mouse and buttons. It sends its pose and shots to the
//   host and shows the host's zombies, wave and its own hearts.
//
// Controls on both boards: mouse turns, BTN-U/D/L/R move, left-click or
// BTN-C fires, right-click reloads, SW0 shows the map, SW15 resets.
// Wiring: JC1 (TX) of each board to JC2 (RX) of the other, plus GND to GND.
module My_Top_Module #(
    parameter DEBOUNCE_CYCLES=1000000,
    parameter GEN_SHIFT=26, parameter OVER_SHIFT=27,
    parameter TINT_SHIFT=25, parameter BLINK_SHIFT=24,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23, parameter RELOAD_SHIFT=25,
    parameter WIN_WAVE=10,
    parameter integer MOVE_PERIOD=50_000_000,
    parameter integer CLK_FREQ=100_000_000,
    parameter integer LINK_INPUT_PERIOD=2_000_000,   // P2 -> host every 20 ms
    parameter integer LINK_STATE_PERIOD=2_000_000,   // host -> P2 every 20 ms
    parameter integer LINK_HELLO_PERIOD=25_000_000,
    parameter integer LINK_TIMEOUT=50_000_000
)(
    input wire clk,
    input wire btnC, btnU, btnL, btnR, btnD,
    input wire sw0, sw1, sw13, sw14, sw15,
    inout wire ps2_clk, ps2_data,
    output wire [15:0] led,
    output wire [7:0] JB,
    output wire [6:0] seg, output wire dp, output wire [3:0] an,
    output wire uart_tx_pin,
    input wire uart_rx_pin
);
    // ---------------- Reset and board role ----------------
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync=2'b11;
    (* ASYNC_REG="TRUE" *) reg [1:0] role_sync=2'b00;
    reg role_prev=0, reset=1;
    always @(posedge clk) begin
        reset_sync <= {reset_sync[0],sw15};
        role_sync <= {role_sync[0],sw1};
        role_prev <= role_sync[1];
        // Changing the role restarts the board in its new role.
        reset <= reset_sync[1] || role_sync[1]!=role_prev;
    end
    wire client_role = role_prev;          // 1 = Player 2 board
    wire host_role = !client_role;

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

    // ---------------- Game core outputs ----------------
    wire [255:0] published_map, enemy_occupied;
    wire [7:0] p1_addr, p2_addr, spawn_tile;
    wire [15:0] active_seed;
    wire [6:0] wave, remaining;
    wire [1:0] health;
    wire selected_2p;
    wire map_ready, map_busy, play_start, frame_begin, frame_idle;
    wire spawn_req, spawn_ack, enemy_defeated, enemies_clear, shot_fired;
    wire spawn_busy, zombie_hit, zombie_hit_p2;
    wire [15:0] game_led;
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

    // ---------------- Local player (both roles) ----------------
    // Map/UI: x right, y down. Renderer/controller: x east, y north.
    // Reverse rows once at this boundary. All geometry uses this same map.
    wire [255:0] world_map;
    genvar row;
    generate for(row=0;row<16;row=row+1) begin : g_map_rows
        assign world_map[row*16 +: 16] = published_map[(15-row)*16 +: 16];
    end endgenerate
    // Both boards build the same map, so each spawns on its own player's tile.
    wire [7:0] spawn_addr = client_role ? p2_addr : p1_addr;
    wire [3:0] spawn_north = 4'd15 - spawn_addr[7:4];
    wire [31:0] spawn_x = {16'd0,spawn_addr[3:0],12'h800};
    wire [31:0] spawn_y = {16'd0,spawn_north,12'h800};
    wire [31:0] player_x, player_y, player_angle;
    wire [3:0] player_row = 4'd15 - player_y[15:12];
    wire [7:0] player_tile = {player_row,player_x[15:12]};
    wire alive = health!=2'd0;   // a dead player watches until the run ends
    wire game_tick;
    Player_Controller #(.USE_RUNTIME_MAP(1),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_Player_Controller (
        .clk(clk),.reset(reset || !playing || play_start),.game_tick(game_tick && playing && alive),
        .map_bits(world_map),.spawn_x(spawn_x),.spawn_y(spawn_y),
        .btnU(btnU),.btnL(btnL),.btnR(btnR),.btnD(btnD),
        .mouse_x_delta(mouse_x_delta),.mouse_event(mouse_event && playing),
        .x_coord(player_x),.y_coord(player_y),.theta(player_angle)
    );

    // ---------------- UART link ----------------
    // Player 2 -> host (7 bytes): x[15:0], y[15:0] (north-up Q4.12),
    // angle[41:32], shot counter[45:42], playing[46].
    // Host -> Player 2 snapshot: state[2:0], 2P run[3], wave[10:4],
    // zombies left[17:11], P1 hearts[19:18], P2 hearts[21:20], map seed[37:22],
    // P1 tile[45:38]. ZOMBIES packet: active mask[71:64], eight {y,x} tiles.
    reg [3:0] local_shot_count;
    always @(posedge clk)
        if(reset) local_shot_count<=0;
        else if(shot_fired) local_shot_count<=local_shot_count+1'b1;
    wire [55:0] client_input = {9'd0, playing, local_shot_count, player_angle[9:0],
                                player_y[15:0], player_x[15:0]};
    wire [55:0] p2_input;
    wire p2_input_valid, client_snapshot_valid, client_zombies_valid, link_up;
    wire [119:0] client_snapshot;
    wire [71:0] client_zombies;
    reg [1:0] p2_health;
    wire coop = host_role && selected_2p && link_up;
    wire [7:0] local_render_active;
    wire [95:0] local_render_x, local_render_y;
    wire [63:0] host_zombie_tiles;
    genvar slot;
    generate for(slot=0;slot<8;slot=slot+1) begin : g_zombie_tiles
        assign host_zombie_tiles[slot*8 +: 8] = {local_render_y[slot*12+8 +: 4],
                                                 local_render_x[slot*12+8 +: 4]};
    end endgenerate
    wire [119:0] host_snapshot = {74'd0, player_tile, active_seed, p2_health, health,
                                  remaining, wave, coop, game_state};
    multiplayer_link #(.CLK_FREQ(CLK_FREQ),.INPUT_PERIOD_CYCLES(LINK_INPUT_PERIOD),
        .STATE_PERIOD_CYCLES(LINK_STATE_PERIOD),.HELLO_PERIOD_CYCLES(LINK_HELLO_PERIOD),
        .TIMEOUT_CYCLES(LINK_TIMEOUT),.INPUT_BYTES(7)) link(
        .clk(clk),.rst(reset),.host_mode(host_role),
        .uart_rx_pin(uart_rx_pin),.uart_tx_pin(uart_tx_pin),
        .local_controls(client_input),.host_snapshot(host_snapshot),
        .host_zombies({local_render_active,host_zombie_tiles}),
        .remote_controls(p2_input),.remote_controls_valid(p2_input_valid),
        .client_snapshot(client_snapshot),.client_snapshot_valid(client_snapshot_valid),
        .client_zombies(client_zombies),.client_zombies_valid(client_zombies_valid),
        .link_up(link_up),.packet_error(),.frame_error());

    // ---------------- Host: Player 2 as seen by the host ----------------
    reg [15:0] p2_x, p2_y;
    reg [9:0] p2_angle;
    reg [3:0] p2_shot_count;
    reg p2_synced, p2_shot;
    wire p2_packet = host_role && p2_input_valid && p2_input[46];
    wire [7:0] p2_tile = {4'd15 - p2_y[15:12], p2_x[15:12]};
    always @(posedge clk) begin
        p2_shot<=0;
        if(reset || play_start) begin
            p2_x<={p2_addr[3:0],12'h800};
            p2_y<={4'd15-p2_addr[7:4],12'h800};
            p2_angle<=10'd128; p2_shot_count<=0; p2_synced<=0; p2_health<=2'd3;
        end else begin
            if(p2_packet) begin
                p2_x<=p2_input[15:0]; p2_y<=p2_input[31:16]; p2_angle<=p2_input[41:32];
                p2_shot_count<=p2_input[45:42]; p2_synced<=1;
                // A changed counter is a new shot (shots are far apart in time).
                if(p2_synced && p2_input[45:42]!=p2_shot_count) p2_shot<=1;
            end
            if(zombie_hit_p2 && p2_health!=0) p2_health<=p2_health-1'b1;
        end
    end
    wire p2_in_game = coop && playing && p2_synced && p2_health!=0;

    // ---------------- Player 2 board: the host's state ----------------
    wire host_runs_2p = link_up && client_snapshot[3];
    wire [2:0] follow_state = (client_role && host_runs_2p) ? client_snapshot[2:0] : 3'd0;
    wire [7:0] host_p1_tile = client_snapshot[45:38];
    wire [7:0] remote_active = client_zombies[71:64] & {8{host_runs_2p}};
    wire [95:0] remote_render_x, remote_render_y;
    generate for(slot=0;slot<8;slot=slot+1) begin : g_remote_zombies
        assign remote_render_x[slot*12 +: 12] = {client_zombies[slot*8 +: 4],8'h80};
        assign remote_render_y[slot*12 +: 12] = {client_zombies[slot*8+4 +: 4],8'h80};
    end endgenerate
    // Minimap zombie dots on the Player 2 board.
    reg [255:0] remote_occupied, remote_decode;
    integer zombie_i;
    always @* begin
        remote_decode=0;
        for(zombie_i=0;zombie_i<8;zombie_i=zombie_i+1)
            if(remote_active[zombie_i])
                remote_decode[client_zombies[zombie_i*8 +: 8]]=1'b1;
    end
    always @(posedge clk)
        remote_occupied <= (reset || host_role) ? 256'd0 : remote_decode;

    // ---------------- Renderer ----------------
    wire [6:0] pixel_x;
    wire [5:0] pixel_y;
    // game_core supplies look-ahead coordinates, including the tail pixel.
    wire [15:0] world_pixel;
    wire [15:0] wall_pixel;
    wire [9:0] column_depth;
    wire scene_start, display_bank, scene_valid, sprites_ready;
    wire [7:0] render_active = client_role ? remote_active : local_render_active;
    wire [95:0] render_x = client_role ? remote_render_x : local_render_x;
    wire [95:0] render_y = client_role ? remote_render_y : local_render_y;
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
    zombie_renderer #(.USE_CAMERA_POSE(1),.FOCAL_X(83),.FOCAL_Y(64)) sprites(
        .clk(clk),.reset(renderer_reset),.prepare(scene_start),
        .display_bank(display_bank),.scene_valid(scene_valid),
        .camera_x(player_x[15:4]),.camera_y(camera_south),.camera_angle(player_angle[9:0]),
        .facing(2'd0),.active(render_active),.zombie_x(render_x),.zombie_y(render_y),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.wall_depth({column_depth,3'b0}),
        .background(wall_pixel),.done(sprites_ready),.pixel(world_pixel));

    // ---------------- Game core ----------------
    game_core #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.ENABLE_2P(1),.GEN_SHIFT(GEN_SHIFT),.OVER_SHIFT(OVER_SHIFT),
        .TINT_SHIFT(TINT_SHIFT),.BLINK_SHIFT(BLINK_SHIFT),
        .SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT),
        .FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT),.RELOAD_SHIFT(RELOAD_SHIFT),
        .WIN_WAVE(WIN_WAVE)) game (
        .clk(clk),.rst(reset),.btn_c(btnC),.btn_d(press_d && !client_role),.sw_map(sw0),
        .oled_jb(JB),.seg(seg),.dp(dp),.an(an),.led(game_led),
        .mouse_x(mouse_x),.mouse_y(mouse_y),.mouse_left(mouse_left),
        .mouse_right(mouse_right),.mouse_event(mouse_event),
        .published_map(published_map),.map_ready(map_ready),.map_busy(map_busy),
        .p1_addr(p1_addr),.p2_addr(p2_addr),.active_seed(active_seed),.error_code(),
        .game_state(game_state),.play_start(play_start),.wave(wave),.health(health),
        .selected_2p(selected_2p),.remaining(remaining),
        .allow_2p(host_role && link_up),
        .teammate_alive(coop && p2_health!=0),
        .follow(client_role),.link_up(link_up),
        .follow_state(follow_state),.follow_seed(client_snapshot[37:22]),
        .follow_wave(client_snapshot[10:4]),.follow_remaining(client_snapshot[17:11]),
        .follow_health(client_snapshot[21:20]),
        .player_tile(player_tile),
        // Minimap marker: 4.4 tiles, y down (16 - y north); angle 0 = north, clockwise.
        .player_pos_x(player_x[15:8]),.player_pos_y(8'd0 - player_y[15:8]),.player_angle(player_angle[9:0]),
        .player2_tile(client_role ? host_p1_tile : p2_tile),
        .world_pixel(world_pixel),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.frame_begin(frame_begin),.frame_idle(frame_idle),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),
        .occupied(enemy_occupied | remote_occupied),
        .player_hit(zombie_hit || test_hit),.spawn_req(spawn_req),.spawn_tile(spawn_tile),.spawn_busy(spawn_busy),
        .enemies_clear(enemies_clear),.shot_fired(shot_fired)
    );

    // ---------------- Zombies (host only) ----------------
    localparam integer MOVE_BITS = MOVE_PERIOD>1 ? $clog2(MOVE_PERIOD) : 1;
    reg [MOVE_BITS-1:0] move_counter;
    wire move_tick = enemy_playing && move_counter==MOVE_PERIOD-1;
    always @(posedge clk) begin
        if(reset || enemy_clear || move_tick) move_counter<=0;
        else move_counter<=move_counter+1'b1;
    end
    enemy_manager #(.USE_CAMERA_RAY(1),.TWO_PLAYERS(1)) enemies(
        .clk(clk),.rst(reset),.clear(enemy_clear || client_role),.playing(enemy_playing && host_role),
        .map_ready(map_ready && !map_busy),.map_bits(published_map),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.spawn_ack(spawn_ack),
        .spawn_busy(spawn_busy),.enemy_defeated(enemy_defeated),.occupied(enemy_occupied),
        .debug_defeat(test_kill),.move_tick(move_tick),.player_tile(player_tile),
        .shot_fired(shot_fired),.aim(2'd0),.camera_x(player_x),.camera_y(player_y),
        .camera_angle(player_angle[9:0]),
        .camera2_x({16'd0,p2_x}),.camera2_y({16'd0,p2_y}),.camera2_angle(p2_angle),
        .shot_hit(),.player_hit(zombie_hit),
        .player_active(alive),.player2_active(p2_in_game),.player2_tile(p2_tile),
        .shot_fired_p2(p2_shot && p2_in_game),.aim_p2(2'd0),.shot_ready(),.shot_ready_p2(),
        .shot_hit_player(),.player_hit_p2(zombie_hit_p2),.active(local_render_active),
        .render_x(local_render_x),.render_y(local_render_y),.read_id(3'd0),
        .read_active(),.read_x(),.read_y(),.read_hp(),.read_type(),.read_state(),.read_cooldown());

    // LED15 map busy, LED14 link up, LED13 Player 2 board, LED12 2-player run,
    // LED3:1 map error code, LED0 map ready.
    assign led = {game_led[15], link_up, client_role, coop && playing, game_led[11:0]};
endmodule
