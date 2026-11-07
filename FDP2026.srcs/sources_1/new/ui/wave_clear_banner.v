`timescale 1ns / 1ps
// "WAVE CLEAR" banner that sweeps down the play view between waves.
// Text: font3x5 at double size (6x10 per letter, 8 px pitch), yellow, 78 px
// wide starting at x=9, on a darkened band two rows taller each side.
// top is the signed row of the first text row (-12 = just above the screen,
// 64 = gone below it); game_core moves it down at a steady rate.
module wave_clear_banner(input wire [6:0] px, input wire [5:0] py,
    input wire show, input wire signed [7:0] top,
    input wire [15:0] pixel_in, output reg [15:0] pixel_out);
    localparam TEXT=16'hFFE0, X0=9, LETTERS=10;
    wire signed [8:0] rel_y = $signed({3'd0,py}) - $signed({top[7],top});
    wire [6:0] rel_x = px - X0;
    wire in_band = show && rel_y >= -9'sd2 && rel_y <= 9'sd11;
    wire in_text_rows = rel_y >= 0 && rel_y <= 9'sd9;
    wire [3:0] letter = rel_x[6:3];
    wire [2:0] col = rel_x[2:0];
    reg [7:0] character;
    always @* begin
        case(letter)
            0: character="W"; 1: character="A"; 2: character="V"; 3: character="E";
            5: character="C"; 6: character="L"; 7: character="E"; 8: character="A";
            9: character="R"; default: character=" ";
        endcase
    end
    wire font_pixel;
    font3x5 font(.character(character),.gx(col[2:1]),.gy(rel_y[3:1]),.pixel(font_pixel));
    wire text_on = in_text_rows && px >= X0 && rel_x < 8*LETTERS && col < 3'd6 && font_pixel;
    always @* begin
        pixel_out = pixel_in;
        if(in_band) begin
            // Darken the background (halve each colour channel) for contrast.
            pixel_out = {1'b0,pixel_in[15:12],1'b0,pixel_in[10:6],1'b0,pixel_in[4:1]};
            if(text_on) pixel_out = TEXT;
        end
    end
endmodule
