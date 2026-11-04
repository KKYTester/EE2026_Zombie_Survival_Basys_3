`timescale 1ns / 1ps
// Fixed slots keep zombie IDs stable until death; no records shift on removal.
module enemy_manager #(
    parameter integer MAX_ENEMIES = 8,
    parameter integer COORD_FRAC_BITS = 8, // supported range: 1..27
    parameter [7:0] INITIAL_HP = 8'd3,
    parameter integer ATTACK_COOLDOWN_CYCLES = 100_000_000,
    parameter integer ID_BITS = (MAX_ENEMIES > 1) ? $clog2(MAX_ENEMIES) : 1
)(
    input wire clk, rst, clear, playing, map_ready,
    input wire [255:0] map_bits,
    input wire spawn_req,
    input wire [7:0] spawn_tile,
    input wire debug_defeat, // one pulse removes the lowest active slot
    input wire move_tick, spawn_busy,
    input wire [7:0] player_tile,
    input wire shot_fired,
    input wire [1:0] aim,
    output wire shot_hit,
    output reg player_hit,
    output reg spawn_ack, enemy_defeated,
    output reg [255:0] occupied,
    output reg [MAX_ENEMIES-1:0] active,
    output wire [MAX_ENEMIES*(COORD_FRAC_BITS+4)-1:0] render_x, render_y,
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
    genvar render_slot;
    generate for(render_slot=0; render_slot<MAX_ENEMIES; render_slot=render_slot+1) begin : g_render
        localparam integer WIDTH=COORD_FRAC_BITS+4;
        assign render_x[render_slot*WIDTH +: WIDTH]=pos_x[render_slot][WIDTH-1:0];
        assign render_y[render_slot*WIDTH +: WIDTH]=pos_y[render_slot][WIDTH-1:0];
    end endgenerate
    reg [7:0] hp [0:MAX_ENEMIES-1];
    reg [1:0] kind [0:MAX_ENEMIES-1];
    reg [1:0] behaviour [0:MAX_ENEMIES-1];
    reg [15:0] cooldown [0:MAX_ENEMIES-1];
    reg request_seen;
    reg free_found, live_found;
    reg [ID_BITS-1:0] free_id, live_id;
    integer select_i, reset_i, hit_i;

    wire ray_busy, hit_valid;
    wire [7:0] hit_tile;
    enemy_combat combat(.clk(clk),.reset(rst || clear),.enabled(playing && map_ready),
        .shot_fired(shot_fired),.player_tile(player_tile),.aim(aim),.walls(map_bits),
        .occupied(occupied),.busy(ray_busy),.hit_valid(hit_valid),.hit_tile(hit_tile));
    reg hit_found, damage_pending, debug_pending;
    reg [ID_BITS-1:0] hit_id, damage_id;
    reg [7:0] damage_tile;
    // Resolve the tile to a slot before applying damage on the next clock.
    always @* begin
        hit_found=0; hit_id=0;
        for(hit_i=0; hit_i<MAX_ENEMIES; hit_i=hit_i+1)
            if(active[hit_i] &&
               {pos_y[hit_i][COORD_FRAC_BITS +: 4],
                pos_x[hit_i][COORD_FRAC_BITS +: 4]}==hit_tile) begin
                hit_found=1;
                hit_id=hit_i;
            end
    end
    // Hold tile ownership stable from the trigger through damage commit.
    wire combat_locked = shot_fired || ray_busy || damage_pending;
    assign shot_hit = damage_pending && playing && map_ready && !rst && !clear;
    wire lethal_hit = shot_hit && hp[damage_id]<=8'd1;
    always @(posedge clk) begin
        if(rst || clear || !playing || !map_ready) begin
            damage_pending<=0; debug_pending<=0;
        end else begin
            damage_pending<=hit_valid && hit_found;
            if(hit_valid && hit_found) begin
                damage_id<=hit_id;
                damage_tile<=hit_tile;
            end
            debug_pending<=combat_locked && (debug_defeat || debug_pending);
        end
    end

    localparam [2:0] MOVE_IDLE=0, MOVE_READ=1, MOVE_LOOKUP=2, MOVE_PLAN=3,
                     MOVE_CHECK=4, MOVE_APPLY=5, MOVE_NEXT=6;
    reg [2:0] move_state;
    reg [ID_BITS-1:0] move_id, first_move_id;
    wire [ID_BITS-1:0] next_move_id =
        (move_id==MAX_ENEMIES-1) ? {ID_BITS{1'b0}} : move_id+1'b1;
    reg [7:0] old_tile, target_tile, candidate;
    wire field_ready, field_reachable;
    wire [1:0] field_direction;
    flow_field routes(.clk(clk),.reset(rst || clear),.enabled(playing && map_ready),
        .walls(map_bits),.goal(player_tile),.read_tile(old_tile),.ready(field_ready),
        .read_reachable(field_reachable),.read_direction(field_direction));
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

    wire accept_spawn = playing && map_ready && !combat_locked && spawn_req && !request_seen &&
                        free_found && !map_bits[spawn_tile] && !occupied[spawn_tile];
    wire debug_remove = playing && !combat_locked && (debug_defeat || debug_pending) && live_found;
    wire remove_enemy = debug_remove || lethal_hit;
    wire [ID_BITS-1:0] remove_id = lethal_hit ? damage_id : live_id;
    wire [7:0] remove_tile = lethal_hit ? damage_tile :
        {pos_y[live_id][COORD_FRAC_BITS +: 4], pos_x[live_id][COORD_FRAC_BITS +: 4]};
    wire movement_enabled = playing && map_ready && !combat_locked && !spawn_busy && !spawn_req;
    wire target_changed = player_tile!=target_tile;
    wire apply_move = movement_enabled && !remove_enemy && !target_changed &&
                      move_state==MOVE_APPLY;
    wire [7:0] set_tile = apply_move ? candidate : spawn_tile;
    wire [7:0] clear_tile = apply_move ? old_tile : remove_tile;

    localparam integer ATTACK_TIMER_BITS =
        (ATTACK_COOLDOWN_CYCLES>1) ? $clog2(ATTACK_COOLDOWN_CYCLES) : 1;
    reg [ATTACK_TIMER_BITS-1:0] attack_timer;
    reg [1:0] attack_dir;
    reg [7:0] attack_origin, attack_tile;
    reg attack_neighbor_valid;

    // Probe one edge-sharing tile per clock to share the occupancy lookup.
    always @(posedge clk) begin
        if(rst || clear || !playing || !map_ready) begin
            attack_dir<=0;
            attack_neighbor_valid<=0;
        end else begin
            attack_dir<=attack_dir+1'b1;
            attack_origin<=player_tile;
            case(attack_dir)
                2'd0: begin attack_tile<=player_tile-8'd1;  attack_neighbor_valid<=player_tile[3:0]!=0; end
                2'd1: begin attack_tile<=player_tile+8'd1;  attack_neighbor_valid<=player_tile[3:0]!=15; end
                2'd2: begin attack_tile<=player_tile-8'd16; attack_neighbor_valid<=player_tile[7:4]!=0; end
                2'd3: begin attack_tile<=player_tile+8'd16; attack_neighbor_valid<=player_tile[7:4]!=15; end
            endcase
        end
    end

    // One shared grace period caps damage even when several zombies are adjacent.
    always @(posedge clk) begin
        player_hit<=0;
        if(rst || clear || !playing || !map_ready) attack_timer<=0;
        else if(attack_timer!=0) attack_timer<=attack_timer-1'b1;
        else if(attack_neighbor_valid && attack_origin==player_tile &&
                !map_bits[attack_origin] && !map_bits[attack_tile] &&
                occupied[attack_tile] && !remove_enemy) begin
            player_hit<=1;
            attack_timer<=ATTACK_COOLDOWN_CYCLES-1;
        end
    end

    // Read, plan, check and apply one slot at a time.
    always @(posedge clk) begin
        if(rst || clear || !playing || !map_ready) begin
            move_state<=MOVE_IDLE; move_id<=0; first_move_id<=0; target_tile<=0;
            old_tile<=0; candidate<=0;
        end else if(move_state!=MOVE_IDLE && target_changed) begin
            move_state<=MOVE_IDLE;
        end else if(move_state!=MOVE_IDLE && (!movement_enabled || remove_enemy)) begin
            // Restart the slot if spawn selection or a removal interrupts it.
            move_state<=MOVE_READ;
        end else if(movement_enabled && !remove_enemy) begin
            case(move_state)
                MOVE_IDLE: if(move_tick && field_ready) begin
                    move_id<=first_move_id; target_tile<=player_tile; move_state<=MOVE_READ;
                end
                MOVE_READ: if(active[move_id]) begin
                    old_tile<={pos_y[move_id][COORD_FRAC_BITS +: 4],
                               pos_x[move_id][COORD_FRAC_BITS +: 4]};
                    move_state<=MOVE_LOOKUP;
                end else move_state<=MOVE_NEXT;
                MOVE_LOOKUP: move_state<=MOVE_PLAN;
                MOVE_PLAN: if(field_reachable) begin
                    case(field_direction)
                        2'd0: candidate<=old_tile-8'd1;
                        2'd1: candidate<=old_tile+8'd1;
                        2'd2: candidate<=old_tile-8'd16;
                        2'd3: candidate<=old_tile+8'd16;
                    endcase
                    move_state<=MOVE_CHECK;
                end else move_state<=MOVE_NEXT;
                MOVE_CHECK: move_state<=can_step ? MOVE_APPLY : MOVE_NEXT;
                MOVE_APPLY: move_state<=MOVE_NEXT;
                MOVE_NEXT: if(next_move_id==first_move_id) begin
                    // A full sweep is done. Rotate priority for the next tick.
                    first_move_id<=(first_move_id==MAX_ENEMIES-1) ?
                                  {ID_BITS{1'b0}} : first_move_id+1'b1;
                    move_state<=MOVE_IDLE;
                end else begin move_id<=next_move_id; move_state<=MOVE_READ; end
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
                active[remove_id]<=0; hp[remove_id]<=0;
                behaviour[remove_id]<=IDLE; cooldown[remove_id]<=0;
                enemy_defeated<=1;
            end else if(shot_hit) hp[damage_id]<=hp[damage_id]-8'd1;
            if(apply_move) begin
                pos_x[move_id]<=tile_center(candidate[3:0]);
                pos_y[move_id]<=tile_center(candidate[7:4]);
            end
        end
    end
endmodule
