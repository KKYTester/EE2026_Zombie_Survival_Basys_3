`timescale 1ns / 1ps

module Player (
    input wire reset,
    input wire clk, // system clock
    input wire game_tick, // one system-clock cycle per game update (24 Hz)
    input wire [31:0] dx, // horizontal velo in m/tick
    input wire [31:0] dy, // vertical velo in m/tick
    input wire [31:0] omega, // in rad/tick
    output reg [31:0] x_coord = 32'd0, //in m
    output reg [31:0] y_coord = 32'd0, // in m
    output reg [31:0] theta = 32'd0// in rad, with 0 as north
);
    // This module holds player's state (position, angle, velocity)
    // The module will also check for collisions to ensure movement will enter a wall
    // Inputs are increments per game tick. 
    // A future controller must scale velocities by the game-update period before supplying them here.
    // TODO: Define the fixed-point coordinate and angle representations.
    // TODO: Collision checker
    always @(posedge clk) begin
        if (reset) begin
            x_coord <= 32'd0;
            y_coord <= 32'd0;
            theta <= 32'd0;
        end
        else if (game_tick) begin
            x_coord <= x_coord + dx;
            y_coord <= y_coord + dy;
            theta <= theta + omega;
        end
    end
endmodule
