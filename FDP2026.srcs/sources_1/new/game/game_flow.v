`timescale 1ns / 1ps
// Single-player game flow: TITLE -> GENERATING -> COUNTDOWN -> PLAYING -> GAME OVER -> TITLE.
//  - Title: mouse hover highlights an option, left-click on it confirms.
//    Buttons work too: btnL/btnR move the selection, btnC confirms.
//  - The 2-player option is shown but disabled unless ENABLE_2P = 1
//    (two-player flow is not implemented yet).
//  - Confirming consumes the press: it never reaches the playing state.
//  - Generating: requests one new map (the seed is whatever the free-running
//    counter holds at that moment) and shows the screen for at least
//    2^GEN_SHIFT clocks so the player can read it.
//  - Countdown: 3, 2, 1, each 2^COUNT_SHIFT clocks, then PLAYING (play_start pulses).
//  - Playing ends when health reaches 0. Game over ignores input for
//    2^OVER_SHIFT clocks (over_ready=0), then a click or btnC returns to the title.
module game_flow #(parameter ENABLE_2P = 0, parameter GEN_SHIFT = 26,
                   parameter COUNT_SHIFT = 26, parameter OVER_SHIFT = 27)(
    input wire clk, input wire rst,
    input wire btn_c, input wire btn_l, input wire btn_r,   // one-clock pulses
    input wire [6:0] mouse_x, input wire [5:0] mouse_y,
    input wire mouse_left, input wire mouse_event,
    input wire map_ready, input wire map_busy,
    input wire health_zero,
    output reg [2:0] state,            // 0 title, 1 generating, 2 countdown, 3 playing, 4 game over
    output reg sel,                    // 0 = 1 PLAYER, 1 = 2 PLAYERS
    output reg regenerate,             // one-clock new-map request
    output reg play_start,             // one-clock pulse when playing begins
    output reg [1:0] count_digit,
    output wire [5:0] progress,
    output wire over_ready);
    localparam S_TITLE=3'd0, S_GEN=3'd1, S_COUNT=3'd2, S_PLAY=3'd3, S_OVER=3'd4;
    localparam MAX_A = (GEN_SHIFT > COUNT_SHIFT) ? GEN_SHIFT : COUNT_SHIFT;
    localparam MAX_SHIFT = (MAX_A > OVER_SHIFT) ? MAX_A : OVER_SHIFT;
    // Option rectangles, identical to menu_screens.
    localparam OPT_X0=18, OPT_X1=77, OPT1_Y0=26, OPT1_Y1=34, OPT2_Y0=35, OPT2_Y1=43;
    reg [MAX_SHIFT:0] timer;
    reg requested, seen_busy, left_prev;
    wire in_x = mouse_x>=OPT_X0 && mouse_x<=OPT_X1;
    wire over_1p = in_x && mouse_y>=OPT1_Y0 && mouse_y<=OPT1_Y1;
    wire over_2p = in_x && mouse_y>=OPT2_Y0 && mouse_y<=OPT2_Y1 && ENABLE_2P;
    wire click = mouse_left && !left_prev;
    wire click_confirm = click && (over_1p || over_2p);
    wire click_sel = over_2p;                   // option under the pointer
    wire gen_done = timer[GEN_SHIFT];
    wire step_done = timer[COUNT_SHIFT];
    wire over_done = timer[OVER_SHIFT];
    assign progress = (state!=S_GEN) ? 6'd0 : (gen_done ? 6'd63 : timer[GEN_SHIFT-1 -: 6]);
    assign over_ready = (state==S_OVER) && over_done;
    always @(posedge clk) begin
        if(rst) begin
            state<=S_TITLE; sel<=0; regenerate<=0; play_start<=0; count_digit<=3; timer<=0;
            requested<=0; seen_busy<=0; left_prev<=0;
        end else begin
            regenerate<=0; play_start<=0;
            left_prev<=mouse_left;
            case(state)
                S_TITLE: begin
                    if(mouse_event && over_1p) sel<=0;
                    if(mouse_event && over_2p) sel<=1;
                    if(ENABLE_2P && (btn_l || btn_r)) sel<=~sel;
                    // Two-player start is not implemented: only 1P can be confirmed.
                    if((btn_c && sel==0) || (click_confirm && click_sel==0)) begin
                        sel<=0; state<=S_GEN; timer<=0; requested<=0; seen_busy<=0;
                    end
                end
                S_GEN: begin
                    if(!gen_done) timer<=timer+1'b1;
                    if(!requested && !map_busy) begin regenerate<=1; requested<=1; end
                    if(requested && map_busy) seen_busy<=1;
                    if(gen_done && seen_busy && map_ready && !map_busy) begin
                        state<=S_COUNT; timer<=0; count_digit<=3;
                    end else if(seen_busy && !map_busy && !map_ready) begin
                        // Generation ended in an error: ask again with a new seed.
                        requested<=0; seen_busy<=0;
                    end
                end
                S_COUNT: begin
                    if(step_done) begin
                        timer<=0;
                        if(count_digit==1) begin state<=S_PLAY; play_start<=1; end
                        else count_digit<=count_digit-1'b1;
                    end else timer<=timer+1'b1;
                end
                S_PLAY: begin
                    // Mouse and btnC are left to the game; only death leaves this state.
                    if(health_zero && !play_start) begin state<=S_OVER; timer<=0; end
                end
                S_OVER: begin
                    if(!over_done) timer<=timer+1'b1;
                    else if(btn_c || click) state<=S_TITLE;
                end
                default: state<=S_TITLE;
            endcase
        end
    end
endmodule
