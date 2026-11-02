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
    wire reset;
    wire frame_begin, sending_pixels, sample_pixel;
    wire [12:0] pixel_index;
    reg [15:0] pixel_data = 15'b00000_111111_11111;

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



endmodule
