`timescale 1ns / 1ps
// In-game HUD over the first-person pixel:
//  - Wave: "W" and two digits at the top-left; zombies left in the wave: "Z" and two digits below.
//  - Health: three hearts at the bottom-left (x=2,8,14; y=56..60).
//    Remaining hearts are red, lost hearts dark grey. With one heart left,
//    low_blink=1 draws the last heart grey too, so it flashes.
//  - Crosshair at the viewport centre (48,32), hidden while the map is shown.
// With the map overlay on, everything stays left of x=32.
module hud_overlay(input wire [6:0] px, input wire [5:0] py,
    input wire minimap_mode, input wire [1:0] health, input wire low_blink,
    input wire [6:0] wave, input wire [6:0] zombies,
    input wire [15:0] pixel_in, output reg [15:0] pixel_out);
    localparam HEART=16'hF800, HEART_LOST=16'h4208, TEXT=16'hFFFF;
    wire [6:0] wv=(wave>99) ? 7'd99 : wave;
    function [7:0] decimal_pair;
        input [6:0] v;
        reg [3:0] tens;
        reg [6:0] ones;
        begin
            if(v>=90) begin tens=9; ones=v-90; end
            else if(v>=80) begin tens=8; ones=v-80; end
            else if(v>=70) begin tens=7; ones=v-70; end
            else if(v>=60) begin tens=6; ones=v-60; end
            else if(v>=50) begin tens=5; ones=v-50; end
            else if(v>=40) begin tens=4; ones=v-40; end
            else if(v>=30) begin tens=3; ones=v-30; end
            else if(v>=20) begin tens=2; ones=v-20; end
            else if(v>=10) begin tens=1; ones=v-10; end
            else begin tens=0; ones=v; end
            decimal_pair={tens,ones[3:0]};
        end
    endfunction
    wire [6:0] zb=(zombies>99) ? 7'd99 : zombies;
    wire [7:0] wv_digits=decimal_pair(wv), zb_digits=decimal_pair(zb);
    reg [7:0] character;
    reg [1:0] gx;
    reg [2:0] gy;
    wire font_pixel;
    font3x5 font(.character(character),.gx(gx),.gy(gy),.pixel(font_pixel));
    always @* begin
        character=0; gx=0; gy=0;
        if(py>=2 && py<=6) begin
            gy=py-6'd2;
            if(px>=2 && px<=4) begin character="W"; gx=px-7'd2; end
            else if(px>=8 && px<=10) begin character=8'd48+wv_digits[7:4]; gx=px-7'd8; end
            else if(px>=12 && px<=14) begin character=8'd48+wv_digits[3:0]; gx=px-7'd12; end
        end else if(py>=9 && py<=13) begin
            gy=py-6'd9;
            if(px>=2 && px<=4) begin character="Z"; gx=px-7'd2; end
            else if(px>=8 && px<=10) begin character=8'd48+zb_digits[7:4]; gx=px-7'd8; end
            else if(px>=12 && px<=14) begin character=8'd48+zb_digits[3:0]; gx=px-7'd12; end
        end
    end
    // 5x5 heart bitmap, row 0 at the top, bit 4 = leftmost column.
    reg [4:0] heart_row;
    always @* begin
        case(py)
            56: heart_row=5'b01010; 57: heart_row=5'b11111; 58: heart_row=5'b11111;
            59: heart_row=5'b01110; 60: heart_row=5'b00100;
            default: heart_row=5'b00000;
        endcase
    end
    reg [1:0] heart_index;
    reg [2:0] heart_col;
    reg in_heart;
    always @* begin
        in_heart=0; heart_index=0; heart_col=0;
        if(px>=2 && px<=6) begin in_heart=1; heart_index=0; heart_col=px-7'd2; end
        else if(px>=8 && px<=12) begin in_heart=1; heart_index=1; heart_col=px-7'd8; end
        else if(px>=14 && px<=18) begin in_heart=1; heart_index=2; heart_col=px-7'd14; end
    end
    wire heart_pixel = in_heart && heart_row[3'd4-heart_col];
    wire heart_full = (heart_index < health) && !(health==2'd1 && low_blink);
    always @* begin
        pixel_out=pixel_in;
        if(!minimap_mode || px<32) begin
            if(font_pixel) pixel_out=TEXT;
            if(heart_pixel) pixel_out = heart_full ? HEART : HEART_LOST;
            if(!minimap_mode && ((py==32 && px>=46 && px<=50) ||
                                (px==48 && py>=30 && py<=34))) pixel_out=TEXT;
        end
    end
endmodule
