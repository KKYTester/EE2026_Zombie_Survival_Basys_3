`timescale 1ns / 1ps
`include "Game_Config.vh"

module Map_Renderer #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer GAME_HZ = 24,
    // Kept for the existing timing interface; ray work runs at full clk speed.
    parameter integer PIXEL_UPDATE_HZ = 25_000_000,
    parameter [255:0] MAP = `GAME_MAP
) (
    input wire clk, reset,
    input wire [31:0] x_coord, y_coord, theta,
    output wire game_tick,
    input wire display_clk, frame_begin,
    input wire [12:0] pixel_index,
    output reg [15:0] pixel_data,
    output wire [9:0] column_depth // perpendicular depth, in 1/32-cell units
);
    localparam integer GAME_CYCLES = (CLK_HZ + GAME_HZ/2) / GAME_HZ;
    localparam integer PIXEL_CYCLES = (CLK_HZ + PIXEL_UPDATE_HZ/2) / PIXEL_UPDATE_HZ;
    localparam integer GAME_BITS = GAME_CYCLES > 1 ? $clog2(GAME_CYCLES) : 1;
    localparam integer PIXEL_BITS = PIXEL_CYCLES > 1 ? $clog2(PIXEL_CYCLES) : 1;
    localparam [GAME_BITS-1:0] GAME_LAST = GAME_CYCLES-1;
    localparam [PIXEL_BITS-1:0] PIXEL_LAST = PIXEL_CYCLES-1;
    reg [GAME_BITS-1:0] game_counter;
    reg [PIXEL_BITS-1:0] pixel_counter;
    assign game_tick = !reset && game_counter == GAME_LAST;
    wire pixel_tick = !reset && pixel_counter == PIXEL_LAST;
    always @(posedge clk) begin
        if (reset) begin
            game_counter <= 0;
            pixel_counter <= 0;
        end else begin
            game_counter <= game_tick ? 0 : game_counter + 1'b1;
            pixel_counter <= pixel_tick ? 0 : pixel_counter + 1'b1;
        end
    end

    // Bundled-data handshake: writer freezes a complete bank until display
    // acknowledges its publication. The display swaps only at frame_begin.
    // The other bank cannot be written until that acknowledgement returns.
    reg [6:0] heights [0:191];
    reg [9:0] depths [0:191];
    reg write_bank, request_toggle;
    reg front_bank, acknowledge_toggle, display_valid;
    (* ASYNC_REG = "TRUE" *) reg request_meta, request_sync;
    (* ASYNC_REG = "TRUE" *) reg acknowledge_meta, acknowledge_sync;
    always @(posedge display_clk) begin
        if (reset) begin
            request_meta <= 0;
            request_sync <= 0;
            acknowledge_toggle <= 0;
            front_bank <= 0;
            display_valid <= 0;
        end else begin
            request_meta <= request_toggle;
            request_sync <= request_meta;
            if (frame_begin && request_sync != acknowledge_toggle) begin
                front_bank <= ~front_bank;
                acknowledge_toggle <= request_sync;
                display_valid <= 1;
            end
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            acknowledge_meta <= 0;
            acknowledge_sync <= 0;
        end else begin
            acknowledge_meta <= acknowledge_toggle;
            acknowledge_sync <= acknowledge_meta;
        end
    end

    `include "Ray_Tables.vh"
    localparam [2:0] SNAPSHOT=0, LAUNCH=1, WAIT_RAY=2, PUBLISH=3, WAIT_SWAP=4, IDLE=5;
    reg [2:0] state;
    reg [6:0] column;
    reg signed [17:0] frame_x, frame_y;
    reg [9:0] frame_angle;
    wire [9:0] ray_angle = frame_angle + column_offset(column);
    wire ray_done, ray_hit, ray_busy;
    wire [6:0] ray_height;
    wire [9:0] ray_depth;
    wire ray_start = state == LAUNCH;
    wire [7:0] write_index = (write_bank ? 8'd96 : 8'd0) + {1'b0,column};
    Ray_Caster #(.MAP(MAP)) raycaster (
        .clk(clk), .reset(reset), .start(ray_start),
        .player_x(frame_x), .player_y(frame_y), .angle(ray_angle),
        .projection_cosine(column_cosine(column)),
        .busy(ray_busy), .done(ray_done), .hit(ray_hit),
        .height(ray_height), .distance_steps(), .depth_steps(ray_depth)
    );
    always @(posedge clk) begin
        if (reset) begin
            state <= SNAPSHOT; // render immediately after reset
            column <= 0;
            frame_x <= 0;
            frame_y <= 0;
            frame_angle <= 0;
            write_bank <= 1;
            request_toggle <= 0;
        end else begin
            case (state)
                SNAPSHOT: begin
                    frame_x <= $signed(x_coord[17:0]);
                    frame_y <= $signed(y_coord[17:0]);
                    frame_angle <= theta[9:0];
                    column <= 0;
                    state <= LAUNCH;
                end
                LAUNCH: state <= WAIT_RAY;
                WAIT_RAY: if (ray_done) begin
                    heights[write_index] <= ray_height;
                    depths[write_index] <= ray_depth;
                    if (column == 7'd95) state <= PUBLISH;
                    else begin
                        column <= column + 1'b1;
                        state <= LAUNCH;
                    end
                end
                PUBLISH: begin
                    request_toggle <= ~request_toggle;
                    state <= WAIT_SWAP;
                end
                WAIT_SWAP: if (acknowledge_sync == request_toggle) begin
                    write_bank <= ~write_bank;
                    state <= IDLE;
                end
                IDLE: if (game_tick) state <= SNAPSHOT;
                default: state <= SNAPSHOT;
            endcase
        end
    end

    // Continuous colour is stable before Oled_Display's falling-edge capture.
    // No system-clock sampling of pixel_index; it belongs to the OLED domain.
    wire [12:0] pixel_x_full = pixel_index % 13'd96;
    wire [12:0] pixel_y_full = pixel_index / 13'd96;
    wire [7:0] read_index = (front_bank ? 8'd96 : 8'd0) + {1'b0,pixel_x_full[6:0]};
    wire valid_pixel = pixel_index < 13'd6144;
    wire [6:0] wall_height = heights[read_index];
    wire [6:0] wall_top = (7'd64 - wall_height) >> 1;
    wire [6:0] wall_bottom = wall_top + wall_height;
    assign column_depth = display_valid && valid_pixel ? depths[read_index] : 10'h3ff;
    always @* begin
        pixel_data = 16'h0000;
        if (!reset && display_valid && valid_pixel) begin
            if (pixel_y_full < wall_top) pixel_data = 16'h18e7; // ceiling
            else if (pixel_y_full < wall_bottom) pixel_data = 16'hbdf7; // wall
            else pixel_data = 16'h3184; // floor
        end
    end
endmodule
