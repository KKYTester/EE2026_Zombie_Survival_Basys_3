`timescale 1ns / 1ps
// Full-screen menu pixels: title (1P / 2P), generating, game over, victory.
// Purely combinational; one font3x5 lookup per pixel. Text lines never overlap,
// so the line is chosen from py and the character from px.
module menu_screens #(parameter ENABLE_2P = 0)(
    input wire [6:0] px, input wire [5:0] py,
    input wire [2:0] screen,          // 0 title, 1 generating, 2 reserved, 3 game over, 4 victory
    input wire sel,                   // 0 = 1 PLAYER, 1 = 2 PLAYERS
    input wire [6:0] cursor_x, input wire [5:0] cursor_y,
    input wire show_cursor,
    input wire [5:0] progress,        // 0..63 generating bar fill
    input wire [3:0] wave_tens, input wire [3:0] wave_ones,   // wave reached (end screens)
    input wire over_ready,            // show the retry / play-again hint
    input wire link_up,               // the other board is linked (title hint)
    input wire show_peer,             // end screens: show the other board's wave
    input wire [3:0] peer_tens, input wire [3:0] peer_ones,
    input wire peer_in_run,           // the other board is still playing
    // 2-player end screens: zombies killed by each player (two digits each).
    input wire [3:0] p1_kill_tens, input wire [3:0] p1_kill_ones,
    input wire [3:0] p2_kill_tens, input wire [3:0] p2_kill_ones,
    input wire you_are_p2,            // highlight this board's own line
    output reg [15:0] pixel);
    localparam BG=16'h0842, RED=16'hE145, WHITE=16'hEF7D, YELLOW=16'hF645,
               GREY=16'h6B6F, DARK=16'h4208, BAND=16'h2921, GROUND=16'h1162,
               GROUND_HI=16'h19E3, HINT=16'h96F2, BAR_BG=16'h39E8, BAR_FILL=16'h2EEA,
               GREEN=16'h2EEA, SKY=16'h10A6;
    // Option rows (shared with game_flow for mouse hit-testing).
    localparam OPT_X0=18, OPT_X1=77, OPT1_Y0=26, OPT1_Y1=34, OPT2_Y0=35, OPT2_Y1=43;

    reg [127:0] str;         // up to 16 characters, leftmost in the top byte
    reg [4:0] len;
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
            3'd0: begin
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
                    line_on=1; y0=57; color=HINT;
                    if(sel && !link_up) begin
                        str={"NO LINK TO P2",24'd0}; len=13; x0=22; color=GREY;
                    end else begin
                        str={"CLICK TO START",16'd0}; len=14; x0=20;
                    end
                end else if(py>=47 && py<=51 && ENABLE_2P && link_up) begin
                    line_on=1; str={"LINKED",80'd0}; len=6; x0=36; y0=47; color=GREEN;
                end
            end
            3'd1: begin
                if(py>=20 && py<=24) begin
                    line_on=1; str={"GENERATING",48'd0}; len=10; x0=28; y0=20;
                end else if(py>=28 && py<=32) begin
                    line_on=1; str={"MAP",104'd0}; len=3; x0=42; y0=28;
                end
            end
            3'd2: begin end // Reserved: the countdown screen was removed.
            3'd4: begin
                if(py>=6 && py<=15) begin
                    line_on=1; str={"YOU",104'd0}; len=3; x0=37; y0=6; shift=1; color=YELLOW;
                end else if(py>=18 && py<=27) begin
                    line_on=1; str={"SURVIVED",64'd0}; len=8; x0=17; y0=18; shift=1; color=GREEN;
                end else if(show_peer ? (py>=31 && py<=35) : (py>=36 && py<=40)) begin
                    line_on=1; y0 = show_peer ? 6'd31 : 6'd36;
                    if(wave_tens!=0) begin
                        str={8'd48+{4'd0,wave_tens},8'd48+{4'd0,wave_ones}," WAVES CLEARED"}; len=16; x0=17;
                    end else begin
                        str={8'd48+{4'd0,wave_ones}," WAVES CLEARED",8'd0}; len=15; x0=19;
                    end
                end else if(py>=38 && py<=42 && show_peer) begin
                    line_on=1; y0=38; color = you_are_p2 ? WHITE : YELLOW;
                    str={"P1 KILLS ",8'd48+{4'd0,p1_kill_tens},8'd48+{4'd0,p1_kill_ones},40'd0};
                    len=11; x0=26;
                end else if(py>=45 && py<=49 && show_peer) begin
                    line_on=1; y0=45; color = you_are_p2 ? YELLOW : WHITE;
                    str={"P2 KILLS ",8'd48+{4'd0,p2_kill_tens},8'd48+{4'd0,p2_kill_ones},40'd0};
                    len=11; x0=26;
                end else if(py>=52 && py<=56 && over_ready) begin
                    line_on=1; str={"CLICK TO PLAY",24'd0}; len=13; x0=22; y0=52; color=HINT;
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
                end else if(py>=38 && py<=42 && show_peer) begin
                    line_on=1; y0=38; color = you_are_p2 ? WHITE : YELLOW;
                    str={"P1 KILLS ",8'd48+{4'd0,p1_kill_tens},8'd48+{4'd0,p1_kill_ones},40'd0};
                    len=11; x0=26;
                end else if(py>=45 && py<=49 && show_peer) begin
                    line_on=1; y0=45; color = you_are_p2 ? YELLOW : WHITE;
                    str={"P2 KILLS ",8'd48+{4'd0,p2_kill_tens},8'd48+{4'd0,p2_kill_ones},40'd0};
                    len=11; x0=26;
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
    wire on_cursor = show_cursor && screen==3'd0 && px>=cursor_x && py>=cursor_y &&
                     cdx<4 && cdy<6 && cursor_row[3-cdx[1:0]];

    always @* begin
        pixel=BG;
        if(screen==3'd0) begin
            if(py>=54) pixel=((px+py)&2'b11)==0 ? GROUND_HI : GROUND;
            if(px>=OPT_X0 && px<=OPT_X1 &&
               ((!sel && py>=OPT1_Y0 && py<=OPT1_Y1) ||
                (sel && ENABLE_2P && py>=OPT2_Y0 && py<=OPT2_Y1))) pixel=BAND;
        end else if(screen==3'd4) begin
            // Dawn sky band behind the title, ground at the bottom.
            if(py<=30) pixel=SKY;
            if(py>=60) pixel=((px+py)&2'b11)==0 ? GROUND_HI : GROUND;
        end else if(screen==3'd1) begin
            if(px>=16 && px<=79 && py>=40 && py<=42)
                pixel = ({1'b0,px}-8'd16 < {2'b00,progress}) ? BAR_FILL : BAR_BG;
        end
        if(font_pixel) pixel=color;
        if(on_cursor) pixel=WHITE;
    end
endmodule
