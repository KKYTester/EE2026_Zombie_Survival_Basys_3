`timescale 1ns / 1ps
module hud_overlay(input wire [6:0] px, input wire [5:0] py,
    input wire minimap_mode, input wire [6:0] health,wave,
    input wire [15:0] pixel_in, output reg [15:0] pixel_out);
    wire [6:0] hp=(health>99) ? 7'd99 : health;
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
    wire [7:0] hp_digits=decimal_pair(hp),wv_digits=decimal_pair(wv);
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
        end else if(py>=51 && py<=55) begin
            gy=py-6'd51;
            if(px>=2 && px<=4) begin character="H"; gx=px-7'd2; end
            else if(px>=6 && px<=8) begin character="P"; gx=px-7'd6; end
            else if(px>=12 && px<=14) begin character=8'd48+hp_digits[7:4]; gx=px-7'd12; end
            else if(px>=16 && px<=18) begin character=8'd48+hp_digits[3:0]; gx=px-7'd16; end
        end
    end
    always @* begin
        pixel_out=pixel_in;
        // Reserve the entire zoom-map footprint when the overlay is enabled.
        if(!minimap_mode || px<32) begin
            if(font_pixel) pixel_out=16'hFFFF;
            if(px>=2 && px<=26 && py>=58 && py<=60) begin
                pixel_out=16'h4208;
                if(px-7'd2 < {2'b00,hp[6:2]})
                    pixel_out=(hp<25) ? 16'hF800 : 16'h07E0;
            end
            if(!minimap_mode && ((py==32 && px>=46 && px<=50) ||
                                (px==48 && py>=30 && py<=34))) pixel_out=16'hFFFF;
        end
    end
endmodule
