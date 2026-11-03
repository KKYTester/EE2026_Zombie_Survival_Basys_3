`timescale 1ns / 1ps
// Build a 16x16 map by repeatedly dividing a rectangular floor region.
// Each division draws one wall with one or two doors, then puts the two
// smaller regions on a stack. One tile is written per clock.
//
// Tile addresses are {y[3:0], x[3:0]}; write_wall=1 means wall, 0 means floor.
// The sequence is:
//   initialise -> pop region -> choose wall -> choose doors -> draw -> push
// Repeat until the stack is empty, then pulse done for one clock.
//
// Rules preserved from the original generator:
// - Before symmetry: even walls and odd doors; maximum division depth 4.
// - Small rooms may stop from depth 2; a second door must be >=4 tiles away.
// - Seed bits select the final map's reflection/transpose.
// - FIXED_MAP bypasses division and writes the original test map instead.
module map_generator #(parameter FIXED_MAP = 0)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [15:0] seed,
    output wire       write_en,
    output wire [7:0] write_addr,
    output wire       write_wall,
    output wire       busy,
    output reg        done
);
    // These constants describe the existing 16x16 design, not new parameters.
    localparam [3:0] EDGE = 4'd15;
    localparam [3:0] INTERIOR_FIRST = 4'd1;
    localparam [3:0] INTERIOR_LAST = 4'd14;
    localparam [7:0] LAST_TILE = 8'hFF;
    localparam STACK_CAPACITY = 8;
    localparam MAX_DEPTH = 4;
    localparam EARLY_STOP_DEPTH = 2;
    localparam [4:0] SMALL_ROOM_SPAN = 5'd9; // inclusive side length <=10
    localparam [4:0] MIN_DOOR_SEPARATION = 5'd4;

    localparam [3:0] S_IDLE      = 4'd0;
    localparam [3:0] S_INIT      = 4'd1;
    localparam [3:0] S_POP       = 4'd2;
    localparam [3:0] S_ORIENT    = 4'd3;
    localparam [3:0] S_WALL      = 4'd4;
    localparam [3:0] S_DOOR_INIT = 4'd5;
    localparam [3:0] S_DOOR      = 4'd6;
    localparam [3:0] S_DRAW_INIT = 4'd7;
    localparam [3:0] S_DRAW      = 4'd8;
    localparam [3:0] S_PUSH      = 4'd9;

    // Current region: inclusive bounds of its floor area.
    reg [3:0] region_x_min, region_y_min, region_x_max, region_y_max;
    reg [2:0] region_depth;
    reg [3:0] state;
    reg [7:0] initial_tile;

    // Stack entries have the same bounds and depth as the current region.
    // stack_size is the number of entries; the top entry is stack_size-1.
    // Depth-first traversal at depth 4 uses at most 5 of the 8 entries.
    reg [3:0] stack_x_min [0:STACK_CAPACITY-1];
    reg [3:0] stack_y_min [0:STACK_CAPACITY-1];
    reg [3:0] stack_x_max [0:STACK_CAPACITY-1];
    reg [3:0] stack_y_max [0:STACK_CAPACITY-1];
    reg [2:0] stack_depth [0:STACK_CAPACITY-1];
    reg [3:0] stack_size;

    // vertical_wall=1: fixed x, draw along y. Otherwise fixed y, draw along x.
    reg vertical_wall;
    reg [3:0] wall_position, draw_position;
    reg [3:0] first_door_position, second_door_position;
    reg second_door_requested, second_door_enabled;
    reg [2:0] symmetry; // bit 0: flip x; bit 1: flip y; bit 2: transpose

    // Advance randomness at exactly the original two decision states.
    // Keeping these clock positions preserves the map produced by every seed.
    wire [15:0] random_value;
    wire advance_random = (state == S_ORIENT) || (state == S_DOOR_INIT);
    lfsr16 rng(
        .clk(clk), .rst(rst),
        .load(start && state == S_IDLE), .advance(advance_random),
        .seed(seed), .value(random_value)
    );

    // Orientation and early stopping. Spans are coordinate differences;
    // a region from x=1 to x=10 has span 9 and inclusive width 10.
    wire [4:0] x_span = {1'b0, region_x_max} - {1'b0, region_x_min};
    wire [4:0] y_span = {1'b0, region_y_max} - {1'b0, region_y_min};
    wire small_room = (x_span <= SMALL_ROOM_SPAN) && (y_span <= SMALL_ROOM_SPAN);
    wire stop_region = (region_depth >= MAX_DEPTH) ||
                       (region_depth >= EARLY_STOP_DEPTH && small_room &&
                        random_value[2:1] == 2'b00);
    wire choose_vertical = (x_span > y_span) ||
                           ((x_span == y_span) && random_value[0]);

    // Reuse the same calculations for either orientation:
    // axis = where the wall is placed; door = the direction along the wall.
    wire [4:0] axis_low = vertical_wall ? {1'b0, region_x_min} : {1'b0, region_y_min};
    wire [4:0] axis_high = vertical_wall ? {1'b0, region_x_max} : {1'b0, region_y_max};
    wire [4:0] door_low = vertical_wall ? {1'b0, region_y_min} : {1'b0, region_x_min};
    wire [4:0] door_high = vertical_wall ? {1'b0, region_y_max} : {1'b0, region_x_max};

    // Wall candidates are even and leave at least two coordinate steps at
    // each side. Adding/subtracting the low bit rounds to the required parity.
    wire [4:0] wall_min = axis_low + 5'd2 + {4'd0, axis_low[0]};
    wire [4:0] wall_upper_margin = axis_high - 5'd2;
    wire [4:0] wall_max = wall_upper_margin - {4'd0, wall_upper_margin[0]};
    wire can_split = (axis_high >= axis_low + 5'd4) && (wall_min <= wall_max);
    wire [4:0] wall_span = wall_max - wall_min;
    wire [2:0] wall_count = wall_span[3:1] + 3'd1;

    // Map a random byte to a candidate index: (random_byte * count) >> 8.
    // This keeps the original balanced bins and avoids division/modulo.
    // Candidate coordinates are spaced by 2, hence the trailing zero bit.
    wire [10:0] wall_product = random_value[7:0] * wall_count;
    wire [4:0] chosen_wall = wall_min + {1'b0, wall_product[10:8], 1'b0};

    // Door candidates are odd and lie inside the wall's inclusive span.
    wire [4:0] door_min = door_low + {4'd0, ~door_low[0]};
    wire [4:0] door_max = door_high - {4'd0, ~door_high[0]};
    wire [4:0] door_span = door_max - door_min;
    wire [2:0] door_count = door_span[3:1] + 3'd1;
    wire [10:0] first_door_product = random_value[7:0] * door_count;
    wire [10:0] second_door_product = random_value[15:8] * door_count;
    wire [4:0] chosen_first_door = door_min + {1'b0, first_door_product[10:8], 1'b0};
    wire [4:0] chosen_second_door = door_min + {1'b0, second_door_product[10:8], 1'b0};
    wire doors_far_apart =
        (chosen_second_door >= chosen_first_door + MIN_DOOR_SEPARATION) ||
        (chosen_first_door >= chosen_second_door + MIN_DOOR_SEPARATION);

    // Original fixed-map rows, used only with FIXED_MAP=1.
    function [15:0] fixed_map_row;
        input [3:0] row;
        begin
            case (row)
                0, 15:  fixed_map_row = 16'hFFFF;
                7:      fixed_map_row = 16'h8001;
                8:      fixed_map_row = 16'hF7F7;
                default: fixed_map_row = 16'h8101;
            endcase
        end
    endfunction

    // Tile output: initialise all 256 cells, then overwrite dividing walls.
    wire [15:0] initial_row = fixed_map_row(initial_tile[7:4]);
    wire is_boundary = initial_tile[3:0] == 0 || initial_tile[3:0] == EDGE ||
                       initial_tile[7:4] == 0 || initial_tile[7:4] == EDGE;
    wire [7:0] untransformed_address = (state == S_INIT) ? initial_tile :
        (vertical_wall ? {draw_position, wall_position} : {wall_position, draw_position});
    wire [3:0] transformed_x = untransformed_address[3:0] ^ {4{symmetry[0]}};
    wire [3:0] transformed_y = untransformed_address[7:4] ^ {4{symmetry[1]}};
    wire is_door = (draw_position == first_door_position) ||
                   (second_door_enabled && draw_position == second_door_position);

    assign write_en = (state == S_INIT) || (state == S_DRAW);
    assign write_addr = FIXED_MAP ? untransformed_address :
        (symmetry[2] ? {transformed_x, transformed_y} : {transformed_y, transformed_x});
    assign write_wall = (state == S_INIT) ?
        (FIXED_MAP ? initial_row[initial_tile[3:0]] : is_boundary) : !is_door;
    assign busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            initial_tile <= 0;
            stack_size <= 0;
            region_x_min <= 0;
            region_y_min <= 0;
            region_x_max <= 0;
            region_y_max <= 0;
            region_depth <= 0;
            wall_position <= 0;
            draw_position <= 0;
            vertical_wall <= 0;
            first_door_position <= 0;
            second_door_position <= 0;
            second_door_requested <= 0;
            second_door_enabled <= 0;
            symmetry <= 0;
        end else begin
            done <= 0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        initial_tile <= 0;
                        symmetry <= seed[15:13];
                        state <= S_INIT;
                    end
                end

                S_INIT: begin
                    // Output logic writes initial_tile on this clock.
                    if (initial_tile != LAST_TILE) begin
                        initial_tile <= initial_tile + 1'b1;
                    end else if (FIXED_MAP) begin
                        done <= 1;
                        state <= S_IDLE;
                    end else begin
                        // First region is the whole floor interior, at depth 0.
                        stack_x_min[0] <= INTERIOR_FIRST;
                        stack_y_min[0] <= INTERIOR_FIRST;
                        stack_x_max[0] <= INTERIOR_LAST;
                        stack_y_max[0] <= INTERIOR_LAST;
                        stack_depth[0] <= 0;
                        stack_size <= 1;
                        state <= S_POP;
                    end
                end

                S_POP: begin
                    if (stack_size == 0) begin
                        done <= 1;
                        state <= S_IDLE;
                    end else begin
                        region_x_min <= stack_x_min[stack_size-1'b1];
                        region_y_min <= stack_y_min[stack_size-1'b1];
                        region_x_max <= stack_x_max[stack_size-1'b1];
                        region_y_max <= stack_y_max[stack_size-1'b1];
                        region_depth <= stack_depth[stack_size-1'b1];
                        stack_size <= stack_size - 1'b1;
                        state <= S_ORIENT;
                    end
                end

                S_ORIENT: begin
                    if (stop_region) begin
                        state <= S_POP;
                    end else begin
                        vertical_wall <= choose_vertical;
                        state <= S_WALL;
                    end
                end

                S_WALL: begin
                    if (!can_split) begin
                        state <= S_POP;
                    end else begin
                        wall_position <= chosen_wall[3:0];
                        second_door_requested <= random_value[8];
                        state <= S_DOOR_INIT;
                    end
                end

                S_DOOR_INIT: begin
                    // Allow the LFSR advance on this clock before using its
                    // updated value in S_DOOR. Do not merge these two states.
                    state <= S_DOOR;
                end

                S_DOOR: begin
                    first_door_position <= chosen_first_door[3:0];
                    second_door_position <= chosen_second_door[3:0];
                    second_door_enabled <= second_door_requested && doors_far_apart;
                    state <= S_DRAW_INIT;
                end

                S_DRAW_INIT: begin
                    draw_position <= door_low[3:0];
                    state <= S_DRAW;
                end

                S_DRAW: begin
                    // Output logic writes one wall/door tile on this clock.
                    if (draw_position == door_high[3:0]) begin
                        state <= S_PUSH;
                    end else begin
                        draw_position <= draw_position + 1'b1;
                    end
                end

                S_PUSH: begin
                    // Child 1: left of a vertical wall, or above a horizontal wall.
                    stack_x_min[stack_size] <= region_x_min;
                    stack_y_min[stack_size] <= region_y_min;
                    stack_x_max[stack_size] <= vertical_wall ? wall_position-1'b1 : region_x_max;
                    stack_y_max[stack_size] <= vertical_wall ? region_y_max : wall_position-1'b1;
                    stack_depth[stack_size] <= region_depth + 1'b1;

                    // Child 2: right/below. Pushed last, so it is processed first.
                    stack_x_min[stack_size+1'b1] <= vertical_wall ? wall_position+1'b1 : region_x_min;
                    stack_y_min[stack_size+1'b1] <= vertical_wall ? region_y_min : wall_position+1'b1;
                    stack_x_max[stack_size+1'b1] <= region_x_max;
                    stack_y_max[stack_size+1'b1] <= region_y_max;
                    stack_depth[stack_size+1'b1] <= region_depth + 1'b1;
                    stack_size <= stack_size + 2;
                    state <= S_POP;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
