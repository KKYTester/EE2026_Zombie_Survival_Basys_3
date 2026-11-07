`timescale 1ns / 1ps
// Health and magazine pickups (one of each per wave).
//  - place (pulse, start of each wave): any uncollected pickup is removed,
//    then a health pickup and a magazine pickup are put on random floor
//    tiles. A tile is accepted if it is floor, has no zombie, is not the other
//    pickup's tile and is at least MIN_DIST tiles (8-neighbour distance) from
//    every live player. The search walks an 8-bit LFSR (all 255 non-zero
//    tiles) from a random start, one tile per clock; if no tile passes, it
//    retries once accepting any free floor tile away from the players' own
//    tiles, then gives up for this wave.
//  - Collection: a live player standing on a pickup's tile takes it. Health
//    is taken only by a player below full hearts (so it is never wasted);
//    a magazine is always taken. P1 wins a tie. Each collection pulses the
//    matching output for one clock and removes the pickup.
//  - Leaving play removes both pickups.
// Runs on the board that owns the run (1 PLAYER, or the 2-player leader).
module pickup_manager #(parameter MIN_DIST=4)(
    input wire clk, input wire rst,
    input wire playing,
    input wire place,                        // one-clock pulse: new wave
    input wire [255:0] map_bits,             // 1 = wall
    input wire [255:0] blocked,              // zombie tiles
    input wire [7:0] random,                 // any changing value (search start)
    input wire [7:0] p1_tile, input wire [7:0] p2_tile,
    input wire p1_active, input wire p2_active,
    input wire p1_hurt, input wire p2_hurt,  // below full hearts
    output reg health_valid, output reg [7:0] health_tile,
    output reg mag_valid, output reg [7:0] mag_tile,
    output reg p1_heal, output reg p1_mag, output reg p2_heal, output reg p2_mag);

    // 8-bit maximal LFSR (x^8+x^6+x^5+x^4+1): visits every non-zero tile.
    reg [7:0] lfsr;
    wire [7:0] lfsr_next = {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
    reg searching, search_mag, relaxed;
    reg [7:0] tries;
    function [3:0] axis_gap(input [3:0] a, input [3:0] b);
        axis_gap = a>b ? a-b : b-a;
    endfunction
    function far_from(input [7:0] t, input [7:0] p, input active, input relax);
        reg [3:0] dx, dy;
        begin
            dx=axis_gap(t[3:0],p[3:0]); dy=axis_gap(t[7:4],p[7:4]);
            far_from = !active || (relax ? t!=p : (dx>=MIN_DIST || dy>=MIN_DIST));
        end
    endfunction
    wire [7:0] other_tile = search_mag ? health_tile : mag_tile;
    wire other_valid = search_mag ? health_valid : 1'b0;
    wire candidate_ok = !map_bits[lfsr] && !blocked[lfsr] &&
                        !(other_valid && other_tile==lfsr) &&
                        far_from(lfsr,p1_tile,p1_active,relaxed) &&
                        far_from(lfsr,p2_tile,p2_active,relaxed);

    wire take_health_p1 = health_valid && p1_active && p1_hurt && p1_tile==health_tile;
    wire take_health_p2 = health_valid && p2_active && p2_hurt && p2_tile==health_tile && !take_health_p1;
    wire take_mag_p1 = mag_valid && p1_active && p1_tile==mag_tile;
    wire take_mag_p2 = mag_valid && p2_active && p2_tile==mag_tile && !take_mag_p1;

    always @(posedge clk) begin
        p1_heal<=0; p1_mag<=0; p2_heal<=0; p2_mag<=0;
        if(rst || !playing) begin
            health_valid<=0; mag_valid<=0; health_tile<=0; mag_tile<=0;
            searching<=0; search_mag<=0; relaxed<=0; tries<=0; lfsr<=8'h5A;
        end else if(place) begin
            health_valid<=0; mag_valid<=0;
            searching<=1; search_mag<=0; relaxed<=0; tries<=0;
            lfsr <= (random==8'd0) ? 8'h5A : random;     // LFSR must not be zero
        end else begin
            if(searching) begin
                if(candidate_ok) begin
                    if(search_mag) begin mag_valid<=1; mag_tile<=lfsr; searching<=0; end
                    else begin health_valid<=1; health_tile<=lfsr; search_mag<=1; end
                    relaxed<=0; tries<=0;
                end else if(tries==8'd254) begin
                    tries<=0;
                    if(!relaxed) relaxed<=1;
                    else if(search_mag) searching<=0;     // no room: skip this wave
                    else begin search_mag<=1; relaxed<=0; end
                end else tries<=tries+1'b1;
                lfsr<=lfsr_next;
            end
            if(take_health_p1 || take_health_p2) health_valid<=0;
            if(take_mag_p1 || take_mag_p2) mag_valid<=0;
            p1_heal<=take_health_p1; p2_heal<=take_health_p2;
            p1_mag<=take_mag_p1; p2_mag<=take_mag_p2;
        end
    end
endmodule
