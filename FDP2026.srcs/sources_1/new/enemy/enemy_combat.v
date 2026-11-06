`timescale 1ns / 1ps
// Cardinal hitscan. A ray ends at the map edge, a wall or the first enemy.
module enemy_combat #(parameter USE_CAMERA_RAY=0)(
    input wire clk, reset, enabled, shot_fired,
    input wire [7:0] player_tile,
    input wire [1:0] aim,
    input wire [255:0] walls, occupied,
    input wire [31:0] camera_x, camera_y,
    input wire [9:0] camera_angle,
    output wire busy,
    output reg hit_valid,
    output reg [7:0] hit_tile
);
    localparam [1:0] IDLE=0, STEP=1, SAMPLE=2, RESOLVE=3;
    reg [1:0] state, direction;
    reg [7:0] tile, next_tile;
    reg in_bounds, wall, enemy;
    generate if(USE_CAMERA_RAY) begin : g_camera_ray
        wire [255:0] collision_map;
        genvar row;
        for(row=0;row<16;row=row+1) begin : g_rows
            assign collision_map[row*16 +:16] =
                walls[(15-row)*16 +:16] | occupied[(15-row)*16 +:16];
        end
        reg [255:0] ray_map;
        reg launch;
        wire ray_busy, ray_done, ray_hit;
        wire [7:0] north_tile;
        wire [7:0] map_tile = {4'd15-north_tile[7:4],north_tile[3:0]};
        reg [31:0] origin_x, origin_y;
        reg [9:0] heading;
        assign busy=launch || ray_busy || ray_done || hit_valid;
        Ray_Caster #(.USE_RUNTIME_MAP(1)) ray(
            .clk(clk),.reset(reset || !enabled),.start(launch),.map_bits(ray_map),
            .player_x(origin_x[17:0]),.player_y(origin_y[17:0]),.angle(heading),
            .projection_cosine(13'd4096),.busy(ray_busy),.done(ray_done),.hit(ray_hit),
            .height(),.distance_steps(),.depth_steps(),.hit_tile(north_tile));
        always @(posedge clk) begin
            launch<=0; hit_valid<=0;
            if(reset || !enabled) launch<=0;
            else begin
                if(shot_fired && !busy) begin
                    ray_map<=collision_map; origin_x<=camera_x; origin_y<=camera_y;
                    heading<=camera_angle; launch<=1;
                end
                if(ray_done && ray_hit && !walls[map_tile] && occupied[map_tile]) begin
                    hit_tile<=map_tile; hit_valid<=1;
                end
            end
        end
    end else begin : g_cardinal_ray
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
    end endgenerate
endmodule
