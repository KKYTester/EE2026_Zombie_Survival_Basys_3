`timescale 1ns / 1ps
// Two-board zombie game. SW3 high selects the host; SW3 low selects the client.
// On the client, SW[7:4] moves Player 2, SW[2:1] aims, btnC fires, and btnL reloads.
// The host uses the same local controls for Player 1; client controls reach P2 over UART.
module enemy_test_top #(parameter STAGE=3, parameter DEBOUNCE_CYCLES=1000000,
    parameter USE_MOUSE=0, parameter ENABLE_2P=1,
    parameter GEN_SHIFT=26, parameter OVER_SHIFT=27,
    parameter TINT_SHIFT=25, parameter BLINK_SHIFT=24,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23, parameter RELOAD_SHIFT=25,
    parameter WIN_WAVE=10, parameter WORLD_PATTERN=0, parameter WORLD_LATENCY=0,
    parameter integer MOVE_PERIOD=50_000_000,
    parameter integer PLAYER_MOVE_PERIOD=10_000_000,
    parameter integer ATTACK_COOLDOWN_CYCLES=100_000_000)(
    input wire clk, input wire sw0, input wire sw1, sw2, sw3, sw4, sw5, sw6, sw7,
    input wire btnC, input wire btnU,
    input wire btnL, input wire btnR, input wire btnD,
    inout wire PS2Clk, inout wire PS2Data,
    output wire [15:0] led, output wire [7:0] JB,
    output wire [6:0] seg, output wire dp, output wire [3:0] an,
    output wire uart_tx_pin, input wire uart_rx_pin);
    // ASSUMPTION: EE2026 Pmod OLEDrgb on JB, as in the supplied lab project.
    // FPGA power-up initialisation; all functional resets below are synchronous.
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync=2'b11;
    wire rst=reset_sync[1];
    always @(posedge clk) reset_sync<={reset_sync[0],btnU};

    (* ASYNC_REG="TRUE" *) reg [1:0] role_sync=0;
    (* ASYNC_REG="TRUE" *) reg [3:0] move_meta=0, move_sync=0;
    (* ASYNC_REG="TRUE" *) reg fire_meta=0, fire_sync=0, reload_meta=0, reload_sync=0;
    always @(posedge clk) begin
        role_sync <= {role_sync[0],sw3};
        move_meta <= {sw7,sw6,sw5,sw4};
        move_sync <= move_meta;
        fire_meta <= btnC; fire_sync <= fire_meta;
        reload_meta <= btnL; reload_sync <= reload_meta;
    end
    wire host_mode = role_sync[1];

    // ---------------- Mouse (Member 1 will own this) ----------------
    // Simulation hook: with USE_MOUSE=0 a testbench drives these registers.
    reg [6:0] sim_mouse_x=48; reg [5:0] sim_mouse_y=40;
    reg sim_mouse_left=0, sim_mouse_right=0, sim_mouse_event=0;
    wire [6:0] mouse_x; wire [5:0] mouse_y;
    wire mouse_left, mouse_right, mouse_event;
    reg [6:0] game_mouse_x;
    reg [5:0] game_mouse_y;
    reg game_mouse_left, game_mouse_right, game_mouse_event;
    // Pipeline the clamped coordinates and their button/event sample together.
    always @(posedge clk) begin
        if(rst) begin
            game_mouse_x<=0; game_mouse_y<=0;
            game_mouse_left<=0; game_mouse_right<=0; game_mouse_event<=0;
        end else begin
            game_mouse_x<=mouse_x; game_mouse_y<=mouse_y;
            game_mouse_left<=mouse_left; game_mouse_right<=mouse_right;
            game_mouse_event<=mouse_event;
        end
    end
    generate if(USE_MOUSE) begin : g_mouse
        wire [11:0] xpos,ypos;
        wire [3:0] zpos;
        wire left_btn,middle_btn,right_btn,new_event;
        reg [11:0] value=0;
        reg setx=0,sety=0,setmax_x=0,setmax_y=0;
        reg [2:0] init_step=0;
        // After reset, limit the pointer to the 96x64 screen and centre it.
        always @(posedge clk) begin
            setx<=0; sety<=0; setmax_x<=0; setmax_y<=0;
            if(rst) init_step<=0;
            else if(init_step!=5) begin
                init_step<=init_step+1'b1;
                case(init_step)
                    1: begin value<=12'd95; setmax_x<=1; end
                    2: begin value<=12'd63; setmax_y<=1; end
                    3: begin value<=12'd48; setx<=1; end
                    4: begin value<=12'd40; sety<=1; end
                    default: ;
                endcase
            end
        end
        MouseCtl mouse(.clk(clk),.rst(rst),.xpos(xpos),.ypos(ypos),.zpos(zpos),
            .left(left_btn),.middle(middle_btn),.right(right_btn),.new_event(new_event),
            .value(value),.setx(setx),.sety(sety),.setmax_x(setmax_x),.setmax_y(setmax_y),
            .ps2_clk(PS2Clk),.ps2_data(PS2Data));
        assign mouse_x = (xpos>12'd95) ? 7'd95 : xpos[6:0];
        assign mouse_y = (ypos>12'd63) ? 6'd63 : ypos[5:0];
        assign mouse_left = left_btn;
        assign mouse_right = right_btn;
        assign mouse_event = new_event;
    end else begin : g_no_mouse
        assign mouse_x = sim_mouse_x; assign mouse_y = sim_mouse_y;
        assign mouse_left = sim_mouse_left; assign mouse_right = sim_mouse_right;
        assign mouse_event = sim_mouse_event;
    end endgenerate

    // ---------------- Test buttons (stand-ins for combat) ----------------
    wire press_d;
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_down(
        .clk(clk),.rst(rst),.button(btnD),.pressed(press_d));

    // ---------------- Final ray-cast world renderer ----------------
    wire [6:0] pixel_x; wire [5:0] pixel_y;
    wire [6:0] world_x; wire [5:0] world_y;
    generate if(WORLD_LATENCY>0) begin : g_late
        // Coordinates reach the "renderer" WORLD_LATENCY clocks late.
        reg [12:0] delay_line [0:WORLD_LATENCY-1];
        integer i;
        always @(posedge clk) begin
            delay_line[0] <= {pixel_x,pixel_y};
            for(i=1;i<WORLD_LATENCY;i=i+1) delay_line[i] <= delay_line[i-1];
        end
        assign world_x = delay_line[WORLD_LATENCY-1][12:6];
        assign world_y = delay_line[WORLD_LATENCY-1][5:0];
    end else begin : g_now
        assign world_x = pixel_x; assign world_y = pixel_y;
    end endgenerate
    wire [15:0] rendered_pixel;
    wire [15:0] world_pixel = (WORLD_PATTERN!=0) ?
        {world_x[4:0], world_y, world_x[6:5], 3'b101} : rendered_pixel;

    // ---------------- game_core ----------------
    wire [255:0] published_map, local_occupied;
    reg [255:0] occupied=0;
    wire [7:0] p1_addr, p2_addr, spawn_tile;
    reg [7:0] p1_current, p2_current;
    reg [1:0] p2_health;
    wire [7:0] local_render_active;
    wire [95:0] local_render_x, local_render_y;
    wire map_ready, map_busy, play_start, frame_begin, frame_idle;
    wire [15:0] active_seed;
    wire [2:0] error_code, game_state;
    wire game_2p_mode;
    wire [6:0] wave; wire [1:0] health;
    wire spawn_req, spawn_ack, enemy_defeated, enemies_clear, shot_fired;
    reg enemy_playing, enemy_clear;
    wire shot_hit, zombie_hit, zombie_hit_p2, player_hit_p2;
    wire [15:0] game_led;
    (* ASYNC_REG="TRUE" *) reg [1:0] aim_meta=0, aim_sync=0;
    wire [7:0] local_controls = {aim_sync, reload_sync, fire_sync, move_sync};
    wire [7:0] remote_controls;
    wire remote_controls_valid, client_snapshot_valid, link_up;
    wire [119:0] host_snapshot, client_snapshot;
    wire [1:0] client_p1_aim = client_snapshot[57:56];
    wire [1:0] client_p2_aim = client_snapshot[55:54];
    wire [1:0] camera_aim = host_mode ? aim_sync : client_p2_aim;
    reg [1:0] sprite_facing;
    reg [9:0] camera_angle;
    always @* begin
        case(camera_aim)
            2'b00: camera_angle=10'd256; // right/east
            2'b01: camera_angle=10'd512; // down/south
            2'b10: camera_angle=10'd768; // left/west
            default: camera_angle=10'd0; // up/north
        endcase
        case(camera_aim)
            2'b00: sprite_facing=2'd0;
            2'b01: sprite_facing=2'd3;
            2'b10: sprite_facing=2'd2;
            default: sprite_facing=2'd1;
        endcase
    end
    wire link_packet_error, link_frame_error, client_zombies_valid;
    wire [71:0] host_zombies, client_zombies;
    wire [1:0] remote_aim = remote_controls[7:6];
    reg remote_fire_prev;
    wire remote_fire_pulse = host_mode && link_up && remote_controls_valid &&
                             remote_controls[4] && !remote_fire_prev;
    always @(posedge clk) begin
        if(rst) remote_fire_prev<=0;
        else if(remote_controls_valid) remote_fire_prev<=remote_controls[4];
    end
    reg [3:0] p1_shot_sequence, p2_shot_sequence;
    reg [3:0] seen_p1_sequence, seen_p2_sequence;
    reg seen_sequences_valid;
    wire client_p1_fire = !host_mode && client_snapshot_valid &&
                          seen_sequences_valid && client_snapshot[45:42]!=seen_p1_sequence;
    wire client_p2_fire = !host_mode && client_snapshot_valid &&
                          seen_sequences_valid && client_snapshot[41:38]!=seen_p2_sequence;
    wire [87:0] snapshot_payload = {
        game_state, wave, p1_current, p2_current, health, p2_health,
        aim_sync, remote_aim, local_render_active,
        p1_shot_sequence, p2_shot_sequence, active_seed, 21'b0, game_2p_mode
    };
    // Snapshot fields (low 88 bits): state[87:85], wave[84:78], P1 tile[77:70],
    // P2 tile[69:62], P1 health[61:60], P2 health[59:58], P1 aim[57:56],
    // P2 aim[55:54], active zombies[53:46], shot sequence counters[45:38],
    // fixed map seed[37:22], selected 2P mode[21].
    assign host_snapshot = {32'b0, snapshot_payload};
    wire [7:0] camera_tile = host_mode ? p1_current : p2_current;
    wire [63:0] host_zombie_tiles;
    wire [63:0] client_zombie_tiles = client_zombies[63:0];
    wire [7:0] display_render_active = host_mode ? local_render_active : client_zombies[71:64];
    wire [95:0] remote_render_x, remote_render_y;
    wire [95:0] display_render_x = host_mode ? local_render_x : remote_render_x;
    wire [95:0] display_render_y = host_mode ? local_render_y : remote_render_y;
    genvar zombie_slot;
    generate for(zombie_slot=0;zombie_slot<8;zombie_slot=zombie_slot+1) begin : g_remote_zombie
        assign host_zombie_tiles[zombie_slot*8 +: 8] = {
            local_render_y[zombie_slot*12+8 +: 4],
            local_render_x[zombie_slot*12+8 +: 4]};
        assign remote_render_x[zombie_slot*12 +: 12] = {
            client_zombie_tiles[zombie_slot*8 +: 4],8'h80};
        assign remote_render_y[zombie_slot*12 +: 12] = {
            client_zombie_tiles[zombie_slot*8+4 +: 4],8'h80};
    end endgenerate
    assign host_zombies = {local_render_active,host_zombie_tiles};
    reg [255:0] remote_occupied, remote_occupied_decode;
    integer zombie_index;
    always @* begin
        remote_occupied_decode=0;
        for(zombie_index=0;zombie_index<8;zombie_index=zombie_index+1)
            if(client_zombies[64+zombie_index])
                remote_occupied_decode[client_zombie_tiles[zombie_index*8 +: 8]]=1'b1;
    end
    // Register the sparse tile-to-mask decode before it enters wave spawning.
    // This breaks the long path from the UART zombie snapshot through the
    // dynamic occupancy mask and into the spawn-finder priority chain.
    always @(posedge clk) begin
        if(rst || !link_up) remote_occupied<=0;
        else remote_occupied<=remote_occupied_decode;
    end
    // Register the host/client occupancy selection. Without this stage the
    // synchronized role bit fans out through a 256-bit mux and the spawn
    // finder in one 100 MHz cycle.
    always @(posedge clk) begin
        if(rst || enemy_clear) occupied<=0;
        else occupied<=host_mode ? local_occupied : remote_occupied;
    end
    multiplayer_link multiplayer_link_i(
        .clk(clk),.rst(rst),.host_mode(host_mode),
        .uart_rx_pin(uart_rx_pin),.uart_tx_pin(uart_tx_pin),
        .local_controls(local_controls),.host_snapshot(host_snapshot),.host_zombies(host_zombies),
        .remote_controls(remote_controls),.remote_controls_valid(remote_controls_valid),
        .client_snapshot(client_snapshot),.client_snapshot_valid(client_snapshot_valid),
        .client_zombies(client_zombies),.client_zombies_valid(client_zombies_valid),
        .link_up(link_up),.packet_error(link_packet_error),.frame_error(link_frame_error));
    reg last_shot_hit;
    always @(posedge clk) begin
        aim_meta<={sw2,sw1};
        aim_sync<=aim_meta;
        if(rst || enemy_clear || shot_fired) last_shot_hit<=0;
        else if(shot_hit) last_shot_hit<=1;
    end
    wire [15:0] host_leds={link_up,1'b1,game_led[13:5],last_shot_hit,game_led[3:0]};
    wire [15:0] client_leds={link_up,1'b0,client_snapshot[87:85],
        client_snapshot[84:78],client_snapshot[65:62]};
    assign led=host_mode ? host_leds : client_leds;
    wire playing = game_state==3'd3;
    // Register the session controls before they fan out to the enemy tile mask.
    always @(posedge clk) begin
        if(rst) begin
            enemy_playing<=0;
            enemy_clear<=1;
        end else begin
            enemy_playing<=playing;
            enemy_clear<=enemies_clear;
        end
    end
    wire spawn_busy;
    localparam integer MOVE_COUNTER_BITS = (MOVE_PERIOD>1) ? $clog2(MOVE_PERIOD) : 1;
    reg [MOVE_COUNTER_BITS-1:0] move_counter;
    wire move_tick = enemy_playing && move_counter==MOVE_PERIOD-1;
    // Clock enable for two movement sweeps per second at 100 MHz.
    always @(posedge clk) begin
        if(rst || enemy_clear || !enemy_playing || move_tick) move_counter<=0;
        else move_counter<=move_counter+1'b1;
    end

    localparam integer PLAYER_MOVE_BITS = (PLAYER_MOVE_PERIOD>1) ? $clog2(PLAYER_MOVE_PERIOD) : 1;
    reg [PLAYER_MOVE_BITS-1:0] player_move_counter;
    wire player_move_tick = enemy_playing && player_move_counter==PLAYER_MOVE_PERIOD-1;
    always @(posedge clk) begin
        if(rst || enemy_clear || !enemy_playing || player_move_tick) player_move_counter<=0;
        else player_move_counter<=player_move_counter+1'b1;
    end
    wire [3:0] p2_move_input = host_mode ? remote_controls[3:0] : local_controls[3:0];
    wire [7:0] p1_move_candidate = moved_tile(p1_current,local_controls[3:0],published_map,p2_current);
    wire [7:0] p2_move_candidate = moved_tile(p2_current,p2_move_input,published_map,p1_current);
    function [7:0] moved_tile;
        input [7:0] current_tile;
        input [3:0] direction;
        input [255:0] map_bits;
        input [7:0] other_player;
        reg [7:0] candidate;
        reg requested;
        begin
            candidate=current_tile; requested=1'b0;
            if(direction[0] && current_tile[7:4]!=0) begin candidate=current_tile-8'd16; requested=1'b1; end
            else if(direction[1] && current_tile[7:4]!=4'hF) begin candidate=current_tile+8'd16; requested=1'b1; end
            else if(direction[2] && current_tile[3:0]!=0) begin candidate=current_tile-8'd1; requested=1'b1; end
            else if(direction[3] && current_tile[3:0]!=4'hF) begin candidate=current_tile+8'd1; requested=1'b1; end
            if(requested && !map_bits[candidate] && candidate!=other_player) moved_tile=candidate;
            else moved_tile=current_tile;
        end
    endfunction
    always @(posedge clk) begin
        if(rst) begin p1_current<=0; p2_current<=0; p2_health<=2'd3; end
        else begin
            if(play_start) begin p1_current<=p1_addr; p2_current<=p2_addr; p2_health<=2'd3; end
            else begin
                if(!host_mode && client_snapshot_valid) begin
                    p1_current<=client_snapshot[77:70];
                    p2_current<=client_snapshot[69:62];
                    p2_health<=client_snapshot[59:58];
                end else if(player_move_tick && playing && map_ready) begin
                    if(host_mode) p1_current<=p1_move_candidate;
                    if(host_mode && link_up && remote_controls[3:0]!=0) p2_current<=p2_move_candidate;
                end
                if(host_mode && player_hit_p2 && p2_health!=0) p2_health<=p2_health-1'b1;
            end
        end
    end
    always @(posedge clk) begin
        if(rst || play_start) begin
            p1_shot_sequence<=0; p2_shot_sequence<=0;
            seen_p1_sequence<=0; seen_p2_sequence<=0; seen_sequences_valid<=0;
        end else if(host_mode) begin
            if(shot_fired) p1_shot_sequence<=p1_shot_sequence+1'b1;
            if(remote_fire_pulse) p2_shot_sequence<=p2_shot_sequence+1'b1;
        end else if(client_snapshot_valid) begin
            seen_p1_sequence<=client_snapshot[45:42];
            seen_p2_sequence<=client_snapshot[41:38];
            seen_sequences_valid<=1;
        end
    end
    game_core #(.STAGE(STAGE),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.ENABLE_2P(ENABLE_2P),
        .FIXED_MAP_SEED(16'h1ACE),
        .SHOW_CURSOR(USE_MOUSE),.GEN_SHIFT(GEN_SHIFT),
        .OVER_SHIFT(OVER_SHIFT),.TINT_SHIFT(TINT_SHIFT),
        .BLINK_SHIFT(BLINK_SHIFT),.SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT),
        .FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT),.RELOAD_SHIFT(RELOAD_SHIFT),
        .WIN_WAVE(WIN_WAVE)) game(
        .clk(clk),.rst(rst),
        .btn_c(btnC),.btn_l(btnL),.btn_d(press_d),.sw_map(sw0),
        .oled_jb(JB),.seg(seg),.dp(dp),.an(an),.led(game_led),
        .mouse_x(game_mouse_x),.mouse_y(game_mouse_y),.mouse_left(game_mouse_left),
        .mouse_right(game_mouse_right),.mouse_event(game_mouse_event),
        .published_map(published_map),.map_ready(map_ready),.map_busy(map_busy),
        .p1_addr(p1_addr),.p2_addr(p2_addr),.active_seed(active_seed),.error_code(error_code),
        .game_state(game_state),.play_start(play_start),.wave(wave),.health(health),
        .selected_2p(game_2p_mode),
        .display_override_enable(!host_mode && link_up),
        .display_game_state_override(client_snapshot[87:85]),
        .display_wave_override(client_snapshot[84:78]),
        .display_health_override(client_snapshot[59:58]),
        .display_selected_2p_override(client_snapshot[21]),
        .teammate_dead(host_mode && ENABLE_2P && game_2p_mode && p2_health==2'd0),
        .player_tile(host_mode ? p1_current : p2_current),
        .player_pos_x({camera_tile[3:0],4'h8}),
        .player_pos_y({camera_tile[7:4],4'h8}),
        .player_angle(camera_angle),.player2_tile(p2_current),
        .world_pixel(world_pixel),.pixel_x(pixel_x),.pixel_y(pixel_y),.frame_begin(frame_begin),
        .frame_idle(frame_idle),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(occupied),
        .player_hit(host_mode ? zombie_hit : 1'b0),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.spawn_busy(spawn_busy),
        .enemies_clear(enemies_clear),.shot_fired(shot_fired));

    // Keep the final project's ray-cast map renderer and layer multiplayer
    // zombie sprites over the same world pixels. The camera is each board's
    // active player, while both boards share the host's authoritative enemy list.
    reg scene_bank, scene_valid, scene_pending;
    wire sprite_done;
    wire scene_reset = rst || enemy_clear || !map_ready || map_busy;
    wire prepare_scene = frame_begin && !scene_reset && !scene_pending;
    always @(posedge clk) begin
        if(scene_reset) begin scene_bank<=0; scene_valid<=0; scene_pending<=0; end
        else if(prepare_scene) scene_pending<=1;
        else if(frame_idle && scene_pending && sprite_done) begin
            scene_bank<=!scene_bank; scene_valid<=1; scene_pending<=0;
        end
    end

    // Match the main game's map-row convention (map y increases downward,
    // ray-caster y increases northward). Positions are tile-centred Q20.12.
    wire [255:0] render_map;
    genvar render_row;
    generate for(render_row=0;render_row<16;render_row=render_row+1) begin : g_render_rows
        assign render_map[render_row*16 +: 16] = published_map[(15-render_row)*16 +: 16];
    end endgenerate
    wire [3:0] camera_row_north = 4'd15-camera_tile[7:4];
    wire [31:0] camera_x = {16'd0,camera_tile[3:0],12'h800};
    wire [31:0] camera_y = {16'd0,camera_row_north,12'h800};
    wire map_renderer_reset = rst || !map_ready || map_busy;
    wire [9:0] wall_depth_steps;
    wire [12:0] wall_depth = wall_depth_steps==10'h3ff ? 13'd4096 :
                             {wall_depth_steps,3'b000};
    wire [15:0] raycast_background;
    wire [95:0] raycast_zombie_y;
    genvar ray_zombie;
    generate for(ray_zombie=0;ray_zombie<8;ray_zombie=ray_zombie+1) begin : g_ray_zombie_y
        wire [11:0] source_y = display_render_y[ray_zombie*12 +: 12];
        assign raycast_zombie_y[ray_zombie*12 +: 12] =
            {4'd15-source_y[11:8],source_y[7:0]};
    end endgenerate
    Map_Renderer #(.USE_RUNTIME_MAP(1),.USE_PIXEL_COORDS(1)) u_Map_Renderer(
        .clk(clk),.reset(map_renderer_reset),.map_bits(render_map),
        .x_coord(camera_x),.y_coord(camera_y),.theta({22'd0,camera_angle}),.game_tick(),
        .display_clk(clk),.frame_begin(frame_idle),.pixel_index(13'd0),
        .pixel_x(world_x),.pixel_y(world_y),.pixel_data(raycast_background),
        .column_depth(wall_depth_steps));
    reg [6:0] view_x;
    reg [5:0] view_y;
    reg view_bank, view_valid;
    // Match the registered wall-table read with its pixel request.
    always @(posedge clk) begin
        view_x<=world_x; view_y<=world_y; view_bank<=scene_bank; view_valid<=scene_valid;
    end
    zombie_renderer #(.USE_CAMERA_POSE(1),.FOCAL_X(83),.FOCAL_Y(64)) sprites(
        .clk(clk),.reset(scene_reset),.prepare(prepare_scene),
        .display_bank(view_bank),.scene_valid(view_valid),
        .camera_x({camera_tile[3:0],8'h80}),
        .camera_y({camera_row_north,8'h80}),
        .facing(sprite_facing),.camera_angle(camera_angle),
        .active(display_render_active),.zombie_x(display_render_x),.zombie_y(raycast_zombie_y),
        .pixel_x(view_x),.pixel_y(view_y),.wall_depth(wall_depth),.background(raycast_background),
        .done(sprite_done),.pixel(rendered_pixel));

    // ---------------- Enemy records and spawn handshake ----------------
    enemy_manager #(.ATTACK_COOLDOWN_CYCLES(ATTACK_COOLDOWN_CYCLES),.TWO_PLAYERS(ENABLE_2P)) enemies(
        .clk(clk),.rst(rst),.clear(enemy_clear),
        .playing(enemy_playing),.map_ready(map_ready && !map_busy),.map_bits(published_map),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.debug_defeat(1'b0),
        .move_tick(move_tick),.spawn_busy(spawn_busy),.player_tile(p1_current),
        .shot_fired(host_mode ? shot_fired : client_p1_fire),
        .aim(host_mode ? aim_sync : client_p1_aim),.shot_hit(shot_hit),
        .player_hit(zombie_hit),.player_hit_p2(zombie_hit_p2),
        .player_active(1'b1),
        .player2_active(ENABLE_2P && game_2p_mode && link_up && p2_health!=0),
        .player2_tile(p2_current),
        .shot_fired_p2(host_mode ? remote_fire_pulse : client_p2_fire),
        .aim_p2(host_mode ? remote_aim : local_controls[7:6]),
        .shot_ready(),.shot_ready_p2(),.shot_hit_player(),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(local_occupied),
        .read_id(3'd0),.active(local_render_active),.render_x(local_render_x),.render_y(local_render_y),
        .read_active(),.read_x(),.read_y(),
        .read_hp(),.read_type(),.read_state(),.read_cooldown());

endmodule
