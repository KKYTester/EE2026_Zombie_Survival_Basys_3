`timescale 1ns / 1ps
// Effects drawn over the finished play view (after HUD and map overlay):
//  - banner: "WAVE n" at 2x size across the middle, on a dark band;
//    with clear=1 it reads "WAVE CLEAR" instead.
//  - tint:   damage flash, every pixel pushed towards red.
// Purely combinational.
module play_effects(input wire [6:0] px, input wire [5:0] py,
    input wire [15:0] pixel_in, input wire tint, input wire banner, input wire clear,
    input wire [3:0] wave_tens, input wire [3:0] wave_ones,
    output reg [15:0] pixel_out);
    localparam BAND=16'h0842, TEXT=16'hF645;
    localparam Y0=24;                       // text rows 24..33 (5 rows x 2)
    wire two_digits = wave_tens!=0;
    wire [6:0] x0 = clear ? 7'd9 : (two_digits ? 7'd21 : 7'd25);
    wire [6:0] width = clear ? 7'd78 : (two_digits ? 7'd54 : 7'd46);
    wire [6:0] rel_x = px - x0;
    wire [5:0] rel_y = py - Y0;
    wire [6:0] sx = rel_x >> 1;
    wire [4:0] char_index = sx[6:2];
    reg [7:0] character;
    always @* begin
        case(char_index)
            0: character="W"; 1: character="A"; 2: character="V"; 3: character="E";
            4: character=" ";
            5: character = clear ? "C" : (two_digits ? 8'd48+wave_tens : 8'd48+wave_ones);
            6: character = clear ? "L" : (two_digits ? 8'd48+wave_ones : 8'd0);
            7: character = clear ? "E" : 8'd0;
            8: character = clear ? "A" : 8'd0;
            9: character = clear ? "R" : 8'd0;
            default: character=8'd0;
        endcase
    end
    wire font_pixel;
    font3x5 font(.character((px>=x0 && py>=Y0 && py<=Y0+9) ? character : 8'd0),
        .gx(sx[1:0]),.gy(rel_y[3:1]),.pixel(font_pixel));
    wire in_band = py>=Y0-2 && py<=Y0+11 && px+7'd3>=x0 && px<=x0+width+7'd2;
    reg [15:0] p;
    always @* begin
        p=pixel_in;
        if((banner || clear) && in_band) p = font_pixel ? TEXT : BAND;
        pixel_out=p;
        if(tint) pixel_out={{1'b0,p[15:12]}+5'd16, 1'b0, p[10:6], 1'b0, p[4:1]};
    end
endmodule
