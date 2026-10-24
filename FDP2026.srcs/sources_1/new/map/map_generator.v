`timescale 1ns / 1ps
// Recursive-division map generator (rule C, polished).
//  - Walls on even coordinates, doorways on odd coordinates.
//  - Up to depth 4; rooms whose sides are both <= 10 tiles may stop early (25%).
//  - Wall and door positions are chosen uniformly: index = (rand8 * count) >> 8.
//  - Optional second door (50%) is kept only when at least 4 tiles from the
//    first, so no isolated single wall tile is left between two gaps.
//  - The finished map is randomly mirrored in x and/or y and/or transposed
//    (8 symmetries, chosen by seed bits) by remapping write addresses.
module map_generator #(parameter FIXED_MAP = 0)(
    input wire clk, input wire rst, input wire start,
    input wire [15:0] seed, output wire write_en,
    output wire [7:0] write_addr, output wire write_wall,
    output wire busy, output reg done);
    localparam S_IDLE=0;       // Wait for a generation request.
    localparam S_INIT=1;       // Write one initial/fixed tile per clock.
    localparam S_POP=2;        // Pop a region, or finish when the stack is empty.
    localparam S_ORIENT=3;     // Early stop, or choose the axis (longer side; LFSR tie-break).
    localparam S_WALL=4;       // Choose an even wall position uniformly.
    localparam S_DOOR_INIT=5;  // Advance the LFSR for the doorway choices.
    localparam S_DOOR=6;       // Choose odd doorway(s) uniformly.
    localparam S_DRAW_INIT=7;  // Load the first tile of the chosen dividing wall.
    localparam S_DRAW=8;       // Draw one wall tile (or doorway) per clock.
    localparam S_PUSH=9;       // Push the two child regions at depth + 1.
    reg [3:0] state;
    reg [7:0] init_addr;
    reg [3:0] sx0[0:7], sy0[0:7], sx1[0:7], sy1[0:7];
    reg [2:0] sd[0:7];
    reg [3:0] sp;
    reg [3:0] x0,y0,x1,y1, wall_pos,door_pos,draw_pos;
    reg [2:0] depth;
    reg vertical;
    reg want_second,second_found;
    reg [3:0] second_door;
    reg [2:0] sym;             // {transpose, flip_y, flip_x}
    wire [15:0] random_value;
    wire [4:0] dx = {1'b0,x1} - {1'b0,x0};
    wire [4:0] dy = {1'b0,y1} - {1'b0,y0};
    wire [4:0] axis_lo = vertical ? {1'b0,x0} : {1'b0,y0};
    wire [4:0] axis_hi = vertical ? {1'b0,x1} : {1'b0,y1};
    wire [4:0] door_lo = vertical ? {1'b0,y0} : {1'b0,x0};
    wire [4:0] door_hi = vertical ? {1'b0,y1} : {1'b0,x1};
    wire advance_rng = (state == S_ORIENT) || (state == S_DOOR_INIT);
    lfsr16 rng(.clk(clk),.rst(rst),.load(start && state==S_IDLE),
        .advance(advance_rng),.seed(seed),.value(random_value));

    // Even wall candidates: lower+2 <= w <= upper-2 (no wall touches a parent wall).
    wire [4:0] wall_min = axis_lo + 5'd2 + {4'd0, axis_lo[0]};          // round up to even
    wire [4:0] wall_hi2 = axis_hi - 5'd2;
    wire [4:0] wall_max = wall_hi2 - {4'd0, wall_hi2[0]};               // round down to even
    wire wall_ok = (axis_hi >= axis_lo + 5'd4) && (wall_min <= wall_max);
    wire [4:0] wall_span = wall_max - wall_min;
    wire [2:0] wall_count = wall_span[3:1] + 3'd1;                      // 1..7 candidates
    wire [10:0] wall_prod = random_value[7:0] * wall_count;            // 8x3-bit multiply
    wire [4:0] wall_pick = wall_min + {1'b0, wall_prod[10:8], 1'b0};
    // Odd doorway candidates inside the wall's span.
    wire [4:0] door_min = door_lo + {4'd0, ~door_lo[0]};
    wire [4:0] door_max = door_hi - {4'd0, ~door_hi[0]};
    wire [4:0] door_span = door_max - door_min;
    wire [2:0] door_count = door_span[3:1] + 3'd1;
    wire [10:0] door1_prod = random_value[7:0] * door_count;
    wire [10:0] door2_prod = random_value[15:8] * door_count;
    wire [4:0] door1_pick = door_min + {1'b0, door1_prod[10:8], 1'b0};
    wire [4:0] door2_pick = door_min + {1'b0, door2_prod[10:8], 1'b0};
    wire doors_far = (door2_pick >= door1_pick + 5'd4) || (door1_pick >= door2_pick + 5'd4);

    function [15:0] fixed_row;
        input [3:0] row;
        begin
            case (row)
                0,15: fixed_row=16'hFFFF;
                7: fixed_row=16'h8001;
                8: fixed_row=16'hF7F7;
                default: fixed_row=16'h8101;
            endcase
        end
    endfunction
    wire [15:0] initial_row = fixed_row(init_addr[7:4]);
    wire boundary = init_addr[3:0]==0 || init_addr[3:0]==15 ||
                    init_addr[7:4]==0 || init_addr[7:4]==15;
    wire [7:0] raw_addr = state==S_INIT ? init_addr :
                          (vertical ? {draw_pos,wall_pos} : {wall_pos,draw_pos});
    // Symmetry remap: a bijection, so every tile is still written exactly once,
    // the boundary stays closed and connectivity is unchanged.
    wire [3:0] map_x = raw_addr[3:0] ^ {4{sym[0]}};
    wire [3:0] map_y = raw_addr[7:4] ^ {4{sym[1]}};
    assign write_en = state==S_INIT || state==S_DRAW;
    assign write_addr = FIXED_MAP ? raw_addr : (sym[2] ? {map_x,map_y} : {map_y,map_x});
    assign write_wall = state==S_INIT ?
        (FIXED_MAP ? initial_row[init_addr[3:0]] : boundary) :
        (draw_pos!=door_pos && (!second_found || draw_pos!=second_door));
    assign busy = state!=S_IDLE;
    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; done<=0; init_addr<=0; sp<=0;
            x0<=0; y0<=0; x1<=0; y1<=0; depth<=0;
            wall_pos<=0; door_pos<=0; draw_pos<=0; vertical<=0;
            want_second<=0; second_found<=0; second_door<=0; sym<=0;
        end else begin
            done<=0;
            case (state)
                S_IDLE: if (start) begin
                    init_addr<=0; sym<=seed[15:13]; state<=S_INIT;
                end
                S_INIT: begin
                    if (init_addr==255) begin
                        if (FIXED_MAP) begin done<=1; state<=S_IDLE; end
                        else begin
                            sx0[0]<=1; sy0[0]<=1; sx1[0]<=14; sy1[0]<=14;
                            sd[0]<=0; sp<=1; state<=S_POP;
                        end
                    end else init_addr<=init_addr+1'b1;
                end
                S_POP: begin
                    if (sp==0) begin done<=1; state<=S_IDLE; end
                    else begin
                        x0<=sx0[sp-1'b1]; y0<=sy0[sp-1'b1];
                        x1<=sx1[sp-1'b1]; y1<=sy1[sp-1'b1];
                        depth<=sd[sp-1'b1]; sp<=sp-1'b1; state<=S_ORIENT;
                    end
                end
                S_ORIENT: begin
                    if (depth>=4 || (depth>=2 && dx<=5'd9 && dy<=5'd9 &&
                                     random_value[2:1]==2'b00)) state<=S_POP;
                    else begin
                        vertical <= (dx>dy) || ((dx==dy) && random_value[0]);
                        state<=S_WALL;
                    end
                end
                S_WALL: begin
                    if (wall_ok) begin
                        wall_pos<=wall_pick[3:0]; want_second<=random_value[8];
                        state<=S_DOOR_INIT;
                    end else state<=S_POP;
                end
                S_DOOR_INIT: state<=S_DOOR;
                S_DOOR: begin
                    door_pos<=door1_pick[3:0];
                    second_door<=door2_pick[3:0];
                    second_found<=want_second && doors_far;
                    state<=S_DRAW_INIT;
                end
                S_DRAW_INIT: begin draw_pos<=door_lo[3:0]; state<=S_DRAW; end
                S_DRAW: begin
                    if (draw_pos==door_hi[3:0]) state<=S_PUSH;
                    else draw_pos<=draw_pos+1'b1;
                end
                S_PUSH: begin
                    // Depth-first traversal needs at most five occupied entries at depth four (capacity eight).
                    sx0[sp]<=x0; sy0[sp]<=y0;
                    sx1[sp]<=vertical ? wall_pos-1'b1 : x1;
                    sy1[sp]<=vertical ? y1 : wall_pos-1'b1;
                    sd[sp]<=depth+1'b1;
                    sx0[sp+1'b1]<=vertical ? wall_pos+1'b1 : x0;
                    sy0[sp+1'b1]<=vertical ? y0 : wall_pos+1'b1;
                    sx1[sp+1'b1]<=x1; sy1[sp+1'b1]<=y1;
                    sd[sp+1'b1]<=depth+1'b1;
                    sp<=sp+2; state<=S_POP;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
