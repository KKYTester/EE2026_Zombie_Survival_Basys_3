`timescale 1ns / 1ps
// Integrated single-player game: game_core owns flow, UI and OLED output.
// The temporary enemies/test switches are retained until combat integration.
module My_Top_Module #(
    parameter DEBOUNCE_CYCLES=1000000,
    parameter GEN_SHIFT=26, parameter OVER_SHIFT=27,
    parameter TINT_SHIFT=25, parameter BLINK_SHIFT=24,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23, parameter RELOAD_SHIFT=25,
    parameter WIN_WAVE=10
)(
    input wire clk,
    input wire btnC, btnU, btnL, btnR, btnD,
    input wire sw0, sw13, sw14, sw15,
    inout wire ps2_clk, ps2_data,
    output wire [15:0] led,
    output wire [7:0] JB,
    output wire [6:0] seg, output wire dp, output wire [3:0] an
);
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync=2'b11;
    wire reset=reset_sync[1];
    always @(posedge clk) reset_sync <= {reset_sync[0],sw15};

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

    wire [255:0] published_map, occupied;
    wire [7:0] p1_addr, p2_addr, spawn_tile;
    wire map_ready, map_busy, play_start, frame_begin, frame_idle;
    wire spawn_req, spawn_ack, enemy_defeated, enemies_clear, shot_fired;
    wire test_kill, test_hit;
    switch_toggle #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) kill_switch(
        .clk(clk),.rst(reset),.switch_in(sw14),.flipped(test_kill));
    switch_toggle #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) hit_switch(
        .clk(clk),.rst(reset),.switch_in(sw13),.flipped(test_hit));

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
    wire [31:0] player_x, player_y, player_angle;
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

    wire [6:0] pixel_x;
    wire [5:0] pixel_y;
    // game_core supplies look-ahead coordinates, including the tail pixel.
    wire [15:0] world_pixel;
    // Give the player one clock to load a newly published spawn before scan 0.
    reg map_valid_delayed=0;
    always @(posedge clk) map_valid_delayed <= !reset && map_ready && !map_busy;
    // Prepare even while GENERATING once a validated map is published.
    // A scan takes at most 96*(768+8) = 74496 board clocks (<0.75 ms).
    // Completed banks swap only during the display's idle window. The bank
    // and map/player snapshot stay immutable throughout transmission.
    Map_Renderer #(.USE_RUNTIME_MAP(1),.USE_PIXEL_COORDS(1)) u_Map_Renderer (
        .clk(clk),.reset(reset || !map_ready || map_busy || !map_valid_delayed),.map_bits(world_map),
        .x_coord(player_x),.y_coord(player_y),.theta(player_angle),.game_tick(game_tick),
        .display_clk(clk),.frame_begin(frame_idle),.pixel_index(13'd0),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .pixel_data(world_pixel),.column_depth()
    );
    game_core #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.GEN_SHIFT(GEN_SHIFT),.OVER_SHIFT(OVER_SHIFT),
        .TINT_SHIFT(TINT_SHIFT),.BLINK_SHIFT(BLINK_SHIFT),
        .SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT),
        .FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT),.RELOAD_SHIFT(RELOAD_SHIFT),
        .WIN_WAVE(WIN_WAVE)) game (
        .clk(clk),.rst(reset),.btn_c(btnC),.sw_map(sw0),
        .oled_jb(JB),.seg(seg),.dp(dp),.an(an),.led(led),
        .mouse_x(mouse_x),.mouse_y(mouse_y),.mouse_left(mouse_left),
        .mouse_right(mouse_right),.mouse_event(mouse_event),
        .published_map(published_map),.map_ready(map_ready),.map_busy(map_busy),
        .p1_addr(p1_addr),.p2_addr(p2_addr),.active_seed(),.error_code(),
        .game_state(game_state),.play_start(play_start),.wave(),.health(),
        .player_tile(player_tile),.world_pixel(world_pixel),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.frame_begin(frame_begin),.frame_idle(frame_idle),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(occupied),
        .player_hit(test_hit),.spawn_req(spawn_req),.spawn_tile(spawn_tile),.spawn_busy(),
        .enemies_clear(enemies_clear),.shot_fired(shot_fired)
    );
    zombie_stub enemies(.clk(clk),.rst(reset),.clear(enemies_clear),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.defeat(test_kill && playing),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(occupied));
endmodule
