`timescale 1ns / 1ps
// In-game HUD over the first-person pixel:
//  - Wave and this player's total kills in a high-contrast header.
//  - Health: three hearts at the bottom-left (x=2,8,14; y=56..60).
//    Remaining hearts are red, lost hearts dark grey. With one heart left,
//    low_blink=1 draws the last heart grey too, so it flashes.
//  - Crosshair at the viewport centre (48,32), hidden while the map is shown;
//    red while hit_flash is set (this player's shot hit a zombie).
// With the map overlay on, everything stays left of x=32.
module hud_overlay(input wire [6:0] px, input wire [5:0] py,
    input wire minimap_mode, input wire [1:0] health, input wire low_blink,
    input wire [6:0] wave, input wire [6:0] kills, input wire hit_flash,
    input wire two_player,
    input wire [15:0] pixel_in, output reg [15:0] pixel_out);
    localparam HEART=16'hF800, HEART_LOST=16'h4208, TEXT=16'hFFFF,
               HEADER=16'h0842, WAVE_COLOUR=16'hFFE0, KILL_COLOUR=16'h87F0,
               DOWN_BG=16'h4000, DOWN_COLOUR=16'hF800, DOWN_SUB=16'hFFE0;
    wire [6:0] wv=(wave>99) ? 7'd99 : wave;
    wire [6:0] kv=(kills>99) ? 7'd99 : kills;
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
    wire [7:0] wv_digits=decimal_pair(wv), kill_digits=decimal_pair(kv);
    reg [7:0] character;
    reg [1:0] gx;
    reg [2:0] gy;
    reg [15:0] label_colour;
    reg [2:0] label_index;
    wire font_pixel;
    font3x5 font(.character(character),.gx(gx),.gy(gy),.pixel(font_pixel));
    always @* begin
        character=0; gx=0; gy=0; label_colour=WAVE_COLOUR; label_index=0;
        if(!minimap_mode && py>=2 && py<=6) begin
            gy=py-6'd2;
            if(px>=2 && px<18) begin
                label_index=(px-7'd2)>>2;
                case(label_index)
                    0: character="W"; 1: character="A"; 2: character="V"; 3: character="E";
                    default: character=0;
                endcase
                gx=(px-7'd2)&3;
            end else if(px>=22 && px<=24) begin character=8'd48+wv_digits[7:4]; gx=px-7'd22; end
            else if(px>=26 && px<=28) begin character=8'd48+wv_digits[3:0]; gx=px-7'd26; end
            else if(px>=50 && px<70) begin
                label_colour=KILL_COLOUR; label_index=(px-7'd50)>>2;
                case(label_index)
                    0: character="K"; 1: character="I"; 2: character="L";
                    3: character="L"; 4: character="S"; default: character=0;
                endcase
                gx=(px-7'd50)&3;
            end else if(px>=74 && px<=76) begin
                label_colour=KILL_COLOUR; character=8'd48+kill_digits[7:4]; gx=px-7'd74;
            end else if(px>=78 && px<=80) begin
                label_colour=KILL_COLOUR; character=8'd48+kill_digits[3:0]; gx=px-7'd78;
            end
        end else if(minimap_mode && px<32) begin
            if(py>=2 && py<=6) begin
                gy=py-6'd2;
                if(px>=2 && px<=4) begin character="W"; gx=px-7'd2; end
                else if(px>=8 && px<=10) begin character=8'd48+wv_digits[7:4]; gx=px-7'd8; end
                else if(px>=12 && px<=14) begin character=8'd48+wv_digits[3:0]; gx=px-7'd12; end
            end else if(py>=9 && py<=13) begin
                gy=py-6'd9; label_colour=KILL_COLOUR;
                if(px>=2 && px<=4) begin character="K"; gx=px-7'd2; end
                else if(px>=8 && px<=10) begin character=8'd48+kill_digits[7:4]; gx=px-7'd8; end
                else if(px>=12 && px<=14) begin character=8'd48+kill_digits[3:0]; gx=px-7'd12; end
            end
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
    wire local_down = two_player && health==2'd0;
    wire down_panel = local_down && ((!minimap_mode && px>=18 && px<=77 && py>=21 && py<=35) ||
                                     (minimap_mode && px<32 && px>=1 && px<=30 && py>=18 && py<=31));
    reg [7:0] down_character;
    reg [3:0] down_index;
    reg [6:0] down_x0;
    reg [5:0] down_y0;
    reg [15:0] down_colour;
    reg [1:0] down_gx;
    reg [2:0] down_gy;
    wire down_font_pixel;
    font3x5 down_font(.character(down_character),.gx(down_gx),.gy(down_gy),.pixel(down_font_pixel));
    always @* begin
        down_character=0; down_index=0; down_x0=0; down_y0=0; down_colour=DOWN_COLOUR;
        if(minimap_mode) begin
            if(py>=19 && py<=23 && px>=2 && px<14) begin
                down_y0=19; down_x0=2; down_index=(px-7'd2)>>2;
                case(down_index) 0: down_character="Y"; 1: down_character="O"; 2: down_character="U"; default: down_character=0; endcase
            end else if(py>=26 && py<=30 && px>=2 && px<18) begin
                down_y0=26; down_x0=2; down_index=(px-7'd2)>>2;
                case(down_index) 0: down_character="D"; 1: down_character="O"; 2: down_character="W"; 3: down_character="N"; default: down_character=0; endcase
            end
        end else if(py>=23 && py<=27 && px>=24 && px<72) begin
            down_y0=23; down_x0=24; down_index=(px-7'd24)>>2;
            case(down_index)
                0: down_character="Y"; 1: down_character="O"; 2: down_character="U";
                4: down_character="A"; 5: down_character="R"; 6: down_character="E";
                8: down_character="D"; 9: down_character="O"; 10: down_character="W"; 11: down_character="N";
                default: down_character=0;
            endcase
        end else if(py>=30 && py<=34 && px>=22 && px<74) begin
            down_y0=30; down_x0=22; down_index=(px-7'd22)>>2; down_colour=DOWN_SUB;
            case(down_index)
                0: down_character="P"; 1: down_character="A"; 2: down_character="R"; 3: down_character="T";
                4: down_character="N"; 5: down_character="E"; 6: down_character="R";
                8: down_character="A"; 9: down_character="L"; 10: down_character="I"; 11: down_character="V"; 12: down_character="E";
                default: down_character=0;
            endcase
        end
        down_gx=(px-down_x0)&7'd3;
        down_gy=py-down_y0;
    end
    always @* begin
        pixel_out=pixel_in;
        if(!minimap_mode && py<=8) pixel_out=HEADER;
        if(minimap_mode && px<32 && py<=15) pixel_out=HEADER;
        if(!minimap_mode || px<32) begin
            if(font_pixel) pixel_out=label_colour;
            if(heart_pixel) pixel_out = heart_full ? HEART : HEART_LOST;
            if(!minimap_mode && ((py==32 && px>=46 && px<=50) ||
                                (px==48 && py>=30 && py<=34))) pixel_out=hit_flash ? 16'hF800 : TEXT;
        end
        if(down_panel) pixel_out=DOWN_BG;
        if(local_down && down_panel && down_font_pixel) pixel_out=down_colour;
    end
endmodule
