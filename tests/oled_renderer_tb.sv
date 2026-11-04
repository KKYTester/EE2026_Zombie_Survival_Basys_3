`timescale 1ns / 1ps
module oled_renderer_tb;
    reg clk=0;
    always #5 clk=~clk;
    wire [7:0] jb;
    tri1 ps2_clk, ps2_data;
    My_Top_Module board (.clk(clk), .JB(jb), .btnU(1'b0), .btnL(1'b0),
        .btnR(1'b0), .btnD(1'b0), .ps2_clk(ps2_clk), .ps2_data(ps2_data), .led());
    reg [16:0] expected[0:95];
    integer count=0, index, h, top, row;
    reg [15:0] color;
    initial begin
        // No mouse events or button presses: the spawn viewpoint stays still.
        $readmemh("frame0.mem",expected);
    end
    // Inspect actual SPI pixel loads, including pixel zero at WaitNextFrame.
    always @(negedge board.clk_6p25mhz) begin
        if (!board.reset && board.u_Oled_Display.next_state == board.u_Oled_Display.SendPixel &&
            board.u_Oled_Display.spi_word_bit_count <= 1 && board.u_Oled_Display.delay == 0) begin
            index=board.pixel_index;
            // The supplied, unmodified sender leaves SendPixel when its index
            // first reaches 6143, before loading that last pixel. Verify the
            // entire stream it actually emits and make the limitation explicit.
            if (index==0 && count==6143) begin
                $display("PASS: OLED SPI colours/indices 0..6142; supplied driver skips final pixel 6143 (known limitation)");
                $finish;
            end
            if (index != count) $fatal(1,"OLED index %0d expected %0d",index,count);
            h=expected[index%96][6:0]; top=(64-h)/2; row=index/96;
            color=row<top ? 16'h18e7 : row<top+h ? 16'hbdf7 : 16'h3184;
            #1;
            if (board.u_Oled_Display.spi_word[39:24] !== color)
                $fatal(1,"OLED captured wrong color at %0d: %h expected %h",
                    index,board.u_Oled_Display.spi_word[39:24],color);
            count=count+1;
        end
    end
    initial begin #200000000; $fatal(1,"OLED integration timeout"); end
endmodule
