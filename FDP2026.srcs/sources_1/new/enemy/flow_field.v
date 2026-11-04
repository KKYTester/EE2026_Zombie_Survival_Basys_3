`timescale 1ns / 1ps
// Reverse BFS on a stable 16x16 map. Tile IDs pack {y, x}.
module flow_field(
    input wire clk, reset, enabled,
    input wire [255:0] walls,
    input wire [7:0] goal, read_tile,
    output wire ready,
    output reg read_reachable,
    output reg [1:0] read_direction
);
    localparam [2:0] START=0, POP=1, NEIGHBOR=2, VISIT=3, DONE=4;
    reg [2:0] state;
    reg [7:0] field_goal, current, neighbor;
    reg neighbor_valid;
    reg [1:0] direction;
    // Nine-bit indices distinguish an empty queue from 256 queued entries.
    reg [8:0] head, tail;
    reg [255:0] visited;
    reg [7:0] queue [0:255];
    reg [1:0] arrows [0:255];

    assign ready = state==DONE && field_goal==goal;
    wire building = enabled && !reset && (state==START || field_goal==goal);
    wire seed = building && state==START && !walls[goal];
    wire discover = building && state==VISIT && neighbor_valid &&
                    !walls[neighbor] && !visited[neighbor];

    // No memory reset needed. Visited bits qualify every stored arrow.
    always @(posedge clk) begin
        if(seed) queue[0]<=goal;
        else if(discover) queue[tail[7:0]]<=neighbor;
        if(discover) arrows[neighbor]<=direction ^ 2'b01;
        if(building && state==POP && head!=tail) current<=queue[head[7:0]];
        read_direction<=arrows[read_tile];
        read_reachable<=ready && visited[read_tile] && read_tile!=field_goal;
    end

    always @(posedge clk) begin
        if(reset || !enabled || (state!=START && field_goal!=goal)) begin
            state<=START;
        end else begin
            case(state)
                START: begin
                    field_goal<=goal;
                    visited<=seed ? (256'd1 << goal) : 256'd0;
                    head<=0; tail<=seed ? 9'd1 : 9'd0;
                    state<=POP;
                end
                POP: if(head==tail) state<=DONE;
                else begin
                    head<=head+1'b1; direction<=0; state<=NEIGHBOR;
                end
                NEIGHBOR: begin
                    // Direction order: left, right, up, down.
                    case(direction)
                        2'd0: begin neighbor<=current-8'd1; neighbor_valid<=current[3:0]!=0; end
                        2'd1: begin neighbor<=current+8'd1; neighbor_valid<=current[3:0]!=15; end
                        2'd2: begin neighbor<=current-8'd16; neighbor_valid<=current[7:4]!=0; end
                        2'd3: begin neighbor<=current+8'd16; neighbor_valid<=current[7:4]!=15; end
                    endcase
                    state<=VISIT;
                end
                VISIT: begin
                    // Mark on enqueue so each tile enters the queue once.
                    if(discover) begin
                        visited[neighbor]<=1;
                        tail<=tail+1'b1;
                    end
                    direction<=direction+1'b1;
                    state<=(direction==3) ? POP : NEIGHBOR;
                end
                DONE: state<=DONE;
                default: state<=START;
            endcase
        end
    end
endmodule
