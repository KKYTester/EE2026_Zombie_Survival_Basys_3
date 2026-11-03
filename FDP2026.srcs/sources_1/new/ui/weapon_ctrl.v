`timescale 1ns / 1ps
// Pistol control: one five-state FSM in the 100 MHz clock domain.
//
//   READY --fire, ammo available--> FIRING --recoil finished--> READY
//     |                              |
//     | manual reload                | empty magazine or remembered reload
//     v                              v
//   LOWER ---------> SWAP ---------> RAISE ---------> READY
//         phase done       phase done       phase done
//
// Each reload phase uses the same timer and lasts 2^RELOAD_SHIFT + 1 clocks,
// preserving the previous controller's exact timing. Ammo refills when SWAP
// ends. Fire is ignored during recoil/reload; reload during recoil is remembered.
// Leaving play resets the weapon to a full magazine with the gun raised.
//
// state and reload_phase remain compatible status outputs for existing users.
// They are decoded from weapon_phase, not separate state registers or FSMs.
// drop: 0 = gun raised, 31 = fully hidden.
module weapon_ctrl #(parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23,
                     parameter RELOAD_SHIFT=25, parameter MAG_SIZE=6)(
    input wire clk, input wire rst, input wire playing,
    input wire fire, input wire reload,          // one-clock requests
    output wire flash, output wire recoil, output reg shot_fired,
    output reg [2:0] ammo,
    output wire reloading,
    output reg [4:0] drop,
    output reg [1:0] state, output reg [1:0] reload_phase);
    localparam [2:0] W_READY=3'd0, W_FIRING=3'd1, W_LOWER=3'd2,
                     W_SWAP=3'd3, W_RAISE=3'd4;
    localparam [2:0] FULL = MAG_SIZE;
    localparam MAX_SHIFT = (RECOIL_SHIFT > RELOAD_SHIFT) ? RECOIL_SHIFT : RELOAD_SHIFT;
    reg [2:0] weapon_phase;
    reg [MAX_SHIFT:0] timer;
    reg reload_pending;

    assign recoil = weapon_phase==W_FIRING;
    assign flash = recoil && ((timer >> FLASH_SHIFT) == 0);
    assign reloading = weapon_phase==W_LOWER || weapon_phase==W_SWAP || weapon_phase==W_RAISE;
    wire phase_done = timer[RELOAD_SHIFT];
    wire [4:0] phase_pos = phase_done ? 5'd31 : timer[RELOAD_SHIFT-1 -: 5];

    // Compatibility status and animation are purely combinational decodes.
    always @* begin
        state=2'd0; reload_phase=2'd0; drop=5'd0;
        case(weapon_phase)
            W_FIRING: state=2'd1;
            W_LOWER: begin state=2'd2; reload_phase=2'd1; drop=phase_pos; end
            W_SWAP:  begin state=2'd2; reload_phase=2'd2; drop=5'd31; end
            W_RAISE: begin state=2'd2; reload_phase=2'd3; drop=5'd31-phase_pos; end
            default: ;
        endcase
    end

    always @(posedge clk) begin
        if(rst || !playing) begin
            weapon_phase<=W_READY; timer<=0; ammo<=FULL;
            shot_fired<=0; reload_pending<=0;
        end else begin
            shot_fired<=0;
            case(weapon_phase)
                W_READY: begin
                    // As before, a valid fire request takes priority over reload.
                    if(fire && ammo!=0) begin
                        weapon_phase<=W_FIRING; timer<=0;
                        shot_fired<=1; ammo<=ammo-1'b1;
                    end else if((reload && ammo!=FULL) || ammo==0) begin
                        weapon_phase<=W_LOWER; timer<=0;
                    end
                end
                W_FIRING: begin
                    if(reload) reload_pending<=1;
                    if(timer[RECOIL_SHIFT]) begin
                        timer<=0; reload_pending<=0;
                        if(ammo==0 || ((reload_pending || reload) && ammo!=FULL))
                            weapon_phase<=W_LOWER;
                        else weapon_phase<=W_READY;
                    end else timer<=timer+1'b1;
                end
                W_LOWER: begin
                    if(phase_done) begin
                        timer<=0; weapon_phase<=W_SWAP;
                    end else timer<=timer+1'b1;
                end
                W_SWAP: begin
                    if(phase_done) begin
                        timer<=0; ammo<=FULL; weapon_phase<=W_RAISE;
                    end else timer<=timer+1'b1;
                end
                W_RAISE: begin
                    if(phase_done) begin
                        timer<=0; weapon_phase<=W_READY;
                    end else timer<=timer+1'b1;
                end
                default: weapon_phase<=W_READY;
            endcase
        end
    end
endmodule
