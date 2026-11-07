`timescale 1ns / 1ps
// Pickups on the 64x64 map overlay (x=32..95, 4 px per tile), drawn over
// the map and zombie dots: health as a red plus filling the tile's inner 3x3,
// a magazine as an orange 2x3 bar. Combinational.
module pickup_overlay(
    input wire [6:0] px, input wire [5:0] py,
    input wire minimap_mode,
    input wire health_valid, input wire [7:0] health_tile,
    input wire mag_valid, input wire [7:0] mag_tile,
    input wire [15:0] pixel_in, output wire [15:0] pixel_out);
    localparam HEALTH=16'hF800, MAG=16'hFD20;
    wire [6:0] mx = px - 7'd32;
    wire [7:0] tile = {py[5:2], mx[5:2]};
    wire on_map = minimap_mode && px>=33 && px<=94 && py>=1 && py<=62;
    wire [1:0] cx = mx[1:0], cy = py[1:0];
    // Tile-local pixel 0..3; the plus is centred on (1..3, 1..3).
    wire plus = cx!=2'd0 && cy!=2'd0 && (cx==2'd2 || cy==2'd2);
    wire bar = (cx==2'd1 || cx==2'd2) && cy!=2'd0;
    wire draw_health = on_map && health_valid && tile==health_tile && plus;
    wire draw_mag = on_map && mag_valid && tile==mag_tile && bar;
    assign pixel_out = draw_health ? HEALTH : draw_mag ? MAG : pixel_in;
endmodule
