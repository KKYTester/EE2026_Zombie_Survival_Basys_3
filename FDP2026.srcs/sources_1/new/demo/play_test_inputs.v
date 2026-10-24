`timescale 1ns / 1ps
// TEMPORARY stand-in for player health until combat (Member 2) exists.
// During play btnD takes one heart. Every game starts with 3 hearts.
// Replace health/damage with Member 2's authoritative player health.
module play_test_inputs(
    input wire clk, input wire rst,
    input wire play_start, input wire playing,
    input wire btn_d,                            // one-clock pulse
    output reg [1:0] health,
    output reg damage);                          // one-clock pulse per heart lost
    always @(posedge clk) begin
        if(rst) begin health<=3; damage<=0; end
        else begin
            damage<=0;
            if(play_start) health<=3;
            else if(playing) begin
                if(btn_d && health!=0) begin health<=health-1'b1; damage<=1; end
            end
        end
    end
endmodule
