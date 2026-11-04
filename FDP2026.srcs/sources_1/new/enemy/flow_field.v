`timescale 1ns / 1ps
// Reverse BFS on a stable 16x16 map. Tile IDs pack {y, x}.
module flow_field(
    input wire clk, reset, enabled,
    input wire [255:0] walls,
    input wire [7:0] goal, read_tile,
    input wire goal_active, goal2_active,
    input wire [7:0] goal2,
    output wire ready,
    output reg read_reachable,
    output reg [1:0] read_direction
);
    localparam [2:0] START=0, POP=1, NEIGHBOR=2, VISIT=3, DONE=4, SEED_SECOND=5;
    reg [2:0] state;
    reg [7:0] field_goal, current, neighbor;
    reg [7:0] field_goal2;
    reg field_active, field_active2;
    reg neighbor_valid;
    reg [1:0] direction;
    // Nine-bit indices distinguish an empty queue from 256 queued entries.
    reg [8:0] head, tail;
    reg [255:0] visited;
    reg [7:0] queue [0:255];
    reg [1:0] arrows [0:255];

    wire same_goals = field_active==goal_active && field_active2==goal2_active &&
                      (!goal_active || field_goal==goal) &&
                      (!goal2_active || field_goal2==goal2);
    assign ready = state==DONE && same_goals;
    wire building = enabled && !reset && (state==START || same_goals);
    wire seed = building && state==START && goal_active && !walls[goal];
    wire seed2 = building && state==SEED_SECOND && goal2_active &&
                 !walls[goal2] && !visited[goal2];
    wire discover = building && state==VISIT && neighbor_valid &&
                    !walls[neighbor] && !visited[neighbor];

    // No memory reset needed. Visited bits qualify every stored arrow.
    always @(posedge clk) begin
        if(seed) queue[0]<=goal;
        else if(seed2 || discover) queue[tail[7:0]]<=seed2 ? goal2 : neighbor;
        if(discover) arrows[neighbor]<=direction ^ 2'b01;
        if(building && state==POP && head!=tail) current<=queue[head[7:0]];
        read_direction<=arrows[read_tile];
        read_reachable<=ready && visited[read_tile] &&
                        !(field_active && read_tile==field_goal) &&
                        !(field_active2 && read_tile==field_goal2);
    end

    always @(posedge clk) begin
        if(reset || !enabled || (state!=START && !same_goals)) begin
            state<=START;
        end else begin
            case(state)
                START: begin
                    field_goal<=goal;
                    field_goal2<=goal2;
                    field_active<=goal_active; field_active2<=goal2_active;
                    visited<=seed ? (256'd1 << goal) : 256'd0;
                    head<=0; tail<=seed ? 9'd1 : 9'd0;
                    state<=goal2_active ? SEED_SECOND : POP;
                end
                SEED_SECOND: begin
                    // Seed both players before expanding either. P1 wins equal routes.
                    if(seed2) begin
                        visited[goal2]<=1;
                        tail<=tail+1'b1;
                    end
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
