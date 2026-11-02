`timescale 1ns / 1ps
module baud_gen #(parameter CLK_FREQ=100000000, parameter BAUD=115200)(
    input wire clk, input wire rst, output reg tick_16x);

    localparam DIVISOR = CLK_FREQ/(BAUD*16);
    reg [15:0] count;

    always @(posedge clk) begin
        if (rst) begin
            count <= 0;
            tick_16x <= 1'b0;
        end else if (count == DIVISOR-1) begin
            count <= 0;
            tick_16x <= 1'b1;
        end else begin
            count <= count + 1'b1;
            tick_16x <= 1'b0;
        end
    end
endmodule
