`timescale 1ns / 1ps

module Player (
    input wire game_clk, // Has to be 24fps i.e. 24 Hz
    input wire [31:0] dx, // in ms^-1
    input wire [31:0] dy, // in ms^-1
    input wire [31:0] omega, // in rad s^-1
    output reg [31:0] x_coord, //in m
    output reg [31:0] y_coord, // in m
    output reg [31:0] theta // in rad, with 0 as north
);
    // TODO: Ensure the velocity updates position correctly.
    always @(posedge game_clk) begin
        x_coord <= x_coord + dx;
        y_coord <= y_coord + dy;
        theta <= theta + omega;
    end
endmodule