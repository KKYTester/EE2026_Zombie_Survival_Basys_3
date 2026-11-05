`timescale 1ns / 1ps
// Map overlay (SW0): the whole 16x16 map as a 64x64 picture at x=32..95,
// four pixels per tile, with a one-pixel white border.
//  - The player is a 2x2 green dot at its actual position, with a two-pixel
//    white pointer in the facing direction (16 directions).
//  - P2's tile is yellow, only in a two-player game (show_p2).
// Player position: player_x/player_y in tiles with 4 fractional bits, y down
// (same orientation as the map rows). player_angle: 1024 units per turn,
// 0 = up (north on the minimap), increasing clockwise.
module map_display_mux(
    input wire [6:0] px, input wire [5:0] py,
    input wire minimap_mode, input wire [15:0] fp_pixel_data,
    input wire [255:0] map_bits, input wire [7:0] p1_addr,p2_addr,
    input wire [7:0] player_x, input wire [7:0] player_y, input wire [9:0] player_angle,
    input wire show_p2,                   // 1 only in a two-player game
    input wire [15:0] seed, input wire map_ready,busy,bfs_enabled,
    input wire [2:0] error_code, output reg [15:0] pixel_data);
    // Status ports retained for interface compatibility and a future HUD.
    localparam WALL=16'h4AD1, FLOOR=16'h0841, GREEN=16'h07E0,
               YELLOW=16'hFFE0, WHITE=16'hFFFF, BLACK=16'h0000;
    wire [6:0] mx=px-7'd32;
    wire [7:0] mini_addr={py[5:2],mx[5:2]};
    // Player dot: pixels (sx-1..sx, sy-1..sy) inside the 64x64 picture.
    wire signed [7:0] sx = {2'b00,player_x[7:2]};
    wire signed [7:0] sy = {2'b00,player_y[7:2]};
    wire signed [7:0] dx = $signed({1'b0,mx}) - sx;
    wire signed [7:0] dy = $signed({2'b00,py}) - sy;
    wire on_dot = (dx==-1 || dx==0) && (dy==-1 || dy==0);
    // Facing: nearest of 16 directions; two pointer pixels at radius 2 and 3.
    wire [3:0] dir = (player_angle + 10'd32) >> 6;
    reg signed [7:0] h1x,h1y,h2x,h2y;
    always @* begin
        case(dir)
            4'd0: begin h1x=0; h1y=-2; h2x=0; h2y=-3; end
            4'd1: begin h1x=0; h1y=-2; h2x=1; h2y=-3; end
            4'd2: begin h1x=1; h1y=-2; h2x=2; h2y=-3; end
            4'd3: begin h1x=1; h1y=-1; h2x=2; h2y=-2; end
            4'd4: begin h1x=2; h1y=-1; h2x=3; h2y=-1; end
            4'd5: begin h1x=1; h1y=0; h2x=2; h2y=1; end
            4'd6: begin h1x=1; h1y=1; h2x=2; h2y=2; end
            4'd7: begin h1x=0; h1y=1; h2x=1; h2y=2; end
            4'd8: begin h1x=0; h1y=2; h2x=0; h2y=3; end
            4'd9: begin h1x=-1; h1y=1; h2x=-2; h2y=2; end
            4'd10: begin h1x=-2; h1y=1; h2x=-3; h2y=2; end
            4'd11: begin h1x=-2; h1y=0; h2x=-3; h2y=1; end
            4'd12: begin h1x=-2; h1y=0; h2x=-3; h2y=0; end
            4'd13: begin h1x=-2; h1y=-1; h2x=-3; h2y=-2; end
            4'd14: begin h1x=-2; h1y=-2; h2x=-3; h2y=-3; end
            4'd15: begin h1x=-1; h1y=-2; h2x=-2; h2y=-3; end
            default: begin h1x=0; h1y=-2; h2x=0; h2y=-3; end
        endcase
    end
    wire on_pointer = (dx==h1x && dy==h1y) || (dx==h2x && dy==h2y);
    always @* begin
        pixel_data=fp_pixel_data;
        if(minimap_mode && px>=32 && px<=95) begin
            if(px==32 || px==95 || py==0 || py==63) pixel_data=WHITE;
            else if(!map_ready) pixel_data=BLACK;
            else begin
                pixel_data=map_bits[mini_addr] ? WALL : FLOOR;
                if(show_p2 && mini_addr==p2_addr) pixel_data=YELLOW;
                if(on_dot) pixel_data=GREEN;
                else if(on_pointer) pixel_data=WHITE;
            end
        end
    end
endmodule
