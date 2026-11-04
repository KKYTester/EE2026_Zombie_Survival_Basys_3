`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: 
//  STUDENT B NAME:
//  STUDENT C NAME: 
//  STUDENT D NAME:  
//////////////////////////////////////////////////////////////////////////////////

module My_Top_Module (input clk, output [7:0] JB);
    wire clk_6p25mhz;
    // Hold reset for 255 system-clock cycles after FPGA configuration, long
    // enough to also be sampled by the existing 6.25 MHz OLED interface clock.
    reg [7:0] startup_counter = 8'd0;
    wire reset = (startup_counter != 8'hff);
    always @(posedge clk) begin
        if (reset)
            startup_counter <= startup_counter + 1'b1;
    end
    wire frame_begin, sending_pixels, sample_pixel;
    wire [12:0] pixel_index;
    wire [15:0] pixel_data;
    assign JB[2] = 1'b0; // unused OLED header pin

    localparam divider_6p25mhz = 32'd7;
    Clk_Divider u_Clk_Divider (
        .clk            (clk),
        .divider (divider_6p25mhz),
        .clk_out    (clk_6p25mhz)
    );

    Oled_Display u_Oled_Display(
        .clk            (clk_6p25mhz    ),
        .reset          (reset          ),
        .frame_begin    (frame_begin    ),
        .sending_pixels (sending_pixels ),
        .sample_pixel   (sample_pixel   ),
        .pixel_index    (pixel_index    ),
        .pixel_data     (pixel_data     ),
        .cs             (JB[0]             ),
        .sdin           (JB[1]           ),
        .sclk           (JB[3]           ),
        .d_cn           (JB[4]           ),
        .resn           (JB[5]           ),
        .vccen          (JB[6]          ),
        .pmoden         (JB[7]         )
    );

    Map_Renderer u_Map_Renderer(
        .clk        (clk        ),
        .reset      (reset      ),
        .display_clk(clk_6p25mhz),
        .frame_begin(frame_begin),
        .pixel_index(pixel_index),
        .pixel_data (pixel_data),
        .column_depth()
    );
    
    // TODO: Some kind of game state manager 
    // TODO: Game state manager has to choose which modules pixel_data to use


endmodule
