`timescale 1ns / 1ps
// Weapon feedback timing (100 MHz domain). A fire request during play starts:
//  - flash:  muzzle flash for 2^FLASH_SHIFT clocks (~42 ms, about 3 frames);
//  - recoil: gun kicked down for 2^RECOIL_SHIFT clocks (~84 ms).
// Requests during the recoil are ignored (fire rate ~12 shots/s), and each
// accepted shot pulses shot_fired once -- the signal combat (Member 2) consumes.
// This is shot feedback only; whether a zombie is hit is decided by combat.
module weapon_ctrl #(parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23)(
    input wire clk, input wire rst, input wire playing, input wire fire,
    output wire flash, output wire recoil, output reg shot_fired);
    reg [RECOIL_SHIFT:0] timer;
    reg active;
    assign recoil = active;
    // Flash only while the counter is still below 2^FLASH_SHIFT (not just one bit,
    // which would toggle again later in the recoil).
    assign flash = active && ((timer >> FLASH_SHIFT) == 0);
    always @(posedge clk) begin
        if(rst || !playing) begin timer<=0; active<=0; shot_fired<=0; end
        else begin
            shot_fired<=0;
            if(active) begin
                if(timer[RECOIL_SHIFT]) active<=0;
                else timer<=timer+1'b1;
            end else if(fire) begin
                active<=1; timer<=0; shot_fired<=1;
            end
        end
    end
endmodule
