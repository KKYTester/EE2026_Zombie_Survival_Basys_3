`timescale 1ns / 1ps
// Draws zombies as red 2x2 dots on the 64x64 map overlay (x=32..95, 4 px per tile),
// the same size and position as the player spawn dots. Combinational.
module zombie_overlay #(parameter USE_FRACTIONAL_POSITIONS=0)(
    input wire [6:0] px, input wire [5:0] py,
    input wire [7:0] active,
    input wire [95:0] position_x, position_y,
    input wire minimap_mode, input wire [255:0] zombies,
    input wire [15:0] pixel_in, output wire [15:0] pixel_out);
    wire [6:0] mx = px - 7'd32;
    wire [7:0] tile = {py[5:2], mx[5:2]};
    wire inner = (mx[1:0]==2'd1 || mx[1:0]==2'd2) && (py[1:0]==2'd1 || py[1:0]==2'd2);
    wire on_map = minimap_mode && px>=33 && px<=94 && py>=1 && py<=62;
    wire [7:0] dots;
    genvar slot;
    generate for(slot=0;slot<8;slot=slot+1) begin : g_dots
        // Four pixels per tile. Q8 positions drop six fractional bits.
        wire [6:0] dot_x = 7'd32+{1'b0,position_x[12*slot+6+:6]};
        wire [6:0] dot_y = {1'b0,position_y[12*slot+6+:6]};
        assign dots[slot]=active[slot] && (px==dot_x || px+7'd1==dot_x) &&
                         ({1'b0,py}==dot_y || {1'b0,py}+7'd1==dot_y);
    end endgenerate
    wire draw_dot = USE_FRACTIONAL_POSITIONS ? |dots : inner && zombies[tile];
    assign pixel_out = (on_map && draw_dot) ? 16'hF800 : pixel_in;
endmodule
