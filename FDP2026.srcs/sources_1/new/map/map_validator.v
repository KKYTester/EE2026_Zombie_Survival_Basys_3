`timescale 1ns / 1ps
module map_validator #(parameter CHECK_CONNECTIVITY=1, parameter MAX_CYCLES=4096)(
    input wire clk, input wire rst, input wire start,
    input wire [255:0] map_bits,
    output wire busy, output reg done, output reg passed,
    output reg [2:0] error_code, output reg [7:0] p1_addr, p2_addr,
    output reg [8:0] floor_count, reachable_count);
    localparam OK=0, OPEN_BOUNDARY=1, DISCONNECTED=2, BAD_SPAWN=3, TIMEOUT=4;
    localparam S_IDLE=0;   // Wait for an immutable map to validate.
    localparam S_SCAN=1;   // Count floors, check boundaries and select extreme-sum spawns.
    localparam S_CHECK=2;  // Reject structural/spawn errors before BFS.
    localparam S_POP=3;    // Pop the next floor tile, or compare counts when empty.
    localparam S_ADDR=4;   // Register one bounded neighbour address.
    localparam S_NEIGH=5;  // Register its floor/unvisited eligibility after lookup.
    localparam S_ENQUEUE=6;// Enqueue the eligible tile once, then advance direction.
    reg [2:0] state;
    reg [7:0] scan_addr, current;
    reg [1:0] direction;
    reg [255:0] visited;
    reg [7:0] queue[0:255];
    reg [8:0] head,tail;
    reg [15:0] elapsed;
    reg boundary_bad;
    reg [4:0] min_sum,max_sum;
    wire [4:0] sum_xy={1'b0,scan_addr[3:0]}+{1'b0,scan_addr[7:4]};
    wire scan_boundary=scan_addr[3:0]==0 || scan_addr[3:0]==15 ||
                       scan_addr[7:4]==0 || scan_addr[7:4]==15;
    reg neighbour_valid;
    reg [7:0] neighbour;
    reg [7:0] checked_neighbour;
    reg checked_valid,enqueue_pending;
    assign busy=state!=S_IDLE;
    always @* begin
        neighbour=current; neighbour_valid=0;
        case(direction)
            0: begin neighbour=current-8'd1; neighbour_valid=current[3:0]!=0; end
            1: begin neighbour=current+8'd1; neighbour_valid=current[3:0]!=15; end
            2: begin neighbour=current-8'd16; neighbour_valid=current[7:4]!=0; end
            3: begin neighbour=current+8'd16; neighbour_valid=current[7:4]!=15; end
        endcase
    end
    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; done<=0; passed<=0; error_code<=OK;
            p1_addr<=0; p2_addr<=0; floor_count<=0; reachable_count<=0;
            visited<=0; head<=0; tail<=0; elapsed<=0; boundary_bad<=0;
            min_sum<=31; max_sum<=0; scan_addr<=0; current<=0; direction<=0;
            checked_neighbour<=0; checked_valid<=0; enqueue_pending<=0;
        end else begin
            done<=0;
            if (state!=S_IDLE) elapsed<=elapsed+1'b1;
            if (state!=S_IDLE && elapsed>=MAX_CYCLES-1) begin
                state<=S_IDLE; done<=1; passed<=0; error_code<=TIMEOUT;
            end else case(state)
                S_IDLE: if(start) begin
                    state<=S_SCAN; scan_addr<=0; elapsed<=0; boundary_bad<=0;
                    floor_count<=0; reachable_count<=0; visited<=0;
                    head<=0; tail<=0; min_sum<=31; max_sum<=0;
                    p1_addr<=0; p2_addr<=0; passed<=0; error_code<=OK;
                end
                S_SCAN: begin
                    if (!map_bits[scan_addr]) begin
                        floor_count<=floor_count+1'b1;
                        if (scan_boundary) boundary_bad<=1;
                        // Row-major first tile wins ties for either extreme.
                        if (floor_count==0 || sum_xy<min_sum) begin
                            min_sum<=sum_xy; p1_addr<=scan_addr;
                        end
                        if (floor_count==0 || sum_xy>max_sum) begin
                            max_sum<=sum_xy; p2_addr<=scan_addr;
                        end
                    end
                    if(scan_addr==255) state<=S_CHECK;
                    else scan_addr<=scan_addr+1'b1;
                end
                S_CHECK: begin
                    if(boundary_bad) begin
                        error_code<=OPEN_BOUNDARY; done<=1; state<=S_IDLE;
                    end else if(floor_count<2 || p1_addr==p2_addr ||
                                map_bits[p1_addr] || map_bits[p2_addr]) begin
                        error_code<=BAD_SPAWN; done<=1; state<=S_IDLE;
                    end else if(!CHECK_CONNECTIVITY) begin
                        passed<=1; error_code<=OK; done<=1; state<=S_IDLE;
                    end else begin
                        visited[p1_addr]<=1; queue[0]<=p1_addr;
                        head<=0; tail<=1; reachable_count<=1; state<=S_POP;
                    end
                end
                S_POP: if(CHECK_CONNECTIVITY) begin
                    if(head==tail) begin
                        passed<=reachable_count==floor_count;
                        error_code<=(reachable_count==floor_count) ? OK : DISCONNECTED;
                        done<=1; state<=S_IDLE;
                    end else begin
                        current<=queue[head[7:0]]; head<=head+1'b1;
                        direction<=0; state<=S_ADDR;
                    end
                end else state<=S_IDLE;
                S_ADDR: if(CHECK_CONNECTIVITY) begin
                    checked_neighbour<=neighbour; checked_valid<=neighbour_valid;
                    state<=S_NEIGH;
                end else state<=S_IDLE;
                S_NEIGH: if(CHECK_CONNECTIVITY) begin
                    enqueue_pending<=checked_valid && !map_bits[checked_neighbour] &&
                                     !visited[checked_neighbour];
                    state<=S_ENQUEUE;
                end else state<=S_IDLE;
                S_ENQUEUE: if(CHECK_CONNECTIVITY) begin
                    if(enqueue_pending) begin
                        if(tail>=256) begin
                            error_code<=TIMEOUT; passed<=0; done<=1; state<=S_IDLE;
                        end else begin
                            visited[checked_neighbour]<=1; queue[tail[7:0]]<=checked_neighbour;
                            tail<=tail+1'b1; reachable_count<=reachable_count+1'b1;
                            if(direction==3) state<=S_POP;
                            else begin direction<=direction+1'b1; state<=S_ADDR; end
                        end
                    end else if(direction==3) state<=S_POP;
                    else begin direction<=direction+1'b1; state<=S_ADDR; end
                end else state<=S_IDLE;
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
