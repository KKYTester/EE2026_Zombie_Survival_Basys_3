`timescale 1ns / 1ps
// Test-only integer oracle: no dependency on hud_overlay or font3x5.
module hud_reference(input wire [6:0] px, input wire [5:0] py,
    input wire minimap_mode, input wire [6:0] health,wave,
    input wire [15:0] pixel_in, output reg [15:0] expected);
    integer h,w,x,y;
    function glyph_at;
        input integer id,ox,oy,xx,yy;
        reg [14:0] bitmap;
        begin
            case(id)
                0: bitmap=15'b111101101101111;
                1: bitmap=15'b010110010010111;
                2: bitmap=15'b111001111100111;
                3: bitmap=15'b111001111001111;
                4: bitmap=15'b101101111001001;
                5: bitmap=15'b111100111001111;
                6: bitmap=15'b111100111101111;
                7: bitmap=15'b111001010010010;
                8: bitmap=15'b111101111101111;
                9: bitmap=15'b111101111001111;
                10: bitmap=15'b101101111101101;
                11: bitmap=15'b101101101111101;
                12: bitmap=15'b110101110100100;
                default: bitmap=0;
            endcase
            glyph_at=0;
            if(xx>=ox && xx<ox+3 && yy>=oy && yy<oy+5)
                glyph_at=bitmap[14-((yy-oy)*3+xx-ox)];
        end
    endfunction
    always @* begin
        h=health; if(h>99) h=99;
        w=wave; if(w>99) w=99;
        x=px; y=py; expected=pixel_in;
        if(!minimap_mode || x<32) begin
            if(glyph_at(11,2,2,x,y) || glyph_at(w/10,8,2,x,y) || glyph_at(w%10,12,2,x,y) ||
               glyph_at(10,2,51,x,y) || glyph_at(12,6,51,x,y) ||
               glyph_at(h/10,12,51,x,y) || glyph_at(h%10,16,51,x,y)) expected=16'hFFFF;
            if(x>=2 && x<=26 && y>=58 && y<=60) begin
                expected=16'h4208;
                if(x<2+h/4) expected=(h<25) ? 16'hF800 : 16'h07E0;
            end
            if(!minimap_mode && ((x==48 && y>=30 && y<=34) ||
                                 (y==32 && x>=46 && x<=50))) expected=16'hFFFF;
        end
    end
endmodule
