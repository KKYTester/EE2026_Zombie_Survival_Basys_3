`timescale 1ns / 1ps
// Cardinal demo raycaster. One sample per 1/16 tile of forward depth.
module demo_wall_view(
    input wire clk, reset, prepare, display_bank,
    input wire [255:0] map_bits,
    input wire [7:0] camera_tile,
    input wire [1:0] facing,
    input wire [6:0] pixel_x,
    output reg done,
    output reg [12:0] wall_depth,
    output reg [5:0] wall_top
);
    localparam [2:0] IDLE=0, START=1, STEP=2, SAMPLE=3, STORE=4;
    reg [2:0] state;
    reg write_bank;
    reg [255:0] walls;
    reg [7:0] origin;
    reg [1:0] direction;
    reg [6:0] column;
    reg signed [15:0] ray_x, ray_y, step_x, step_y;
    reg [7:0] distance;
    reg hit_wall;
    wire signed [15:0] lateral = $signed({9'd0,column})-16'sd48;
    wire outside_map = ray_x<0 || ray_y<0 || ray_x>=16384 || ray_y>=16384;
    wire [7:0] tile = {ray_y[13:10],ray_x[13:10]};
    reg [12:0] depths [0:255];
    reg [5:0] tops [0:255];
    reg [5:0] top_rom [0:255];
    integer i;
    initial begin
        top_rom[0]=0;
        for(i=1;i<256;i=i+1)
            top_rom[i]=(i<=16) ? 0 : 32-(512/i);
    end

    // Depth is in Q8 tile units, measured along the camera's forward axis.
    always @(posedge clk) begin
        wall_depth<=depths[{display_bank,pixel_x}];
        wall_top<=tops[{display_bank,pixel_x}];
        if(!reset && state==STORE) begin
            depths[{write_bank,column}]<=hit_wall ? {1'b0,distance,4'b0} : 13'd4096;
            tops[{write_bank,column}]<=hit_wall ? top_rom[distance] : 6'd32;
        end
    end

    always @(posedge clk) begin
        if(reset) begin state<=IDLE; done<=0; end
        else case(state)
            IDLE: if(prepare) begin
                walls<=map_bits; origin<=camera_tile; direction<=facing;
                write_bank<=!display_bank; column<=0; done<=0; state<=START;
            end
            START: begin
                // Q10 ray positions start at the center of the player tile.
                ray_x<={2'b0,origin[3:0],10'b1000000000};
                ray_y<={2'b0,origin[7:4],10'b1000000000};
                case(direction)
                    2'd0: begin step_x<=16'sd64; step_y<=lateral; end
                    2'd1: begin step_x<=-lateral; step_y<=16'sd64; end
                    2'd2: begin step_x<=-16'sd64; step_y<=-lateral; end
                    2'd3: begin step_x<=lateral; step_y<=-16'sd64; end
                endcase
                distance<=0; state<=STEP;
            end
            STEP: begin
                ray_x<=ray_x+step_x; ray_y<=ray_y+step_y;
                distance<=distance+1'b1; state<=SAMPLE;
            end
            SAMPLE: begin
                hit_wall<=!outside_map && walls[tile];
                if(outside_map || walls[tile] || distance==8'hff) state<=STORE;
                else state<=STEP;
            end
            STORE: if(column==95) begin done<=1; state<=IDLE; end
            else begin column<=column+1'b1; state<=START; end
            default: state<=IDLE;
        endcase
    end
endmodule
