`timescale 1ns / 1ps
// Player health, owned by game_core: 3 hearts at the start of every game.
// Each player_hit pulse from combat (Member 2) during play costs one heart and
// pulses damage once (red tint). Hits outside play or at 0 hearts are ignored.
module player_health(
    input wire clk, input wire rst,
    input wire play_start, input wire playing,
    input wire hit,                              // one-clock pulse per hit
    output reg [1:0] health,
    output reg damage);                          // one-clock pulse per heart lost
    always @(posedge clk) begin
        if(rst) begin health<=3; damage<=0; end
        else begin
            damage<=0;
            if(play_start) health<=3;
            else if(playing && hit && health!=0) begin health<=health-1'b1; damage<=1; end
        end
    end
endmodule
