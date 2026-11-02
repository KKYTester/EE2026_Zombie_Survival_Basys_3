`timescale 1ns / 1ps

module Clk_Divider (
    input wire clk,
    input wire [31:0]divider,
    output reg clk_out = 1'b0
);
    reg [31:0] counter = 0;

    always @(posedge clk) begin
        if (counter >= divider) begin
            counter <= 0;
            clk_out <= ~clk_out;
        end else begin
            counter <= counter + 1;
        end
    end
endmodule
