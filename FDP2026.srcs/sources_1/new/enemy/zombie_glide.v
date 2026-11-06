`timescale 1ns / 1ps
// Smooth zombie walking for display only.
// enemy_manager keeps each zombie on a tile centre and jumps one tile per
// move tick. This module keeps a separate drawn position per slot that walks
// towards the real position by one 1/256-tile step every STEP_CYCLES clocks,
// so a full tile takes 256*STEP_CYCLES clocks. Set STEP_CYCLES a little below
// MOVE_PERIOD/256 (the top uses MOVE_PERIOD/264, about 3% faster) so each walk
// finishes just before the next move starts. Game logic (paths, hits, attacks,
// minimap tiles) still uses the real tile positions.
//  - A slot that is inactive, or has just become active (spawn), snaps to its
//    real position so it never slides in from where the last zombie died.
//  - If the real position is more than two tiles away on an axis (slot reused
//    without going inactive), it also snaps. Spawns are at least 8 tiles from
//    the player, so a reused slot always lands far from its old position.
// Coordinates are packed like enemy_manager's render_x/render_y: unsigned,
// 4 tile bits above FRAC fraction bits (Q8 by default).
module zombie_glide #(
    parameter integer SLOTS = 8,
    parameter integer FRAC = 8,
    parameter integer STEP_CYCLES = 195_312
)(
    input wire clk, input wire rst,
    input wire [SLOTS-1:0] active,
    input wire [SLOTS*(FRAC+4)-1:0] target_x, target_y,
    output wire [SLOTS*(FRAC+4)-1:0] glide_x, glide_y
);
    localparam integer W = FRAC + 4;
    localparam integer TILE = 1 << FRAC;
    localparam integer STEP_BITS = (STEP_CYCLES > 1) ? $clog2(STEP_CYCLES) : 1;

    reg [STEP_BITS-1:0] step_count;
    wire step = (STEP_CYCLES <= 1) || (step_count == STEP_CYCLES-1);
    always @(posedge clk)
        if(rst || step) step_count <= 0;
        else step_count <= step_count + 1'b1;

    // One axis: move one unit towards the target on a step; snap if far away.
    function [W-1:0] follow;
        input [W-1:0] now, goal;
        input do_step;
        begin
            if(goal > now + 2*TILE || now > goal + 2*TILE) follow = goal;
            else if(!do_step || goal == now) follow = now;
            else if(goal > now) follow = now + 1'b1;
            else follow = now - 1'b1;
        end
    endfunction

    genvar s;
    generate for(s = 0; s < SLOTS; s = s + 1) begin : g_slot
        reg [W-1:0] gx, gy;
        reg was_active;
        wire [W-1:0] tx = target_x[s*W +: W];
        wire [W-1:0] ty = target_y[s*W +: W];
        always @(posedge clk) begin
            if(rst || !active[s] || !was_active) begin
                gx <= tx; gy <= ty;
            end else begin
                gx <= follow(gx, tx, step);
                gy <= follow(gy, ty, step);
            end
            was_active <= !rst && active[s];
        end
        assign glide_x[s*W +: W] = gx;
        assign glide_y[s*W +: W] = gy;
    end endgenerate
endmodule
