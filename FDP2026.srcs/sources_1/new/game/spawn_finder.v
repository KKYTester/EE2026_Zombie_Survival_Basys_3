`timescale 1ns / 1ps
// Picks a zombie spawn tile: a floor tile at least MIN_DIST walking steps from
// the player, not occupied, chosen pseudo-randomly.
//  1. NEAR: all 256 tiles flood out from the player in parallel, one step per
//     clock, through floor only (MIN_DIST-1 clocks). The outer ring is always
//     wall, so row wrap-around in the 1-bit shifts can never reach a floor tile.
//  2. SCAN: from a random start tile, walk the 256 tiles once and take the first
//     floor tile that is neither near nor occupied (at most 256 clocks).
// Result: done pulses with found=1 and tile, or found=0 if no tile qualifies.
module spawn_finder #(parameter MIN_DIST=8)(
    input wire clk, input wire rst, input wire start,
    input wire [255:0] map_bits,          // 1 = wall
    input wire [255:0] occupied,          // tiles already holding a zombie
    input wire [7:0] player_tile,         // {y,x}
    input wire [7:0] random_start,
    output reg busy, output reg done, output reg found, output reg [7:0] tile);
    localparam S_IDLE=2'd0, S_NEAR=2'd1, S_SCAN=2'd2;
    reg [1:0] state;
    reg [255:0] near;
    reg [4:0] steps;
    reg [7:0] index;
    reg [8:0] scanned;
    wire [255:0] floor = ~map_bits;
    // One flood step: neighbours left/right (+-1) and up/down (+-16), floor only.
    wire [255:0] grown = (near | (near<<1) | (near>>1) | (near<<16) | (near>>16)) & floor;
    wire candidate = floor[index] && !near[index] && !occupied[index];
    always @(posedge clk) begin
        if(rst) begin
            state<=S_IDLE; busy<=0; done<=0; found<=0; tile<=0;
            near<=0; steps<=0; index<=0; scanned<=0;
        end else begin
            done<=0;
            case(state)
                S_IDLE: if(start) begin
                    near<=256'd1 << player_tile; steps<=0; busy<=1; state<=S_NEAR;
                end
                S_NEAR: begin
                    near<=grown; steps<=steps+1'b1;
                    if(steps==MIN_DIST-2) begin index<=random_start; scanned<=0; state<=S_SCAN; end
                end
                S_SCAN: begin
                    if(candidate) begin
                        tile<=index; found<=1; done<=1; busy<=0; state<=S_IDLE;
                    end else if(scanned==9'd255) begin
                        found<=0; done<=1; busy<=0; state<=S_IDLE;
                    end else begin
                        index<=index+1'b1; scanned<=scanned+1'b1;
                    end
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
