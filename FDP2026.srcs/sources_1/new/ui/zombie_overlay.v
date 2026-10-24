`timescale 1ns / 1ps
// Draws zombies as red 2x2 dots on the 64x64 map overlay (x=32..95, 4 px per tile),
// the same size and position as the player spawn dots. Combinational.
module zombie_overlay(input wire [6:0] px, input wire [5:0] py,
    input wire minimap_mode, input wire [255:0] zombies,
    input wire [15:0] pixel_in, output wire [15:0] pixel_out);
    wire [6:0] mx = px - 7'd32;
    wire [7:0] tile = {py[5:2], mx[5:2]};
    wire inner = (mx[1:0]==2'd1 || mx[1:0]==2'd2) && (py[1:0]==2'd1 || py[1:0]==2'd2);
    wire on_map = minimap_mode && px>=33 && px<=94 && py>=1 && py<=62;
    assign pixel_out = (on_map && inner && zombies[tile]) ? 16'hF800 : pixel_in;
endmodule
