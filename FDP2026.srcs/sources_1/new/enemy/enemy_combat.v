`timescale 1ns / 1ps
// Cardinal hitscan. A ray ends at the map edge, a wall or the first enemy.
module enemy_combat(
    input wire clk, reset, enabled, shot_fired,
    input wire [7:0] player_tile,
    input wire [1:0] aim,
    input wire [255:0] walls, occupied,
    output wire busy,
    output reg hit_valid,
    output reg [7:0] hit_tile
);
    localparam [1:0] IDLE=0, STEP=1, SAMPLE=2, RESOLVE=3;
    reg [1:0] state, direction;
    reg [7:0] tile, next_tile;
    reg in_bounds, wall, enemy;
    assign busy = state!=IDLE || hit_valid;

    always @* begin
        case(direction)
            2'd0: begin next_tile=tile+8'd1;  in_bounds=tile[3:0]!=15; end
            2'd1: begin next_tile=tile+8'd16; in_bounds=tile[7:4]!=15; end
            2'd2: begin next_tile=tile-8'd1;  in_bounds=tile[3:0]!=0; end
            2'd3: begin next_tile=tile-8'd16; in_bounds=tile[7:4]!=0; end
            default: begin next_tile=tile; in_bounds=0; end
        endcase
    end

    always @(posedge clk) begin
        hit_valid<=0;
        if(reset || !enabled) state<=IDLE;
        else case(state)
            // Weapon recoil spaces accepted shots farther apart than a full ray.
            IDLE: if(shot_fired) begin
                tile<=player_tile;
                direction<=aim;
                state<=STEP;
            end
            STEP: if(in_bounds) begin
                tile<=next_tile;
                state<=SAMPLE;
            end else state<=IDLE;
            SAMPLE: begin
                wall<=walls[tile];
                enemy<=occupied[tile];
                state<=RESOLVE;
            end
            RESOLVE: if(wall) state<=IDLE;
            else if(enemy) begin
                hit_tile<=tile;
                hit_valid<=1;
                state<=IDLE;
            end else state<=STEP;
            default: state<=IDLE;
        endcase
    end
endmodule
