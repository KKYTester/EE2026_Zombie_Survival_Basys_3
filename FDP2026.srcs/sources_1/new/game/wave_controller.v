`timescale 1ns / 1ps
// Wave progression and zombie spawning (Member 4).
//  - Wave n has 3 + 2(n-1) zombies (capped at MAX_WAVE_SIZE).
//  - Intensity grows with the wave: at most n+2 zombies are alive at once
//    (capped at MAX_ALIVE), and the gap between spawns is 2^SPAWN_SHIFT clocks
//    (~0.67 s) for waves 1-2, half that for waves 3-4 and a quarter from wave 5.
//  - Each spawn asks spawn_finder for a far, free floor tile, then holds
//    spawn_req with spawn_tile until the enemy side answers spawn_ack.
//  - enemy_defeated pulses count kills. When every zombie of the wave is
//    spawned and defeated, wave_clear is high for 2^CLEAR_SHIFT clocks
//    (~1.3 s), then the next wave starts.
// Interface to the enemy module (Member 2): spawn_req/spawn_tile -> spawn_ack,
// and one enemy_defeated pulse per zombie killed.
module wave_controller #(parameter MAX_ALIVE=8, parameter MAX_WAVE_SIZE=21,
                         parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
                         parameter MIN_DIST=8)(
    input wire clk, input wire rst,
    input wire play_start, input wire playing,
    input wire [255:0] map_bits, input wire [255:0] occupied,
    input wire [7:0] player_tile,
    input wire spawn_ack, input wire enemy_defeated,
    output reg [6:0] wave,
    output reg spawn_req, output reg [7:0] spawn_tile,
    output reg [5:0] alive,
    output wire [6:0] remaining,          // zombies of this wave not yet defeated
    output reg wave_clear);
    localparam W_IDLE=3'd0, W_WAIT=3'd1, W_FIND=3'd2, W_REQ=3'd3, W_CLEAR=3'd4;
    localparam MAX_SHIFT = (SPAWN_SHIFT > CLEAR_SHIFT) ? SPAWN_SHIFT : CLEAR_SHIFT;
    localparam [6:0] WAVE_CAP = MAX_WAVE_SIZE;
    localparam [5:0] ALIVE_CAP = MAX_ALIVE;
    reg [2:0] state;
    reg [MAX_SHIFT:0] timer;
    reg [6:0] total, spawned, killed;
    reg finder_start;
    wire finder_busy, finder_done, finder_found;
    wire [7:0] finder_tile;
    wire [15:0] random_value;
    lfsr16 rng(.clk(clk),.rst(rst),.load(1'b0),.advance(1'b1),.seed(16'h0001),.value(random_value));
    spawn_finder #(.MIN_DIST(MIN_DIST)) finder(.clk(clk),.rst(rst),.start(finder_start),
        .map_bits(map_bits),.occupied(occupied),.player_tile(player_tile),
        .random_start(random_value[7:0]),.busy(finder_busy),.done(finder_done),
        .found(finder_found),.tile(finder_tile));
    assign remaining = total - killed;
    wire [7:0] next_size = {1'b0,total} + 8'd2;
    // Per-wave limits.
    wire [7:0] wave_limit = {1'b0,wave} + 8'd2;
    wire [5:0] alive_limit = (wave_limit > {2'b00,ALIVE_CAP}) ? ALIVE_CAP : wave_limit[5:0];
    wire spawn_gap_done = (wave<=7'd2) ? timer[SPAWN_SHIFT] :
                          (wave<=7'd4) ? timer[SPAWN_SHIFT-1] : timer[SPAWN_SHIFT-2];
    always @(posedge clk) begin
        if(rst) begin
            state<=W_IDLE; timer<=0; wave<=1; total<=3; spawned<=0; killed<=0; alive<=0;
            spawn_req<=0; spawn_tile<=0; wave_clear<=0; finder_start<=0;
        end else begin
            finder_start<=0;
            if(play_start) begin
                state<=W_WAIT; timer<=0; wave<=1; total<=3; spawned<=0; killed<=0; alive<=0;
                spawn_req<=0; wave_clear<=0;
            end else if(!playing) begin
                state<=W_IDLE; spawn_req<=0; wave_clear<=0;
            end else begin
                // Kills can arrive in any state; never count below zero.
                if(enemy_defeated && alive!=0) begin
                    alive<=alive-1'b1; killed<=killed+1'b1;
                end
                case(state)
                    W_WAIT: begin
                        if(!spawn_gap_done) timer<=timer+1'b1;
                        if(killed==total) begin
                            state<=W_CLEAR; timer<=0; wave_clear<=1;
                        end else if(spawn_gap_done && spawned<total && alive<alive_limit) begin
                            finder_start<=1; state<=W_FIND;
                        end
                    end
                    W_FIND: if(finder_done) begin
                        timer<=0;
                        if(finder_found) begin spawn_tile<=finder_tile; spawn_req<=1; state<=W_REQ; end
                        else state<=W_WAIT;                  // try again later
                    end
                    W_REQ: if(spawn_ack) begin
                        spawn_req<=0; spawned<=spawned+1'b1;
                        alive<=alive+1'b1 - ((enemy_defeated && alive!=0) ? 1'b1 : 1'b0);
                        state<=W_WAIT;
                    end
                    W_CLEAR: begin
                        if(timer[CLEAR_SHIFT]) begin
                            wave_clear<=0; timer<=0; spawned<=0; killed<=0;
                            if(wave!=7'd99) wave<=wave+1'b1;
                            total <= (next_size>{1'b0,WAVE_CAP}) ? WAVE_CAP : next_size[6:0];
                            state<=W_WAIT;
                        end else timer<=timer+1'b1;
                    end
                    default: state<=W_WAIT;
                endcase
            end
        end
    end
endmodule
