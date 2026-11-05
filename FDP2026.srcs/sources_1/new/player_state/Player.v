`timescale 1ns / 1ps

module Player #(
    parameter [31:0] START_X = 32'd0,
    parameter [31:0] START_Y = 32'd0,
    parameter [31:0] START_ANGLE = 32'd0,
    parameter USE_RUNTIME_SPAWN = 0
) (
    input wire reset,
    input wire [31:0] spawn_x, spawn_y,
    input wire clk, // system clock
    input wire game_tick, // one system-clock cycle per game update (24 Hz)
    input wire [31:0] dx, // x increment per tick, 12 fractional bits
    input wire [31:0] dy, // y increment per tick, 12 fractional bits
    input wire [31:0] omega, // angle increment per tick, 1024 units per turn
    output reg [31:0] x_coord = 32'd0,
    output reg [31:0] y_coord = 32'd0,
    output reg [31:0] theta = 32'd0 // low 10 bits: 0 north, clockwise positive
);
    // This module holds position and angle. x points east, y points north.
    // Inputs are increments per game tick (two's complement for negative steps).
    // Player_Controller supplies collision-checked increments per update.
    wire [9:0] next_angle = theta[9:0] + omega[9:0];
    always @(posedge clk) begin
        if (reset) begin
            x_coord <= USE_RUNTIME_SPAWN ? spawn_x : START_X;
            y_coord <= USE_RUNTIME_SPAWN ? spawn_y : START_Y;
            theta <= {22'd0, START_ANGLE[9:0]};
        end
        else if (game_tick) begin
            x_coord <= x_coord + dx;
            y_coord <= y_coord + dy;
            theta <= {22'd0, next_angle};
        end
    end
endmodule
