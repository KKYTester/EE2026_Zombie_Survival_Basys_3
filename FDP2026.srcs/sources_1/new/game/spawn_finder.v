`timescale 1ns / 1ps
// Multi-source BFS marks each tile's distance band and nearest player.
// Prefer the requested player's side of the map. Ties belong to P1, matching
// the movement field's queue order. If the preferred side
// has no safe floor, use the other side. Never relax below MIN_SAFE_DIST.
module spawn_finder #(parameter MIN_DIST=8, parameter TWO_PLAYERS=0,
    parameter MIN_SAFE_DIST=(MIN_DIST<2 ? MIN_DIST : 2))(
    input wire clk, input wire rst, input wire start,
    input wire [255:0] map_bits,          // 1 = wall
    input wire [255:0] occupied,          // includes enemy movement reservations
    input wire [7:0] player_tile, player2_tile,
    input wire player_active,player2_active,
    input wire prefer_player2,
    input wire [7:0] random_start,
    output wire busy, output reg done, output reg found, output reg [7:0] tile);
    localparam [3:0] IDLE=0, INIT=1, SEED1=2, SEED2=3, POP=4, ADDRESS=5,
                     LOOKUP=6, VISIT=7, SCAN=8, CANDIDATE=9, FALLBACK=10;
    reg [3:0] state;
    reg [7:0] p1,p2,start_index,index,current,neighbor,fallback,side_fallback,other_far;
    reg p1_live,p2_live,neighbor_allowed,fallback_valid;
    reg balance,prefer_p1,current_p1,side_fallback_valid,other_far_valid;
    reg [8:0] head,tail,level_end;
    reg [7:0] depth,scanned;
    reg [2:0] direction;
    // INIT clears the tile metadata one address per cycle.
    (* ram_style="block" *) reg [8:0] queue[0:255];
    // {P1's side, at least MIN_DIST away, visited}
    (* ram_style="distributed" *) reg [2:0] tile_info[0:255];
    reg [2:0] info;
    reg free_tile;
    `include "Enemy_Path.vh"
    wire [7:0] next_tile=neighbor_tile(current,direction);
    wire next_legal=neighbor_valid(current,direction) &&
        (!direction[2] || (!map_bits[{current[7:4],next_tile[3:0]}] &&
                           !map_bits[{next_tile[7:4],current[3:0]}]));
    wire seed1=state==SEED1 && p1_live && !map_bits[p1];
    wire seed2=state==SEED2 && p2_live && !map_bits[p2] && !(tail!=0 && p1==p2);
    wire discover=state==VISIT && neighbor_allowed && !info[0] && !map_bits[neighbor];
    wire enqueue=seed1 || seed2 || discover;
    wire [7:0] enqueue_tile=seed1 ? p1 : seed2 ? p2 : neighbor;
    wire enqueue_p1=seed1 || (discover && current_p1);
    wire far_enough=discover && depth>=MIN_DIST-1;
    wire [7:0] lookup_tile=state==SCAN ? index : neighbor;
    wire far_candidate=free_tile && (!info[0] || info[1]);
    assign busy=state!=IDLE;
    always @(posedge clk) begin
        if(!rst && enqueue) queue[tail[7:0]]<={enqueue_p1,enqueue_tile};
        if(state==POP && head!=tail) {current_p1,current}<=queue[head[7:0]];
        if(!rst && (state==INIT || enqueue))
            tile_info[state==INIT ? index : enqueue_tile]<=
                state==INIT ? 3'b0 : {enqueue_p1,far_enough,1'b1};
        if(state==LOOKUP || state==SCAN) begin
            info<=tile_info[lookup_tile];
            free_tile<=!map_bits[lookup_tile] && !occupied[lookup_tile];
        end
    end
    always @(posedge clk) begin
        done<=0;
        if(rst) begin
            state<=IDLE; found<=0; tile<=0; index<=0; head<=0; tail<=0;
            level_end<=0; depth<=0; scanned<=0; fallback_valid<=0;
        end else begin
            if(enqueue) tail<=tail+1'b1;
            case(state)
                IDLE: if(start) begin
                    balance<=TWO_PLAYERS && player_active && player2_active;
                    prefer_p1<=!prefer_player2;
                    p1<=player_tile; p2<=player2_tile;
                    p1_live<=!TWO_PLAYERS || player_active;
                    p2_live<=TWO_PLAYERS && player2_active;
                    start_index<=random_start; index<=0;
                    head<=0; tail<=0; depth<=0; fallback_valid<=0;
                    side_fallback_valid<=0; other_far_valid<=0; state<=INIT;
                end
                INIT: begin
                    index<=index+1'b1;
                    if(index==8'hff) state<=SEED1;
                end
                SEED1: state<=SEED2;
                SEED2: begin
                    level_end<=tail+{8'd0,seed2}; state<=POP;
                end
                POP: if(head==tail || (!balance && (MIN_DIST<=1 || depth>=MIN_DIST-1))) begin
                    index<=start_index; scanned<=0; state<=SCAN;
                end else begin
                    head<=head+1'b1; direction<=0; state<=ADDRESS;
                end
                ADDRESS: begin
                    neighbor<=next_tile; neighbor_allowed<=next_legal; state<=LOOKUP;
                end
                LOOKUP: state<=VISIT;
                VISIT: begin
                    // Discovery is ordered by distance, so the last safe
                    // candidate is a farthest one if no preferred tile exists.
                    if(discover && free_tile && depth+8'd1>=MIN_SAFE_DIST) begin
                        fallback<=neighbor; fallback_valid<=1;
                        if(current_p1==prefer_p1) begin
                            side_fallback<=neighbor; side_fallback_valid<=1;
                        end
                    end
                    if(direction==7) begin
                        if(head==level_end) begin
                            level_end<=tail+{8'd0,discover}; depth<=depth+1'b1;
                        end
                        state<=POP;
                    end else begin direction<=direction+1'b1; state<=ADDRESS; end
                end
                SCAN: state<=CANDIDATE;
                CANDIDATE: if(far_candidate && (!balance || (info[0] && info[2]==prefer_p1))) begin
                    found<=1; tile<=index; done<=1; state<=IDLE;
                end else begin
                    if(far_candidate && !other_far_valid) begin
                        other_far<=index; other_far_valid<=1;
                    end
                    if(scanned==8'hff) state<=FALLBACK;
                    else begin index<=index+1'b1; scanned<=scanned+1'b1; state<=SCAN; end
                end
                FALLBACK: begin
                    if(balance && side_fallback_valid && !occupied[side_fallback]) begin
                        found<=1; tile<=side_fallback;
                    end else if(other_far_valid && !occupied[other_far]) begin
                        found<=1; tile<=other_far;
                    end else begin
                        found<=fallback_valid && !occupied[fallback];
                        tile<=fallback;
                    end
                    done<=1; state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
