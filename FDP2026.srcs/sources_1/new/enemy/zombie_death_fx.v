`timescale 1ns / 1ps
// Display-only death animation for the zombie sprites (Minecraft style:
// the zombie turns red and tips over sideways, then disappears).
// enemy_manager frees a slot as soon as the zombie dies. This module notices
// a slot going inactive during play and keeps drawing it as a corpse at its
// last position for 2^STEP_SHIFT * TOTAL_STEPS clocks:
//   steps 0..15  fall = step (rotates 0..90 degrees)
//   steps 16..   fall = 15 (lying on the floor)
// A new spawn into the slot, or leaving play, ends the corpse at once.
// Works the same on the follower board, from the zombie list it receives.
module zombie_death_fx #(
    parameter integer SLOTS = 8,
    parameter integer W = 12,              // coordinate width per slot
    parameter integer STEP_SHIFT = 21,     // 2^21 clocks = 21 ms per step
    parameter integer TOTAL_STEPS = 28     // ~0.6 s: 0.34 s falling, 0.25 s lying
)(
    input wire clk, input wire rst,
    input wire playing,
    input wire [SLOTS-1:0] active,
    input wire [W*SLOTS-1:0] in_x, in_y,
    input wire [2*SLOTS-1:0] in_hp,
    output wire [SLOTS-1:0] draw_active,
    output wire [W*SLOTS-1:0] draw_x, draw_y,
    output wire [2*SLOTS-1:0] draw_hp,
    output wire [SLOTS-1:0] dying,
    output wire [4*SLOTS-1:0] fall
);
    reg [STEP_SHIFT-1:0] tick_count;
    wire tick = &tick_count;
    always @(posedge clk)
        if(rst) tick_count <= 0; else tick_count <= tick_count + 1'b1;

    genvar s;
    generate for(s = 0; s < SLOTS; s = s + 1) begin : g_slot
        reg was_active, corpse;
        reg [W-1:0] last_x, last_y;
        reg [4:0] step;
        always @(posedge clk) begin
            if(rst || !playing) begin
                corpse <= 0; step <= 0;
            end else if(active[s]) begin
                corpse <= 0; step <= 0;             // a new zombie owns the slot
            end else if(was_active) begin
                corpse <= 1; step <= 0;             // just died: start falling
            end else if(corpse && tick) begin
                if(step == TOTAL_STEPS-1) corpse <= 0;
                else step <= step + 1'b1;
            end
            if(active[s]) begin
                last_x <= in_x[s*W +: W]; last_y <= in_y[s*W +: W];
            end
            was_active <= !rst && playing && active[s];
        end
        assign draw_active[s] = active[s] || corpse;
        assign dying[s] = !active[s] && corpse;
        assign draw_x[s*W +: W] = active[s] ? in_x[s*W +: W] : last_x;
        assign draw_y[s*W +: W] = active[s] ? in_y[s*W +: W] : last_y;
        assign draw_hp[2*s +: 2] = active[s] ? in_hp[2*s +: 2] : 2'd0;
        assign fall[4*s +: 4] = step > 5'd15 ? 4'd15 : step[3:0];
    end endgenerate
endmodule
