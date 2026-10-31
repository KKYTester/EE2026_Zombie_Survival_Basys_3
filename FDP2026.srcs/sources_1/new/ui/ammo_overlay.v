`timescale 1ns / 1ps
// Ammo HUD at the bottom-right of the play view, drawn after hud_overlay:
//  - six bullets at x = 83, 85, ..., 93 (one pixel wide): tip on row 56,
//    case on rows 57..60. Loaded rounds are brass, spent rounds dark grey;
//    rounds are used from the right, so the loaded ones stay on the left.
//  - "RELOAD" in small text above them (x=72..94, y=49..53) while reloading.
// Hidden when show=0 (map overlay on). Purely combinational.
module ammo_overlay(input wire [6:0] px, input wire [5:0] py,
    input wire show, input wire [2:0] ammo, input wire reloading,
    input wire [15:0] pixel_in, output reg [15:0] pixel_out);
    localparam BRASS=16'hF645, TIP=16'hFF9A, SPENT=16'h4208, TEXT=16'hFC62;
    localparam BX0=83, BY_TIP=56, BY1=60, TX0=72, TY0=49;
    wire [6:0] bx = px - BX0;
    wire in_bullet = px>=BX0 && px<=BX0+10 && !bx[0] && py>=BY_TIP && py<=BY1;
    wire [2:0] bullet = bx[3:1];                    // 0..5, left to right
    wire loaded = bullet < ammo;
    wire [6:0] tx = px - TX0;
    wire [2:0] char_index = tx[4:2];
    reg [7:0] character;
    always @* begin
        case(char_index)
            0: character="R"; 1: character="E"; 2: character="L";
            3: character="O"; 4: character="A"; 5: character="D";
            default: character=8'd0;
        endcase
        if(!(reloading && px>=TX0 && px<TX0+24 && py>=TY0 && py<TY0+5)) character=8'd0;
    end
    wire [5:0] ty = py - TY0;
    wire font_pixel;
    font3x5 font(.character(character),.gx(tx[1:0]),.gy(ty[2:0]),.pixel(font_pixel));
    always @* begin
        pixel_out=pixel_in;
        if(show) begin
            if(in_bullet) pixel_out = !loaded ? SPENT : (py==BY_TIP ? TIP : BRASS);
            if(font_pixel) pixel_out=TEXT;
        end
    end
endmodule
