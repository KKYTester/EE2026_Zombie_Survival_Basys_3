`timescale 1ns / 1ps
// Damage tint over the finished play view. No wave-announcement overlays.
module play_effects(input wire [15:0] pixel_in, input wire tint,
    output wire [15:0] pixel_out);
    assign pixel_out = tint ?
        {{1'b0,pixel_in[15:12]}+5'd16, 1'b0, pixel_in[10:6], 1'b0, pixel_in[4:1]} : pixel_in;
endmodule
