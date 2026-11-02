`timescale 1ns / 1ps

module Map_Renderer (
    input clk, // system clock
    output reg [15:0] pixel_data
);
    localparam [31:0] game_clk_divider = 32'd2_083_332; // about 24fps
    localparam [31:0] pixel_data_clk_divider = 32'd1999; // 25 khz
    wire game_clk, pixel_data_clk;

    Clk_Divider Game_Clk_Divider(
        .clk     (clk     ),
        .divider (game_clk_divider),
        .clk_out (game_clk )
    );

    Clk_Divider Pixel_Data_Clk_Divider(
        .clk     (clk     ),
        .divider (pixel_data_clk_divider),
        .clk_out (pixel_data_clk )
    );

    reg [31:0] dx = 32'd0;
    reg [31:0] dy = 32'd0;
    reg [31:0] omega = 32'd0;
    wire [31:0] x_coord = 32'd0;
    wire [31:0] y_coord = 32'd0;
    wire [31:0] theta = 32'd0;
    Player Player_one(
        .game_clk (game_clk ),
        .dx       (dx       ),
        .dy       (dy       ),
        .omega    (omega),
        .x_coord  (x_coord  ),
        .y_coord  (y_coord  ),
        .theta    (theta)
    );
    
    localparam [255:0] MAP = {
        16'b1111111111111111,
        {14{16'b1000000000000001}},
        16'b1111111111111111
    };

    always @(posedge pixel_data_clk) begin
        // TODO: Render map with 2d raytracing logic
        


    end

endmodule