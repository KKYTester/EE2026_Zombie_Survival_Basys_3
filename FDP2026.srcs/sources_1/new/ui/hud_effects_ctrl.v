`timescale 1ns / 1ps
// Timers for HUD effects (100 MHz domain):
//  - tint: on for 2^TINT_SHIFT clocks after each damage pulse (~0.34 s).
//  - banner: "WAVE n" for 2^BANNER_SHIFT clocks when play starts or the wave changes (~1.3 s).
//  - low_blink: with one heart left, toggles every 2^BLINK_SHIFT clocks (~3 Hz flash).
module hud_effects_ctrl #(parameter TINT_SHIFT=25, parameter BANNER_SHIFT=27,
                          parameter BLINK_SHIFT=24)(
    input wire clk, input wire rst,
    input wire playing, input wire play_start, input wire damage,
    input wire [6:0] wave, input wire [1:0] health,
    output wire tint, output wire banner, output wire low_blink);
    reg [TINT_SHIFT:0] tint_timer;
    reg [BANNER_SHIFT:0] banner_timer;
    reg [BLINK_SHIFT:0] blink_timer;
    reg [6:0] last_wave;
    assign tint = playing && !tint_timer[TINT_SHIFT];
    assign banner = playing && !banner_timer[BANNER_SHIFT];
    assign low_blink = (health==2'd1) && blink_timer[BLINK_SHIFT];
    always @(posedge clk) begin
        if(rst) begin
            tint_timer<={1'b1,{TINT_SHIFT{1'b0}}};       // expired
            banner_timer<={1'b1,{BANNER_SHIFT{1'b0}}};
            blink_timer<=0; last_wave<=0;
        end else begin
            blink_timer<=blink_timer+1'b1;
            last_wave<=wave;
            if(damage) tint_timer<=0;
            else if(!tint_timer[TINT_SHIFT]) tint_timer<=tint_timer+1'b1;
            if(play_start || (playing && wave!=last_wave)) banner_timer<=0;
            else if(!banner_timer[BANNER_SHIFT]) banner_timer<=banner_timer+1'b1;
        end
    end
endmodule
