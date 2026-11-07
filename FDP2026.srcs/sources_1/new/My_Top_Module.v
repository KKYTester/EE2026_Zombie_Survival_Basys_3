`timescale 1ns / 1ps
// Zombie survival, one bitstream for every board.
//
// 1 PLAYER: the board plays alone; the UART link is not needed.
// 2 PLAYERS: two linked boards play ONE shared game. Either board can start;
//   a linked board on its title screen joins automatically. The starting
//   board (leader) runs the waves and the zombies for both players: zombies
//   chase whichever player is nearer, attack either, and both players' shots
//   hit them. The other board (follower) builds the same map from the
//   leader's seed, sends its position, view angle and shots, and draws the
//   leader's zombies. Each player has three hearts; a downed player is frozen
//   and the run ends when both are down (or on victory). Players see each
//   other (blue figure in the 3D view, yellow tile on the SW0 map).
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
    parameter integer MOVE_PERIOD=3_125_000,      // 32 fractional zombie updates per second
    parameter integer CLK_FREQ=100_000_000,
    parameter integer LINK_PERIOD=2_000_000,      // status every 20 ms
    parameter integer LINK_TIMEOUT=50_000_000,    // link lost after 500 ms of silence
    parameter integer ZOMBIE_WINDUP_CYCLES=CLK_FREQ/4,
    parameter integer ZOMBIE_RECOVERY_CYCLES=(CLK_FREQ/20)*3
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

    wire [255:0] published_map, occupied, spawn_occupied;
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

    // ---------------- Two-board link ----------------
    // Status word (24 bytes, both boards): state[2:0], 2-player run[3],
    // leader[4], game token[12:5], start priority[28:13], map seed[44:29],
    // wave[51:45], hearts[53:52], position x[69:54] and y[85:70] (north-up
    // Q4.12 tiles), view angle[95:86], diagnostic shot count[99:96],
    // follower's hearts[101:100] and zombies left[108:102] from the leader.
    // Queued follower shot: valid[112], ID[120:113], X[136:121], Y[152:137],
    // angle[162:153]. Leader's last accepted event ID is in [170:163].
    // UI (leader / 1P): WAVE CLEAR pause[171], count of the follower's shots
    // that hit[173:172], kills by P1 (leader)[182:176] and P2 (follower)
    // [189:183] for the end screens; [175:174] and [191:190] spare.
    // Zombie word (29 bytes): x[95:0], y[191:96] (Q4.8, y down),
    // active mask[199:192], game token[207:200], hit points[223:208]
    // (2 bits per zombie, for the health bars).
    // [231:224] flags the zombies preparing an attack.
    wire two_player, leader;
    wire [7:0] game_token;
    wire [15:0] start_priority;
    wire [6:0] remaining;
    wire [31:0] player_x, player_y, player_angle;
    reg [3:0] shot_count;
    reg [1:0] partner_hearts;          // leader: the follower's hearts
    wire [7:0] local_render_active;
    wire [95:0] local_render_x, local_render_y;
    wire [15:0] local_render_hp;
    wire [7:0] local_render_windup;
    reg [1:0] p2_hits;                 // leader: hits by the follower's shots
    wire wave_clear_now;
    reg [6:0] kills_p1, kills_p2;      // leader / 1P: zombies killed by each player
    wire event_ready,event_valid;
    wire [7:0] event_id;
    wire [15:0] event_x,event_y;
    wire [9:0] event_angle;
    reg [7:0] partner_shot_ack;
    reg [15:0] partner_shot_x,partner_shot_y;
    reg [9:0] partner_shot_angle;
    wire combat_ready,combat_ready_p2;
    wire [191:0] local_status;
    wire [191:0] peer_status;
    wire [231:0] peer_zombies;
    wire [7:0] link_errors,link_gaps;
    wire peer_status_valid, link_up;
    wire run_leader = two_player && leader;      // runs the shared zombies
    wire follower = two_player && !leader;       // shows the leader's zombies
    peer_link #(.CLK_FREQ(CLK_FREQ),.PERIOD_CYCLES(LINK_PERIOD),
        .TIMEOUT_CYCLES(LINK_TIMEOUT),.STATUS_BYTES(24),.EXTRA_BYTES(29)) link(
        .clk(clk),.rst(reset),.uart_rx_pin(uart_rx_pin),.uart_tx_pin(uart_tx_pin),
        .local_status(local_status),
        .send_extra(run_leader && playing),
        .local_extra({local_render_windup,local_render_hp,game_token,
                      local_render_active,local_render_y,local_render_x}),
        .peer_status(peer_status),.peer_status_valid(peer_status_valid),
        .peer_extra(peer_zombies),.peer_extra_valid(),
        .link_up(link_up),.packet_error(),.frame_error(),
        .packet_error_count(link_errors),.sequence_gap_count(link_gaps));
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

    // Leader: the follower is Player 2 of the shared zombies.
    wire zombie_hit_p2;
    wire partner_in_game = run_leader && peer_in_run && partner_hearts!=2'd0;
    (* max_fanout = 32 *) reg partner_in_game_q;
    reg partner_shot;
    wire shot_session_active = follower && playing && peer_in_run;
    reg shot_session_active_q;
    always @(posedge clk) shot_session_active_q<=!reset && shot_session_active;
    assign local_status = {2'd0, kills_p2, kills_p1, 2'd0, p2_hits, wave_clear_now,
                           partner_shot_ack,event_angle,event_y,event_x,event_id,
                           event_valid && shot_session_active,
                           3'd0, remaining, partner_hearts, shot_count,
                           player_angle[9:0], player_y[15:0], player_x[15:0],
                           health, wave, active_seed, start_priority,
                           game_token, leader, two_player, game_state};
    shot_event_queue shots(.clk(clk),.reset(reset || play_start),
        .enabled(shot_session_active_q),.fire(shot_fired),
        .fire_x(player_x[15:0]),.fire_y(player_y[15:0]),.fire_angle(player_angle[9:0]),
        .acknowledged(peer_status[170:163]),.ready(event_ready),.valid(event_valid),
        .event_id(event_id),.event_x(event_x),.event_y(event_y),.event_angle(event_angle));
    // Hit marker (red crosshair). enemy_manager reports which player's shot hit.
    // Leader / 1P: its own hits flash its crosshair; hits by the follower's
    // shots are counted into the status word, and the follower flashes when
    // that count changes.
    wire shot_hit, shot_hit_player, shot_kill;
    reg [1:0] p2_hits_seen;
    reg hit_marker;
    always @(posedge clk) begin
        if(reset) begin p2_hits<=0; p2_hits_seen<=0; hit_marker<=0; end
        else begin
            if(shot_hit && shot_hit_player) p2_hits<=p2_hits+1'b1;
            p2_hits_seen<=peer_status[173:172];
            hit_marker <= follower ? (peer_in_run && peer_status[173:172]!=p2_hits_seen)
                                   : (shot_hit && !shot_hit_player);
        end
    end
    // Kill scores: counted where the shots are judged (leader / 1P), reset at
    // the start of each run, kept for the end screens; the follower shows the
    // leader's counts from the status word.
    always @(posedge clk) begin
        if(reset || play_start) begin kills_p1<=0; kills_p2<=0; end
        else if(shot_hit && shot_kill) begin
            if(shot_hit_player) begin if(kills_p2!=7'd127) kills_p2<=kills_p2+1'b1; end
            else if(kills_p1!=7'd127) kills_p1<=kills_p1+1'b1;
        end
    end
    always @(posedge clk) begin
        partner_shot<=0;
        if(reset || play_start) begin
            partner_hearts<=2'd3; partner_shot_ack<=0;
            partner_shot_x<=0; partner_shot_y<=0; partner_shot_angle<=0;
        end else begin
            if(peer_status_valid && partner_in_game && peer_status[112] &&
               peer_status[120:113]==partner_shot_ack+8'd1 && combat_ready_p2) begin
                partner_shot<=1;
                partner_shot_ack<=peer_status[120:113];
                partner_shot_x<=peer_status[136:121]; partner_shot_y<=peer_status[152:137];
                partner_shot_angle<=peer_status[162:153];
            end
            if(zombie_hit_p2 && partner_hearts!=0) partner_hearts<=partner_hearts-1'b1;
        end
    end

    // ---------------- Player ----------------
    // Map/UI: x right, y down. Renderer/controller: x east, y north.
    // Reverse rows once at this boundary. All geometry uses this same map.
    wire [255:0] world_map;
    genvar row;
    generate for(row=0;row<16;row=row+1) begin : g_map_rows
        assign world_map[row*16 +: 16] = published_map[(15-row)*16 +: 16];
    end endgenerate
    // The follower starts on the map's second spawn tile.
    wire [7:0] spawn_addr = follower ? p2_addr : p1_addr;
    wire [3:0] spawn_north = 4'd15 - spawn_addr[7:4];
    wire [31:0] spawn_x = {16'd0,spawn_addr[3:0],12'h800};
    wire [31:0] spawn_y = {16'd0,spawn_north,12'h800};
    wire [3:0] player_row = 4'd15 - player_y[15:12];
    wire [7:0] player_tile = {player_row,player_x[15:12]};
    wire game_tick;
    wire alive = health!=2'd0;   // a downed player watches until the run ends
    // Keep the game-state decode off the player controller's reset fanout.
    (* max_fanout = 32 *) reg player_reset_q=1'b1;
    always @(posedge clk) player_reset_q<=reset || !playing || play_start;
    always @(posedge clk)
        if(reset) shot_count<=0;
        else if(shot_fired) shot_count<=shot_count+1'b1;
    Player_Controller #(.USE_RUNTIME_MAP(1),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_Player_Controller (
        .clk(clk),.reset(player_reset_q),.game_tick(game_tick && playing && alive),
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
    // Zombies on screen: this board's own, or the leader's on the follower.
    wire [7:0] remote_active = peer_zombies[199:192] &
                              {8{peer_in_run && peer_zombies[207:200]==game_token}};
    // Registered (one clock late): keeps the leader flag and the UART data
    // off the long paths into the sprite renderer and the OLED frame capture.
    reg [7:0] render_active;
    reg [95:0] render_x, render_y;
    reg [15:0] render_hp;
    reg [7:0] render_windup;
    always @(posedge clk) begin
        render_active <= follower ? remote_active : local_render_active;
        render_x <= follower ? peer_zombies[95:0] : local_render_x;
        render_y <= follower ? peer_zombies[191:96] : local_render_y;
        render_hp <= follower ? peer_zombies[223:208] : local_render_hp;
        render_windup <= follower ? (peer_zombies[231:224] & remote_active) : local_render_windup;
    end
    // Killed zombies stay on screen briefly: red, tipping over (display only).
    wire [7:0] draw_active, draw_dying;
    wire [95:0] draw_x, draw_y;
    wire [15:0] draw_hp;
    wire [31:0] draw_fall;
    zombie_death_fx death_fx(.clk(clk),.rst(reset),.playing(playing),
        .active(render_active),.in_x(render_x),.in_y(render_y),.in_hp(render_hp),
        .draw_active(draw_active),.draw_x(draw_x),.draw_y(draw_y),.draw_hp(draw_hp),
        .dying(draw_dying),.fall(draw_fall));
    // Sprite slot 8 is the partner (Q8 coordinates, y down like the zombies).
    wire [8:0] sprite_active = {partner_visible, draw_active};
    wire [107:0] sprite_x = {partner_x[15:4], draw_x};
    wire [107:0] sprite_y = {12'd0 - partner_y[15:4], draw_y};
    // Give the player one clock to load the spawn before scan 0 and keep
    // map-state decoding off the enemy movement and damage paths.
    (* max_fanout = 32 *) reg map_valid_delayed=0;
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
        .hp({2'd3, draw_hp}),.dying({1'b0, draw_dying}),.fall({4'd0, draw_fall}),
        .winding_up({1'b0,render_windup}),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.wall_depth({column_depth,3'b0}),
        .background(wall_pixel),.done(sprites_ready),.pixel(world_pixel));

    // ---------------- Game core ----------------
    wire [15:0] game_led;
    game_core #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.ENABLE_2P(1),.GEN_SHIFT(GEN_SHIFT),.OVER_SHIFT(OVER_SHIFT),
        .TINT_SHIFT(TINT_SHIFT),.BLINK_SHIFT(BLINK_SHIFT),
        .SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT),
        .FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT),.RELOAD_SHIFT(RELOAD_SHIFT),
        .WIN_WAVE(WIN_WAVE),.USE_SPAWN_OCCUPANCY(1),.FRACTIONAL_ENEMIES(1),
        .USE_SHOT_BACKPRESSURE(1)) game (
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
        .teammate_alive(partner_in_game_q),
        .shot_available(follower ? (shot_session_active && event_ready) : combat_ready),
        .follow_health(peer_status[101:100]),.follow_remaining(peer_status[108:102]),
        .remaining(remaining),
        .follow_wave_clear(peer_status[171]),.wave_clear_out(wave_clear_now),
        .hit_marker(hit_marker),
        .p1_kills(follower ? peer_status[182:176] : kills_p1),
        .p2_kills(follower ? peer_status[189:183] : kills_p2),
        .partner_tile(partner_tile),.partner_visible(partner_visible),
        .two_player(two_player),.leader(leader),.game_token(game_token),.start_priority(start_priority),
        .player_tile(player_tile),
        // Minimap marker: 4.4 tiles, y down (16 - y north); angle 0 = north, clockwise.
        .player_pos_x(player_x[15:8]),.player_pos_y(8'd0 - player_y[15:8]),.player_angle(player_angle[9:0]),
        .world_pixel(world_pixel),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.frame_begin(frame_begin),.frame_idle(frame_idle),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(occupied),
        .spawn_occupied(spawn_occupied),
        .zombie_active(render_active),.zombie_x(render_x),.zombie_y(render_y),
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
    // Registered zombie controls: the leader flag only changes when a game
    // starts, so one clock of delay is harmless. max_fanout lets Vivado copy
    // these flip-flops close to the hundreds of zombie-state registers they
    // drive (the unregistered version failed timing by ~1.3 ns).
    (* max_fanout = 32 *) reg enemy_clear_q;
    (* max_fanout = 32 *) reg enemy_run_q;
    // Same for the player status inputs, which depend on the 2-player flags.
    (* max_fanout = 32 *) reg alive_q;
    reg partner_shot_q;
    always @(posedge clk) begin
        enemy_clear_q <= enemy_clear || follower;
        enemy_run_q <= enemy_playing && !follower;
        alive_q <= alive;
        partner_in_game_q <= partner_in_game;
        partner_shot_q <= partner_shot && partner_in_game;
    end
    // Zombies (1 PLAYER, or the leader of a shared run): Player 2 is the follower.
    enemy_manager #(.USE_CAMERA_RAY(1),.USE_PLAYER_POSITIONS(1),.TWO_PLAYERS(1),.USE_AWARENESS(1),
        .USE_WANDER(1),.USE_PATROL(1),
        .ATTACK_WINDUP_CYCLES(ZOMBIE_WINDUP_CYCLES),
        .ATTACK_RECOVERY_CYCLES(ZOMBIE_RECOVERY_CYCLES)) enemies(
        .clk(clk),.rst(reset),.clear(enemy_clear_q),.playing(enemy_run_q),
        .map_ready(map_valid_delayed),.map_bits(published_map),.wander_seed(active_seed),
        .patrol_tile1(p1_addr),.patrol_tile2(p2_addr),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.spawn_ack(spawn_ack),
        .spawn_busy(spawn_busy),.enemy_defeated(enemy_defeated),.occupied(occupied),
        .debug_defeat(test_kill),.move_tick(move_tick),.player_tile(player_tile),
        .player_pos_x({20'd0,player_x[15:4]}),.player_pos_y({20'd0,camera_south}),
        .player2_pos_x({20'd0,partner_x[15:4]}),.player2_pos_y({20'd0,12'd0-partner_y[15:4]}),
        .shot_fired(shot_fired),.aim(2'd0),.camera_x(player_x),.camera_y(player_y),
        .camera_angle(player_angle[9:0]),
        .camera2_x({16'd0,partner_shot_x}),.camera2_y({16'd0,partner_shot_y}),.camera2_angle(partner_shot_angle),
        .shot_hit(shot_hit),.player_hit(zombie_hit),
        .player_active(alive_q),.player2_active(partner_in_game_q),.player2_tile(partner_tile),
        .shot_fired_p2(partner_shot_q),.aim_p2(2'd0),.shot_ready(combat_ready),.shot_ready_p2(combat_ready_p2),
        .shot_hit_player(shot_hit_player),.shot_kill(shot_kill),.player_hit_p2(zombie_hit_p2),.active(local_render_active),
        .render_x(local_render_x),.render_y(local_render_y),.render_hp(local_render_hp),.spawn_occupied(spawn_occupied),.read_id(3'd0),
        .render_windup(local_render_windup),
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
    // LED10 packet/frame error, LED9 missed status sequence, LED3-1 map error
    // code, LED0 map ready.
    wire [2:0] peer_hearts = !same_game ? 3'b000 :
                             peer_health==2'd3 ? 3'b111 :
                             peer_health==2'd2 ? 3'b011 :
                             peer_health==2'd1 ? 3'b001 : 3'b000;
    assign led = {link_up, peer_hearts, game_led[15], |link_errors, |link_gaps, 5'd0, error_code, map_ready};
endmodule
