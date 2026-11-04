`timescale 1ns / 1ps
// Enemy demo: SW2:SW1 aims right, down, left or up. btnR is debug removal.
module enemy_test_top #(parameter STAGE=3, parameter DEBOUNCE_CYCLES=1000000,
    parameter USE_MOUSE=1, parameter ENABLE_2P=0,
    parameter GEN_SHIFT=26, parameter OVER_SHIFT=27,
    parameter TINT_SHIFT=25, parameter BLINK_SHIFT=24,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23, parameter RELOAD_SHIFT=25,
    parameter WIN_WAVE=10, parameter WORLD_PATTERN=0, parameter WORLD_LATENCY=0,
    parameter integer MOVE_PERIOD=50_000_000)(
    input wire clk, input wire sw0, input wire sw1, sw2, input wire btnC, input wire btnU,
    input wire btnL, input wire btnR, input wire btnD,
    inout wire PS2Clk, inout wire PS2Data,
    output wire [15:0] led, output wire [7:0] JB,
    output wire [6:0] seg, output wire dp, output wire [3:0] an);
    // ASSUMPTION: EE2026 Pmod OLEDrgb on JB, as in the supplied lab project.
    // FPGA power-up initialisation; all functional resets below are synchronous.
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync=2'b11;
    wire rst=reset_sync[1];
    always @(posedge clk) reset_sync<={reset_sync[0],btnU};

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
    wire press_r,press_d;
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_right(
        .clk(clk),.rst(rst),.button(btnR),.pressed(press_r));
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_down(
        .clk(clk),.rst(rst),.button(btnD),.pressed(press_d));

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
    reg enemy_playing, enemy_clear;
    wire shot_hit;
    wire [15:0] game_led;
    (* ASYNC_REG="TRUE" *) reg [1:0] aim_meta=0, aim_sync=0;
    reg last_shot_hit;
    always @(posedge clk) begin
        aim_meta<={sw2,sw1};
        aim_sync<=aim_meta;
        if(rst || enemy_clear || shot_fired) last_shot_hit<=0;
        else if(shot_hit) last_shot_hit<=1;
    end
    assign led={game_led[15:5],last_shot_hit,game_led[3:0]};
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
    game_core #(.STAGE(STAGE),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.ENABLE_2P(ENABLE_2P),
        .SHOW_CURSOR(USE_MOUSE),.GEN_SHIFT(GEN_SHIFT),
        .OVER_SHIFT(OVER_SHIFT),.TINT_SHIFT(TINT_SHIFT),
        .BLINK_SHIFT(BLINK_SHIFT),.SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT),
        .FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT),.RELOAD_SHIFT(RELOAD_SHIFT),
        .WIN_WAVE(WIN_WAVE)) game(
        .clk(clk),.rst(rst),
        .btn_c(btnC),.btn_l(btnL),.sw_map(sw0),
        .oled_jb(JB),.seg(seg),.dp(dp),.an(an),.led(game_led),
        .mouse_x(game_mouse_x),.mouse_y(game_mouse_y),.mouse_left(game_mouse_left),
        .mouse_right(game_mouse_right),.mouse_event(game_mouse_event),
        .published_map(published_map),.map_ready(map_ready),.map_busy(map_busy),
        .p1_addr(p1_addr),.p2_addr(p2_addr),.active_seed(active_seed),.error_code(error_code),
        .game_state(game_state),.play_start(play_start),.wave(wave),.health(health),
        .player_tile(p1_addr),
        .world_pixel(world_pixel),.pixel_x(pixel_x),.pixel_y(pixel_y),.frame_begin(frame_begin),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(occupied),
        .player_hit(press_d),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.spawn_busy(spawn_busy),
        .enemies_clear(enemies_clear),.shot_fired(shot_fired));

    // ---------------- Enemy records and spawn handshake ----------------
    enemy_manager enemies(.clk(clk),.rst(rst),.clear(enemy_clear),
        .playing(enemy_playing),.map_ready(map_ready && !map_busy),.map_bits(published_map),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.debug_defeat(press_r),
        .move_tick(move_tick),.spawn_busy(spawn_busy),.player_tile(p1_addr),
        .shot_fired(shot_fired),.aim(aim_sync),.shot_hit(shot_hit),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(occupied),
        .read_id(3'd0),.active(),.read_active(),.read_x(),.read_y(),
        .read_hp(),.read_type(),.read_state(),.read_cooldown());
endmodule
