`timescale 1ns / 1ps
module map_generator #(parameter FIXED_MAP = 0)(
    input wire clk, input wire rst, input wire start,
    input wire [15:0] seed, output wire write_en,
    output wire [7:0] write_addr, output wire write_wall,
    output wire busy, output reg done);
    localparam S_IDLE=0;       // Wait for a generation request.
    localparam S_INIT=1;       // Write one initial/fixed tile per clock.
    localparam S_POP=2;        // Pop a region, or finish when the stack is empty.
    localparam S_ORIENT=3;     // Choose the longer axis; break ties with the LFSR.
    localparam S_WALL=4;       // Scan legal even wall positions, choosing one.
    localparam S_DOOR_INIT=5;  // Initialise the odd-coordinate doorway search.
    localparam S_DOOR=6;       // Scan odd doorway candidates, choosing one.
    localparam S_DRAW_INIT=7;  // Load the first tile of the chosen dividing wall.
    localparam S_DRAW=8;       // Draw one wall tile (or the one doorway) per clock.
    localparam S_PUSH=9;       // Push the two child regions at depth + 1.
    reg [3:0] state;
    reg [7:0] init_addr;
    reg [3:0] sx0[0:7], sy0[0:7], sx1[0:7], sy1[0:7];
    reg [2:0] sd[0:7];
    reg [3:0] sp;
    reg [3:0] x0,y0,x1,y1, wall_pos,door_pos,draw_pos;
    reg [2:0] depth;
    reg vertical, found;
    reg want_second,second_found;
    reg [3:0] second_door;
    localparam S_SECOND=10; // Scan distinct odd candidates for the optional second door.
    reg [4:0] candidate;
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
    assign write_en = state==S_INIT || state==S_DRAW;
    assign write_addr = state==S_INIT ? init_addr :
                        (vertical ? {draw_pos,wall_pos} : {wall_pos,draw_pos});
    assign write_wall = state==S_INIT ?
        (FIXED_MAP ? initial_row[init_addr[3:0]] : boundary) : (draw_pos!=door_pos && (!second_found || draw_pos!=second_door));
    assign busy = state!=S_IDLE;
    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; done<=0; init_addr<=0; sp<=0;
            x0<=0; y0<=0; x1<=0; y1<=0; depth<=0;
            wall_pos<=0; door_pos<=0; draw_pos<=0;
            vertical<=0; found<=0; candidate<=0;
            want_second<=0; second_found<=0; second_door<=0;
        end else begin
            done<=0;
            case (state)
                S_IDLE: if (start) begin init_addr<=0; state<=S_INIT; end
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
                    if (depth>=4 || (depth>=2 && random_value[2:1]==2'b00)) state<=S_POP;
                    else begin
                        vertical <= (dx>dy) || ((dx==dy) && random_value[0]);
                        candidate<=0; found<=0; state<=S_WALL;
                    end
                end
                S_WALL: begin
                    if (candidate==16) begin
                        if (found) state<=S_DOOR_INIT;
                        else state<=S_POP;
                    end else begin
                        // Addition comparisons avoid unsigned subtraction underflow.
                        if (!candidate[0] && candidate>=axis_lo+5'd2 &&
                            candidate+5'd2<=axis_hi) begin
                            if (!found || random_value[candidate[3:0]])
                                wall_pos<=candidate[3:0];
                            found<=1;
                        end
                        candidate<=candidate+1'b1;
                    end
                end
                S_DOOR_INIT: begin
                    candidate<=0; found<=0; second_found<=0;
                    want_second<=random_value[3]; state<=S_DOOR;
                end
                S_DOOR: begin
                    if (candidate==16) begin candidate<=0; state<=S_SECOND; end
                    else begin
                        if (candidate[0] && candidate>=door_lo && candidate<=door_hi) begin
                            if (!found || random_value[candidate[3:0]])
                                door_pos<=candidate[3:0];
                            found<=1;
                        end
                        candidate<=candidate+1'b1;
                    end
                end
                S_SECOND: begin
                    if (!want_second || candidate==16) state<=S_DRAW_INIT;
                    else begin
                        if(candidate[0] && candidate>=door_lo && candidate<=door_hi &&
                           candidate[3:0]!=door_pos) begin
                            if(!second_found || random_value[candidate[3:0]])
                                second_door<=candidate[3:0];
                            second_found<=1;
                        end
                        candidate<=candidate+1'b1;
                    end
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
