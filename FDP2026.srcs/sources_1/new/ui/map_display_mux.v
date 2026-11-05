`timescale 1ns / 1ps
module map_display_mux(
    input wire [6:0] px, input wire [5:0] py,
    input wire minimap_mode, input wire [15:0] fp_pixel_data,
    input wire [255:0] map_bits, input wire [7:0] p1_addr,p2_addr,
    input wire [15:0] seed, input wire map_ready,busy,bfs_enabled,
    input wire [2:0] error_code, output reg [15:0] pixel_data);
    // Status ports retained for interface compatibility and a future HUD.
    localparam WALL=16'h4AD1, FLOOR=16'h0841, GREEN=16'h07E0,
               YELLOW=16'hFFE0, WHITE=16'hFFFF, BLACK=16'h0000;
    // 64x64 whole-map zoom at x=32..95, y=0..63: four pixels per tile.
    // A one-pixel inset outline preserves the 64-pixel screen height.
    wire [6:0] mx=px-7'd32;
    wire [7:0] mini_addr={py[5:2],mx[5:2]};
    always @* begin
        pixel_data=fp_pixel_data;
        if(minimap_mode && px>=32 && px<=95) begin
            if(px==32 || px==95 || py==0 || py==63) pixel_data=WHITE;
            else if(!map_ready) pixel_data=BLACK;
            else begin
                pixel_data=map_bits[mini_addr] ? WALL : FLOOR;
                if(mini_addr==p1_addr) pixel_data=GREEN;
                else if(mini_addr==p2_addr) pixel_data=YELLOW;
            end
        end
    end
endmodule
