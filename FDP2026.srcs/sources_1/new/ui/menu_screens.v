`timescale 1ns / 1ps
// Full-screen menu pixels: title (1P / 2P), generating, countdown, game over.
// Purely combinational; one font3x5 lookup per pixel. Text lines never overlap,
// so the line is chosen from py and the character from px.
module menu_screens #(parameter ENABLE_2P = 0)(
    input wire [6:0] px, input wire [5:0] py,
    input wire [1:0] screen,          // 0 title, 1 generating, 2 countdown, 3 game over
    input wire sel,                   // 0 = 1 PLAYER, 1 = 2 PLAYERS
    input wire [6:0] cursor_x, input wire [5:0] cursor_y,
    input wire show_cursor,
    input wire [1:0] count_digit,     // 3, 2, 1
    input wire [5:0] progress,        // 0..63 generating bar fill
    input wire [3:0] wave_tens, input wire [3:0] wave_ones,   // wave reached (game over)
    input wire over_ready,            // show the retry hint
    output reg [15:0] pixel);
    localparam BG=16'h0842, RED=16'hE145, WHITE=16'hEF7D, YELLOW=16'hF645,
               GREY=16'h6B6F, DARK=16'h4208, BAND=16'h2921, GROUND=16'h1162,
               GROUND_HI=16'h19E3, HINT=16'h96F2, BAR_BG=16'h39E8, BAR_FILL=16'h2EEA;
    // Option rows (shared with game_flow for mouse hit-testing).
    localparam OPT_X0=18, OPT_X1=77, OPT1_Y0=26, OPT1_Y1=34, OPT2_Y0=35, OPT2_Y1=43;

    reg [127:0] str;         // up to 16 characters, leftmost in the top byte
    reg [3:0] len;
    reg [6:0] x0;
    reg [5:0] y0;
    reg [1:0] shift;         // scale = 1 << shift
    reg [15:0] color;
    reg line_on;
    reg [7:0] character;
    reg [1:0] gx;
    reg [2:0] gy;
    wire font_pixel;
    font3x5 font(.character(character),.gx(gx),.gy(gy),.pixel(font_pixel));

    wire [6:0] rel_x = px - x0;
    wire [5:0] rel_y = py - y0;
    wire [6:0] sx = rel_x >> shift;
    wire [4:0] char_index = sx[6:2];
    wire [127:0] shifted = str << {char_index, 3'b000};

    always @* begin
        str=0; len=0; x0=0; y0=0; shift=0; color=WHITE; line_on=0;
        case(screen)
            2'd0: begin
                if(py>=3 && py<=12) begin
                    line_on=1; str={"ZOMBIE",80'd0}; len=6; x0=25; y0=3; shift=1; color=RED;
                end else if(py>=16 && py<=20) begin
                    line_on=1; str={"SURVIVAL",64'd0}; len=8; x0=32; y0=16;
                end else if(py>=28 && py<=32) begin
                    line_on=1; len=10; x0=21; y0=28;
                    str = sel ? {"  1 PLAYER",48'd0} : {"> 1 PLAYER",48'd0};
                    color = sel ? GREY : YELLOW;
                end else if(py>=37 && py<=41) begin
                    line_on=1; len=11; x0=21; y0=37;
                    str = sel ? {"> 2 PLAYERS",40'd0} : {"  2 PLAYERS",40'd0};
                    color = !ENABLE_2P ? DARK : (sel ? YELLOW : GREY);
                end else if(py>=57 && py<=61) begin
                    line_on=1; str={"CLICK TO START",16'd0}; len=14; x0=20; y0=57; color=HINT;
                end
            end
            2'd1: begin
                if(py>=20 && py<=24) begin
                    line_on=1; str={"GENERATING",48'd0}; len=10; x0=28; y0=20;
                end else if(py>=28 && py<=32) begin
                    line_on=1; str={"MAP",104'd0}; len=3; x0=42; y0=28;
                end
            end
            2'd2: begin
                if(py>=14 && py<=33) begin
                    line_on=1; str={8'd48+{6'd0,count_digit},120'd0}; len=1;
                    x0=42; y0=14; shift=2; color=YELLOW;
                end else if(py>=44 && py<=48) begin
                    line_on=1; str={"GET READY",56'd0}; len=9; x0=30; y0=44;
                end
            end
            default: begin
                if(py>=10 && py<=19) begin
                    line_on=1; str={"GAME OVER",56'd0}; len=9; x0=13; y0=10; shift=1; color=RED;
                end else if(py>=30 && py<=34) begin
                    line_on=1; y0=30;
                    if(wave_tens!=0) begin
                        str={"WAVE ",8'd48+{4'd0,wave_tens},8'd48+{4'd0,wave_ones},72'd0}; len=7; x0=35;
                    end else begin
                        str={"WAVE ",8'd48+{4'd0,wave_ones},80'd0}; len=6; x0=37;
                    end
                end else if(py>=52 && py<=56 && over_ready) begin
                    line_on=1; str={"CLICK TO RETRY",16'd0}; len=14; x0=20; y0=52; color=HINT;
                end
            end
        endcase
    end

    always @* begin
        character=0; gx=0; gy=0;
        if(line_on && px>=x0 && char_index<len) begin
            character=shifted[127:120];
            gx=sx[1:0];
            gy=rel_y >> shift;
        end
    end

    // Mouse arrow, 4x6 pixels, hot spot at its top-left tip.
    wire [6:0] cdx = px - cursor_x;
    wire [5:0] cdy = py - cursor_y;
    reg [3:0] cursor_row;
    always @* begin
        case(cdy)
            0: cursor_row=4'b1000; 1: cursor_row=4'b1100; 2: cursor_row=4'b1110;
            3: cursor_row=4'b1111; 4: cursor_row=4'b0110; 5: cursor_row=4'b0011;
            default: cursor_row=4'b0000;
        endcase
    end
    wire on_cursor = show_cursor && screen==2'd0 && px>=cursor_x && py>=cursor_y &&
                     cdx<4 && cdy<6 && cursor_row[3-cdx[1:0]];

    always @* begin
        pixel=BG;
        if(screen==2'd0) begin
            if(py>=54) pixel=((px+py)&2'b11)==0 ? GROUND_HI : GROUND;
            if(px>=OPT_X0 && px<=OPT_X1 &&
               ((!sel && py>=OPT1_Y0 && py<=OPT1_Y1) ||
                (sel && ENABLE_2P && py>=OPT2_Y0 && py<=OPT2_Y1))) pixel=BAND;
        end else if(screen==2'd1) begin
            if(px>=16 && px<=79 && py>=40 && py<=42)
                pixel = ({1'b0,px}-8'd16 < {2'b00,progress}) ? BAR_FILL : BAR_BG;
        end
        if(font_pixel) pixel=color;
        if(on_cursor) pixel=WHITE;
    end
endmodule
