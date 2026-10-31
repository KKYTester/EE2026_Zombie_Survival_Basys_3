`timescale 1ns / 1ps
// Pistol control (100 MHz domain): a main FSM with a reload sub-machine.
//
//   Main FSM                              Reload sub-machine (only in W_RELOAD)
//   W_READY  --fire, ammo>0------> W_FIRING    R_LOWER : gun slides down out of view
//   W_FIRING --recoil done-------> W_READY     R_SWAP  : gun hidden, magazine refilled
//            (W_RELOAD instead if the          R_RAISE : gun slides back up
//             magazine is empty or a           each phase lasts 2^RELOAD_SHIFT clocks
//             reload was asked)                (3 x 2^25 clocks = about 1 s in total)
//   W_READY  --reload, not full--> W_RELOAD
//   W_RELOAD --R_RAISE done------> W_READY
//
//  - fire: shot_fired pulses once, ammo drops by one, muzzle flash for
//    2^FLASH_SHIFT clocks and recoil for 2^RECOIL_SHIFT clocks. Fire requests
//    during recoil or reload are ignored.
//  - The last round starts a reload automatically when its recoil ends.
//  - reload (btnL / right-click) is accepted when the magazine is not full;
//    pressed during recoil it is remembered and starts when the recoil ends.
//  - The magazine is refilled at the end of R_SWAP.
//  - Leaving play resets everything: every game starts with a full magazine.
// drop is how far the gun is lowered (0 = normal, 31 = fully hidden).
module weapon_ctrl #(parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23,
                     parameter RELOAD_SHIFT=25, parameter MAG_SIZE=6)(
    input wire clk, input wire rst, input wire playing,
    input wire fire, input wire reload,          // one-clock requests
    output wire flash, output wire recoil, output reg shot_fired,
    output reg [2:0] ammo,
    output wire reloading,
    output reg [4:0] drop,
    output reg [1:0] state, output reg [1:0] reload_phase);
    localparam W_READY=2'd0, W_FIRING=2'd1, W_RELOAD=2'd2;
    localparam R_IDLE=2'd0, R_LOWER=2'd1, R_SWAP=2'd2, R_RAISE=2'd3;
    localparam [2:0] FULL = MAG_SIZE;
    localparam MAX_SHIFT = (RECOIL_SHIFT > RELOAD_SHIFT) ? RECOIL_SHIFT : RELOAD_SHIFT;
    reg [MAX_SHIFT:0] timer;
    reg reload_pending;
    assign recoil = state==W_FIRING;
    // Flash only while the counter is still below 2^FLASH_SHIFT.
    assign flash = state==W_FIRING && ((timer >> FLASH_SHIFT) == 0);
    assign reloading = state==W_RELOAD;
    wire phase_done = timer[RELOAD_SHIFT];
    // 0..31 through a phase (held at 31 on its last clock).
    wire [4:0] phase_pos = phase_done ? 5'd31 : timer[RELOAD_SHIFT-1 -: 5];
    always @* begin
        case(reload_phase)
            R_LOWER: drop = phase_pos;
            R_SWAP:  drop = 5'd31;
            R_RAISE: drop = 5'd31 - phase_pos;
            default: drop = 5'd0;
        endcase
        if(state!=W_RELOAD) drop = 5'd0;
    end
    always @(posedge clk) begin
        if(rst || !playing) begin
            state<=W_READY; reload_phase<=R_IDLE; timer<=0; ammo<=FULL;
            shot_fired<=0; reload_pending<=0;
        end else begin
            shot_fired<=0;
            case(state)
                W_READY: begin
                    if(fire && ammo!=0) begin
                        state<=W_FIRING; timer<=0; shot_fired<=1; ammo<=ammo-1'b1;
                    end else if((reload && ammo!=FULL) || ammo==0) begin
                        state<=W_RELOAD; reload_phase<=R_LOWER; timer<=0;
                    end
                end
                W_FIRING: begin
                    if(reload) reload_pending<=1;
                    if(timer[RECOIL_SHIFT]) begin
                        timer<=0; reload_pending<=0;
                        if(ammo==0 || ((reload_pending || reload) && ammo!=FULL)) begin
                            state<=W_RELOAD; reload_phase<=R_LOWER;
                        end else state<=W_READY;
                    end else timer<=timer+1'b1;
                end
                W_RELOAD: begin
                    // ---- reload sub-machine ----
                    if(phase_done) begin
                        timer<=0;
                        case(reload_phase)
                            R_LOWER: reload_phase<=R_SWAP;
                            R_SWAP:  begin reload_phase<=R_RAISE; ammo<=FULL; end
                            default: begin reload_phase<=R_IDLE; state<=W_READY; end
                        endcase
                    end else timer<=timer+1'b1;
                end
                default: begin state<=W_READY; reload_phase<=R_IDLE; end
            endcase
        end
    end
endmodule
