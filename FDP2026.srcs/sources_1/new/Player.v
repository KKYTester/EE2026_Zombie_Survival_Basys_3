`timescale 1ns / 1ps

module Player (
    input wire reset,
    input wire game_clk, // Has to be 24fps i.e. 24 Hz
    input wire [31:0] dx, // in ms^-1
    input wire [31:0] dy, // in ms^-1
    input wire [31:0] omega, // in rad s^-1
    output reg [31:0] x_coord = 32'd0, //in m
    output reg [31:0] y_coord = 32'd0, // in m
    output reg [31:0] theta = 32'd0// in rad, with 0 as north
);
    // This module holds player's state (position, angle, velocity)
    // The module will also check for collisions to ensure movement will enter a wall
    // TODO: Ensure the velocity updates position correctly.
    // TODO: Collision checker
    always @(posedge game_clk) begin
        if (reset) begin
            x_coord = 0;
            y_coord = 0;
            theta = 0;
        end
        else begin
            x_coord <= x_coord + dx;
            y_coord <= y_coord + dy;
            theta <= theta + omega;
        end
    end
endmodule