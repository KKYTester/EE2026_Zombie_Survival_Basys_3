`timescale 1ns / 1ps

module Map_Renderer #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer GAME_HZ = 24,
    parameter integer PIXEL_UPDATE_HZ = 25_000_000
) (
    input clk, // system clock
    input reset, // synchronous active-high reset
    output reg [15:0] pixel_data
);
    // Positive rates <= CLK_HZ are required. Round periods to the nearest cycle.
    // Defaults: game update every 4,166,667 cycles; pixel work every 4,000.
    localparam integer GAME_CYCLES = (CLK_HZ + GAME_HZ / 2) / GAME_HZ;
    localparam integer PIXEL_CYCLES =
        (CLK_HZ + PIXEL_UPDATE_HZ / 2) / PIXEL_UPDATE_HZ;
    localparam integer GAME_COUNTER_BITS =
        (GAME_CYCLES > 1) ? $clog2(GAME_CYCLES) : 1;
    localparam integer PIXEL_COUNTER_BITS =
        (PIXEL_CYCLES > 1) ? $clog2(PIXEL_CYCLES) : 1;
    localparam [GAME_COUNTER_BITS-1:0] GAME_LAST = GAME_CYCLES - 1;
    localparam [PIXEL_COUNTER_BITS-1:0] PIXEL_LAST = PIXEL_CYCLES - 1;
    reg [GAME_COUNTER_BITS-1:0] game_counter = 0;
    reg [PIXEL_COUNTER_BITS-1:0] pixel_counter = 0;
    wire game_tick = !reset && (game_counter == GAME_LAST);
    wire pixel_tick = !reset && (pixel_counter == PIXEL_LAST);

    always @(posedge clk) begin
        if (reset) begin
            game_counter <= 0;
            pixel_counter <= 0;
        end else begin
            if (game_tick)
                game_counter <= 0;
            else
                game_counter <= game_counter + 1'b1;

            if (pixel_tick)
                pixel_counter <= 0;
            else
                pixel_counter <= pixel_counter + 1'b1;
        end
    end

    reg [31:0] dx = 32'd0;
    reg [31:0] dy = 32'd0;
    reg [31:0] omega = 32'd0;
    wire [31:0] x_coord, y_coord, theta;
    Player Player_one(
        .reset    (reset),
        .clk      (clk),
        .game_tick(game_tick),
        .dx       (dx       ),
        .dy       (dy       ),
        .omega    (omega),
        .x_coord  (x_coord  ),
        .y_coord  (y_coord  ),
        .theta    (theta)
    );
    
    // Placeholder fixed map
    // TODO: Change to a random map generator eventually
    localparam [255:0] MAP = {
        16'b1111111111111111,
        {14{16'b1000000000000001}},
        16'b1111111111111111
    };

    always @(posedge clk) begin
        if (reset)
            pixel_data <= 16'd0;
        else if (pixel_tick) begin
            // TODO: Render map with 2d raycasting logic.
        end
    end

endmodule
