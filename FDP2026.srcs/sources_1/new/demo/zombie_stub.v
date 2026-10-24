`timescale 1ns / 1ps
// TEMPORARY stand-in for the enemy module (Member 2) so waves can be tested:
//  - accepts every spawn request (spawn_ack one clock later) and remembers the
//    tile in one of SLOTS slots (zombies do not move; SLOTS >= the wave controller's MAX_ALIVE);
//  - defeat (btnR in the demo) removes the oldest zombie and pulses enemy_defeated;
//  - occupied[] marks the tiles holding zombies (used for spawning and the map dots).
// Replace with Member 2's enemy module, which implements the same handshake.
module zombie_stub #(parameter SLOTS=8)(
    input wire clk, input wire rst, input wire clear,
    input wire spawn_req, input wire [7:0] spawn_tile,
    input wire defeat,
    output reg spawn_ack, output reg enemy_defeated,
    output reg [255:0] occupied);
    reg [7:0] slot_tile [0:SLOTS-1];
    reg [SLOTS-1:0] slot_used;
    integer i;
    reg [255:0] mask;
    always @* begin
        mask=0;
        for(i=0;i<SLOTS;i=i+1) if(slot_used[i]) mask[slot_tile[i]]=1'b1;
    end
    always @(posedge clk) occupied<=mask;
    // Free slot: lowest unused index. Oldest zombie: slot 0 after shifting.
    reg found_free; reg [3:0] free_index;
    always @* begin
        found_free=0; free_index=0;
        for(i=SLOTS-1;i>=0;i=i-1) if(!slot_used[i]) begin found_free=1; free_index=i; end
    end
    always @(posedge clk) begin
        if(rst || clear) begin
            slot_used<=0; spawn_ack<=0; enemy_defeated<=0;
            for(i=0;i<SLOTS;i=i+1) slot_tile[i]<=0;
        end else begin
            spawn_ack<=0; enemy_defeated<=0;
            if(defeat && slot_used[0]) begin
                // Remove the oldest (slot 0) and shift the rest down.
                for(i=0;i<SLOTS-1;i=i+1) begin
                    slot_tile[i]<=slot_tile[i+1]; slot_used[i]<=slot_used[i+1];
                end
                slot_used[SLOTS-1]<=0;
                enemy_defeated<=1;
            end else if(spawn_req && !spawn_ack && found_free) begin
                slot_tile[free_index]<=spawn_tile; slot_used[free_index]<=1; spawn_ack<=1;
            end
        end
    end
endmodule
