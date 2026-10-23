`timescale 1ns / 1ps
module lfsr16(input wire clk, input wire rst, input wire load,
    input wire advance, input wire [15:0] seed, output reg [15:0] value);
    always @(posedge clk) begin
        if (rst) value <= 16'h0001;
        else if (load) value <= (seed == 0) ? 16'h0001 : seed;
        else if (advance)
            value <= (value >> 1) ^ (value[0] ? 16'hB400 : 16'h0000);
    end
endmodule
