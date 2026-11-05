`timescale 1ns / 1ps
`include "Game_Config.vh"

// One fixed-step ray, one map check per system-clock cycle.
// Raw distance and perpendicular camera depth are in 1/32-cell steps.
module Ray_Caster #(
    parameter [255:0] MAP = `GAME_MAP,
    parameter [9:0] MAX_STEPS = 10'd768,
    parameter USE_RUNTIME_MAP = 0
) (
    input wire clk, reset, start,
    input wire [255:0] map_bits, // hold stable from start through done
    input wire signed [17:0] player_x, player_y, // signed, 12 fractional bits
    input wire [9:0] angle,
    // round(4096*cos(ray_angle-view_angle)), unsigned Q1.12, 0..4096.
    // Use 4096 for an uncorrected ray. Captured with the other start inputs.
    input wire [12:0] projection_cosine,
    output wire busy,
    output reg done, hit,
    output reg [6:0] height,
    output reg [9:0] distance_steps,
    output reg [9:0] depth_steps
);
    localparam [2:0] IDLE=0, SETUP=1, TRACE=2, CORRECT=3, PROJECT=4;
    reg [2:0] state;
    reg signed [17:0] ray_x, ray_y;
    reg signed [8:0] step_x, step_y;
    reg [9:0] saved_angle, steps;
    reg [12:0] saved_cosine;
    // 10x13-bit product plus half an LSB: round to the nearest depth step.
    // Clamp the factor on capture so the corrected depth cannot exceed steps.
    wire [22:0] depth_product = steps * saved_cosine;
    wire [22:0] rounded_depth = depth_product + 23'd2048;
    wire [9:0] cosine_angle = saved_angle + 10'd256;
    wire in_bounds = ray_x >= 18'sd0 && ray_x < 18'sd65536 &&
                     ray_y >= 18'sd0 && ray_y < 18'sd65536;
    wire [255:0] active_map = USE_RUNTIME_MAP ? map_bits : MAP;
    wire wall = in_bounds ? active_map[{ray_y[15:12], ray_x[15:12]}] : 1'b0;
    assign busy = state != IDLE;

    // All division here is evaluated once at elaboration, producing a ROM.
    // height = min(64, floor(64 / (depth_steps/32))). Depths 0..32 saturate.
    (* rom_style = "distributed" *) reg [6:0] height_lut [0:1023];
    integer k;
    initial begin
        for (k=0; k<1024; k=k+1) begin
            if (k <= 32) height_lut[k] = 7'd64;
            else height_lut[k] = 2048 / k;
        end
    end
    // Generated constant functions, including the quarter-wave sine table.
    `include "Ray_Tables.vh"

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            hit <= 0;
            height <= 0;
            distance_steps <= 10'h3ff;
            depth_steps <= 10'h3ff;
            ray_x <= 0;
            ray_y <= 0;
            step_x <= 0;
            step_y <= 0;
            saved_angle <= 0;
            saved_cosine <= 13'd4096;
            steps <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if (start) begin
                    ray_x <= player_x;
                    ray_y <= player_y;
                    saved_angle <= angle;
                    saved_cosine <= projection_cosine > 13'd4096 ? 13'd4096 : projection_cosine;
                    steps <= 0;
                    hit <= 0;
                    height <= 0;
                    distance_steps <= 10'h3ff;
                    depth_steps <= 10'h3ff;
                    state <= SETUP;
                end
                SETUP: begin
                    // round(128*sin(angle)): 1/32-cell step in Q*.12.
                    step_x <= sine_step(saved_angle);
                    step_y <= sine_step(cosine_angle);
                    state <= TRACE;
                end
                TRACE: begin
                    if (!in_bounds) begin
                        done <= 1;
                        state <= IDLE;
                    end else if (wall) begin
                        hit <= 1;
                        distance_steps <= steps;
                        state <= CORRECT;
                    end else if (steps == MAX_STEPS) begin
                        done <= 1;
                        state <= IDLE;
                    end else begin
                        ray_x <= ray_x + {{9{step_x[8]}},step_x};
                        ray_y <= ray_y + {{9{step_y[8]}},step_y};
                        steps <= steps + 1'b1;
                    end
                end
                CORRECT: begin
                    depth_steps <= rounded_depth[21:12];
                    state <= PROJECT;
                end
                PROJECT: begin
                    height <= height_lut[depth_steps];
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
