`timescale 1ns / 1ps
// Fixed slots keep zombie IDs stable until death; no records shift on removal.
module enemy_manager #(
    parameter integer MAX_ENEMIES = 8,
    parameter integer COORD_FRAC_BITS = 8, // supported range: 1..27
    parameter [7:0] INITIAL_HP = 8'd3,
    parameter integer ID_BITS = (MAX_ENEMIES > 1) ? $clog2(MAX_ENEMIES) : 1
)(
    input wire clk, rst, clear, playing, map_ready,
    input wire [255:0] map_bits,
    input wire spawn_req,
    input wire [7:0] spawn_tile,
    input wire debug_defeat, // one pulse removes the lowest active slot
    input wire move_tick, spawn_busy,
    input wire [7:0] player_tile,
    output reg spawn_ack, enemy_defeated,
    output reg [255:0] occupied,
    output reg [MAX_ENEMIES-1:0] active,
    // Combinational record lookup for debugging and future consumers.
    input wire [ID_BITS-1:0] read_id,
    output reg read_active,
    output reg [31:0] read_x, read_y,
    output reg [7:0] read_hp,
    output reg [1:0] read_type, read_state,
    output reg [15:0] read_cooldown
);
    localparam [31:0] HALF_TILE = 32'd1 << (COORD_FRAC_BITS-1);
    localparam [1:0] IDLE = 2'd0;
    reg [31:0] pos_x [0:MAX_ENEMIES-1];
    reg [31:0] pos_y [0:MAX_ENEMIES-1];
    reg [7:0] hp [0:MAX_ENEMIES-1];
    reg [1:0] kind [0:MAX_ENEMIES-1];
    reg [1:0] behaviour [0:MAX_ENEMIES-1];
    reg [15:0] cooldown [0:MAX_ENEMIES-1];
    reg request_seen;
    reg free_found, live_found;
    reg [ID_BITS-1:0] free_id, live_id;
    integer select_i, reset_i;

    localparam [2:0] MOVE_IDLE=0, MOVE_READ=1, MOVE_PLAN=2, MOVE_CHECK=3, MOVE_APPLY=4;
    reg [2:0] move_state;
    reg [ID_BITS-1:0] move_id;
    reg [7:0] old_tile, target_tile, candidate, fallback;
    wire [3:0] x = old_tile[3:0], y = old_tile[7:4];
    wire [3:0] tx = target_tile[3:0], ty = target_tile[7:4];
    wire [3:0] dx = (x < tx) ? tx-x : x-tx;
    wire [3:0] dy = (y < ty) ? ty-y : y-ty;
    // Stepping toward an in-range target cannot wrap across a map edge.
    wire [3:0] next_x = (x < tx) ? x+4'd1 : (x > tx) ? x-4'd1 : x;
    wire [3:0] next_y = (y < ty) ? y+4'd1 : (y > ty) ? y-4'd1 : y;
    wire [7:0] x_step = {y,next_x}, y_step = {next_y,x};
    wire can_step = candidate != old_tile && candidate != target_tile &&
                    !map_bits[candidate] && !occupied[candidate];

    function [31:0] tile_center(input [3:0] tile_axis);
        tile_center = ({28'd0,tile_axis} << COORD_FRAC_BITS) + HALF_TILE;
    endfunction

    // Priority encoders: choose the lowest free/live index.
    always @* begin
        free_found=0; live_found=0; free_id=0; live_id=0;
        for(select_i=0; select_i<MAX_ENEMIES; select_i=select_i+1) begin
            if(!active[select_i] && !free_found) begin
                free_found=1; free_id=select_i;
            end
            if(active[select_i] && !live_found) begin
                live_found=1; live_id=select_i;
            end
        end
    end

    // Inactive/invalid IDs return zeros instead of stale records.
    always @* begin
        read_active=0; read_x=0; read_y=0; read_hp=0;
        read_type=0; read_state=0; read_cooldown=0;
        if(read_id<MAX_ENEMIES) begin
            if(active[read_id]) begin
                read_active=1;
                read_x=pos_x[read_id]; read_y=pos_y[read_id];
                read_hp=hp[read_id]; read_type=kind[read_id];
                read_state=behaviour[read_id]; read_cooldown=cooldown[read_id];
            end
        end
    end

    wire accept_spawn = playing && map_ready && spawn_req && !request_seen &&
                        free_found && !map_bits[spawn_tile] && !occupied[spawn_tile];
    wire [7:0] remove_tile = {pos_y[live_id][COORD_FRAC_BITS +: 4],
                              pos_x[live_id][COORD_FRAC_BITS +: 4]};
    wire remove_enemy = playing && debug_defeat && live_found;
    wire movement_enabled = playing && map_ready && !spawn_busy && !spawn_req;
    wire apply_move = movement_enabled && !remove_enemy && move_state==MOVE_APPLY;
    wire [7:0] set_tile = apply_move ? candidate : spawn_tile;
    wire [7:0] clear_tile = apply_move ? old_tile : remove_tile;

    // Read, plan, check and apply one slot at a time.
    always @(posedge clk) begin
        if(rst || clear || !playing || !map_ready) begin
            move_state<=MOVE_IDLE; move_id<=0; target_tile<=0;
            old_tile<=0; candidate<=0; fallback<=0;
        end else if(move_state!=MOVE_IDLE && (!movement_enabled || remove_enemy)) begin
            // Restart the slot if spawn selection or a removal interrupts it.
            move_state<=MOVE_READ;
        end else if(movement_enabled && !remove_enemy) begin
            case(move_state)
                MOVE_IDLE: if(move_tick) begin
                    move_id<=0; target_tile<=player_tile; move_state<=MOVE_READ;
                end
                MOVE_READ: if(active[move_id]) begin
                    old_tile<={pos_y[move_id][COORD_FRAC_BITS +: 4],
                               pos_x[move_id][COORD_FRAC_BITS +: 4]};
                    move_state<=MOVE_PLAN;
                end else if(move_id==MAX_ENEMIES-1) move_state<=MOVE_IDLE;
                else move_id<=move_id+1'b1;
                MOVE_PLAN: begin
                    candidate <= (dx>=dy) ? x_step : y_step;
                    fallback <= (dx>=dy) ? y_step : x_step;
                    move_state<=MOVE_CHECK;
                end
                MOVE_CHECK: if(can_step) move_state<=MOVE_APPLY;
                else if(candidate!=fallback) candidate<=fallback;
                else if(move_id==MAX_ENEMIES-1) move_state<=MOVE_IDLE;
                else begin move_id<=move_id+1'b1; move_state<=MOVE_READ; end
                MOVE_APPLY: if(move_id==MAX_ENEMIES-1) move_state<=MOVE_IDLE;
                else begin move_id<=move_id+1'b1; move_state<=MOVE_READ; end
                default: move_state<=MOVE_IDLE;
            endcase
        end
    end
    always @(posedge clk) begin
        spawn_ack<=0; enemy_defeated<=0;
        if(rst || clear) begin
            active<=0; occupied<=0; request_seen<=0;
            for(reset_i=0; reset_i<MAX_ENEMIES; reset_i=reset_i+1) begin
                pos_x[reset_i]<=0; pos_y[reset_i]<=0; hp[reset_i]<=0;
                kind[reset_i]<=0; behaviour[reset_i]<=IDLE; cooldown[reset_i]<=0;
            end
        end else begin
            // Share two mask writes across movement, spawning and removal.
            if(accept_spawn || apply_move) occupied[set_tile]<=1;
            if(remove_enemy || apply_move) occupied[clear_tile]<=0;
            // A held request is accepted once; a low cycle rearms it.
            if(!spawn_req) request_seen<=0;
            if(accept_spawn) begin
                active[free_id]<=1;
                pos_x[free_id]<=tile_center(spawn_tile[3:0]);
                pos_y[free_id]<=tile_center(spawn_tile[7:4]);
                hp[free_id]<=INITIAL_HP; kind[free_id]<=0;
                behaviour[free_id]<=IDLE; cooldown[free_id]<=0;
                spawn_ack<=1; request_seen<=1;
            end
            // Free/live selectors use pre-edge state, so simultaneous updates
            // target different slots. A full pool retries on the next cycle.
            if(remove_enemy) begin
                active[live_id]<=0; hp[live_id]<=0;
                behaviour[live_id]<=IDLE; cooldown[live_id]<=0;
                enemy_defeated<=1;
            end
            if(apply_move) begin
                pos_x[move_id]<=tile_center(candidate[3:0]);
                pos_y[move_id]<=tile_center(candidate[7:4]);
            end
        end
    end
endmodule
