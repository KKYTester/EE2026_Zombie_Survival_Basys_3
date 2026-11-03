`timescale 1ns / 1ps
// Damage tint and low-health blink timers (100 MHz domain).
// Wave announcements have been removed; the small HUD wave number remains.
module hud_effects_ctrl #(parameter TINT_SHIFT=25, parameter BLINK_SHIFT=24)(
    input wire clk, input wire rst,
    input wire playing, input wire damage,
    input wire [1:0] health,
    output wire tint, output wire low_blink);
    reg [TINT_SHIFT:0] tint_timer;
    reg [BLINK_SHIFT:0] blink_timer;
    assign tint = playing && !tint_timer[TINT_SHIFT];
    assign low_blink = (health==2'd1) && blink_timer[BLINK_SHIFT];
    always @(posedge clk) begin
        if(rst) begin
            tint_timer<={1'b1,{TINT_SHIFT{1'b0}}};
            blink_timer<=0;
        end else begin
            blink_timer<=blink_timer+1'b1;
            if(damage) tint_timer<=0;
            else if(!tint_timer[TINT_SHIFT]) tint_timer<=tint_timer+1'b1;
        end
    end
endmodule
