`timescale 1ns / 1ps
// Standalone demo board top: game_core plus temporary stand-ins for the
// teammates' modules, so the whole single-player flow runs on one Basys 3.
//   - World view (Member 1): flat sky over floor (WORLD_PATTERN=0), or a test
//     pattern that changes every pixel (WORLD_PATTERN=1, used by tb_oled),
//     optionally answered WORLD_LATENCY clocks late to prove the look-ahead.
//   - Player tile (Member 1): the P1 spawn tile; the player does not move.
//   - Mouse (Member 1): MouseCtl with the pointer clamped to the screen.
//   - Enemies (Member 2): zombie_stub accepts every spawn. Test actions on
//     switches, one event per flip: SW14 defeats the oldest zombie, SW13
//     stands in for a zombie hitting the player.
// Controls: SW15 up = reset (title, seed 1ACE). btnC starts/fires, left-click
// fires, right-click reloads, SW0 shows the map. btnU/btnL/btnR/btnD are not
// used here: they are reserved for Member 1's movement.
// In the integrated game, My_Top_Module instantiates game_core and connects
// the real modules to the same ports instead.
module map_preview_top #(parameter STAGE=3, parameter DEBOUNCE_CYCLES=1000000,
    parameter USE_MOUSE=1, parameter ENABLE_2P=0,
    parameter GEN_SHIFT=26, parameter OVER_SHIFT=27,
    parameter TINT_SHIFT=25, parameter BLINK_SHIFT=24,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23, parameter RELOAD_SHIFT=25,
    parameter WIN_WAVE=10, parameter WORLD_PATTERN=0, parameter WORLD_LATENCY=0)(
    input wire clk, input wire sw0, input wire btnC,
    input wire sw13, input wire sw14, input wire sw15,
    inout wire PS2Clk, inout wire PS2Data,
    output wire [15:0] led, output wire [7:0] JB,
    output wire [6:0] seg, output wire dp, output wire [3:0] an);
    // ASSUMPTION: EE2026 Pmod OLEDrgb on JB, as in the supplied lab project.
    // FPGA power-up initialisation; all functional resets below are synchronous.
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync=2'b11;
    wire rst=reset_sync[1];
    always @(posedge clk) reset_sync<={reset_sync[0],sw15};      // SW15 up = reset

    // ---------------- Mouse (Member 1 will own this) ----------------
    // Simulation hook: with USE_MOUSE=0 a testbench drives these registers.
    reg [6:0] sim_mouse_x=48; reg [5:0] sim_mouse_y=40;
    reg sim_mouse_left=0, sim_mouse_right=0, sim_mouse_event=0;
    wire [6:0] mouse_x; wire [5:0] mouse_y;
    wire mouse_left, mouse_right, mouse_event;
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

    // ---------------- Test switches (stand-ins for combat) ----------------
    wire test_kill, test_hit;
    switch_toggle #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) kill_switch(
        .clk(clk),.rst(rst),.switch_in(sw14),.flipped(test_kill));
    switch_toggle #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) hit_switch(
        .clk(clk),.rst(rst),.switch_in(sw13),.flipped(test_hit));

    // ---------------- World view stand-in (Member 1) ----------------
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
    wire [15:0] world_pixel = (WORLD_PATTERN!=0) ? {world_x[4:0], world_y, world_x[6:5], 3'b101} :
                              (world_y<32) ? 16'h1084 : 16'h3166;

    // ---------------- game_core ----------------
    wire [255:0] published_map, occupied;
    wire [7:0] p1_addr, p2_addr, spawn_tile;
    wire map_ready, map_busy, play_start, frame_begin;
    wire [15:0] active_seed;
    wire [2:0] error_code, game_state;
    wire [6:0] wave; wire [1:0] health;
    wire spawn_req, spawn_ack, enemy_defeated, enemies_clear, shot_fired;
    wire playing = game_state==3'd3;
    game_core #(.STAGE(STAGE),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.ENABLE_2P(ENABLE_2P),
        .SHOW_CURSOR(USE_MOUSE),.GEN_SHIFT(GEN_SHIFT),
        .OVER_SHIFT(OVER_SHIFT),.TINT_SHIFT(TINT_SHIFT),
        .BLINK_SHIFT(BLINK_SHIFT),.SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT),
        .FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT),.RELOAD_SHIFT(RELOAD_SHIFT),
        .WIN_WAVE(WIN_WAVE)) game(
        .clk(clk),.rst(rst),
        .btn_c(btnC),.sw_map(sw0),
        .oled_jb(JB),.seg(seg),.dp(dp),.an(an),.led(led),
        .mouse_x(mouse_x),.mouse_y(mouse_y),.mouse_left(mouse_left),
        .mouse_right(mouse_right),.mouse_event(mouse_event),
        .published_map(published_map),.map_ready(map_ready),.map_busy(map_busy),
        .p1_addr(p1_addr),.p2_addr(p2_addr),.active_seed(active_seed),.error_code(error_code),
        .game_state(game_state),.play_start(play_start),.wave(wave),.health(health),
        .player_tile(p1_addr),
        .world_pixel(world_pixel),.pixel_x(pixel_x),.pixel_y(pixel_y),.frame_begin(frame_begin),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(occupied),
        .player_hit(test_hit),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),
        .enemies_clear(enemies_clear),.shot_fired(shot_fired));

    // ---------------- Enemy stand-in (Member 2) ----------------
    zombie_stub enemies(.clk(clk),.rst(rst),.clear(enemies_clear),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.defeat(test_kill && playing),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(occupied));
endmodule
