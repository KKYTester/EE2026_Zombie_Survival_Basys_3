`timescale 1ns / 1ps
// Fixed slots keep zombie IDs stable until death; no records shift on removal.
module enemy_manager #(
    parameter integer MAX_ENEMIES = 8,
    parameter integer COORD_FRAC_BITS = 8, // supported range: 1..27
    parameter [7:0] INITIAL_HP = 8'd3,
    parameter integer ATTACK_COOLDOWN_CYCLES = 100_000_000,
    parameter TWO_PLAYERS = 0,
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
    input wire player_active, player2_active,
    input wire [7:0] player2_tile,
    input wire shot_fired_p2,
    input wire [1:0] aim_p2,
    output wire shot_ready, shot_ready_p2,
    output wire shot_hit,
    output wire shot_hit_player, // 0 = P1, 1 = P2; valid with shot_hit
    output wire player_hit, player_hit_p2,
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

    wire p1_live = !TWO_PLAYERS || player_active;
    wire p2_live = TWO_PLAYERS && player2_active;
    wire combat_enabled = playing && map_ready && !rst && !clear;
    wire ray_busy, hit_valid, fire_ray, fire_p2, shots_waiting;
    wire [7:0] ray_origin;
    wire [1:0] ray_aim;
    wire [7:0] hit_tile;
    reg hit_found, damage_pending, debug_pending;
    reg ray_player, damage_player;
    reg [ID_BITS-1:0] hit_id, damage_id;
    reg [7:0] damage_tile;

    generate if(TWO_PLAYERS) begin : g_shots
        reg pending_p1, pending_p2;
        reg [7:0] origin_p1, origin_p2;
        reg [1:0] facing_p1, facing_p2;
        wire issue_ready = combat_enabled && !ray_busy && !damage_pending;
        assign shot_ready = combat_enabled && p1_live && !pending_p1;
        assign shot_ready_p2 = combat_enabled && p2_live && !pending_p2;
        wire capture_p1 = shot_ready && shot_fired;
        wire capture_p2 = shot_ready_p2 && shot_fired_p2;
        assign fire_ray = issue_ready && (pending_p1 || pending_p2);
        assign fire_p2 = !pending_p1;
        assign ray_origin = fire_p2 ? origin_p2 : origin_p1;
        assign ray_aim = fire_p2 ? facing_p2 : facing_p1;
        assign shots_waiting = pending_p1 || pending_p2 || capture_p1 || capture_p2;

        // One mailbox per player. Resolve P1 first when both are pending.
        always @(posedge clk) begin
            if(!combat_enabled) begin pending_p1<=0; pending_p2<=0; end
            else begin
                if(fire_ray && !fire_p2) pending_p1<=0;
                if(fire_ray && fire_p2) pending_p2<=0;
                if(capture_p1) begin
                    pending_p1<=1; origin_p1<=player_tile; facing_p1<=aim;
                end
                if(capture_p2) begin
                    pending_p2<=1; origin_p2<=player2_tile; facing_p2<=aim_p2;
                end
            end
        end
    end else begin : g_single_shot
        assign shot_ready = combat_enabled && !ray_busy && !damage_pending;
        assign shot_ready_p2 = 0;
        assign fire_ray = shot_fired;
        assign fire_p2 = 0;
        assign ray_origin = player_tile;
        assign ray_aim = aim;
        assign shots_waiting = shot_fired;
    end endgenerate

    enemy_combat combat(.clk(clk),.reset(rst || clear),.enabled(playing && map_ready),
        .shot_fired(fire_ray),.player_tile(ray_origin),.aim(ray_aim),.walls(map_bits),
        .occupied(occupied),.busy(ray_busy),.hit_valid(hit_valid),.hit_tile(hit_tile));
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
    wire combat_locked = shots_waiting || ray_busy || damage_pending;
    assign shot_hit = damage_pending && playing && map_ready && !rst && !clear;
    assign shot_hit_player = damage_player;
    wire lethal_hit = shot_hit && hp[damage_id]<=8'd1;
    always @(posedge clk) begin
        if(rst || clear || !playing || !map_ready) begin
            damage_pending<=0; debug_pending<=0;
            ray_player<=0; damage_player<=0;
        end else begin
            if(fire_ray) ray_player<=fire_p2;
            damage_pending<=hit_valid && hit_found;
            if(hit_valid && hit_found) begin
                damage_id<=hit_id;
                damage_tile<=hit_tile;
                damage_player<=ray_player;
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
        .goal_active(p1_live),.goal2_active(p2_live),.goal2(player2_tile),
        .read_reachable(field_reachable),.read_direction(field_direction));
    wire can_step = candidate != old_tile &&
                    !(p1_live && candidate==target_tile) &&
                    !(p2_live && candidate==player2_tile) &&
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
                        free_found && !map_bits[spawn_tile] && !occupied[spawn_tile] &&
                        (!TWO_PLAYERS || !p1_live || spawn_tile!=player_tile) &&
                        (!p2_live || spawn_tile!=player2_tile);
    wire debug_remove = playing && !combat_locked && (debug_defeat || debug_pending) && live_found;
    wire remove_enemy = debug_remove || lethal_hit;
    wire [ID_BITS-1:0] remove_id = lethal_hit ? damage_id : live_id;
    wire [7:0] remove_tile = lethal_hit ? damage_tile :
        {pos_y[live_id][COORD_FRAC_BITS +: 4], pos_x[live_id][COORD_FRAC_BITS +: 4]};
    wire movement_enabled = playing && map_ready && !combat_locked && !spawn_busy && !spawn_req;
    wire target_changed = TWO_PLAYERS ? !field_ready : player_tile!=target_tile;
    wire apply_move = movement_enabled && !remove_enemy && !target_changed &&
                      move_state==MOVE_APPLY;
    wire [7:0] set_tile = apply_move ? candidate : spawn_tile;
    wire [7:0] clear_tile = apply_move ? old_tile : remove_tile;

    localparam integer ATTACK_TIMER_BITS =
        (ATTACK_COOLDOWN_CYCLES>1) ? $clog2(ATTACK_COOLDOWN_CYCLES) : 1;
    wire [1:0] contact_hits;
    assign player_hit=contact_hits[0];
    assign player_hit_p2=contact_hits[1];
    if(!TWO_PLAYERS) assign contact_hits[1]=0;
    genvar player_index;
    generate for(player_index=0; player_index<(TWO_PLAYERS ? 2 : 1);
                 player_index=player_index+1) begin : g_attack
        wire [7:0] contact_tile = player_index==0 ? player_tile : player2_tile;
        wire contact_enabled = combat_enabled && (player_index==0 ? p1_live : p2_live);
        reg [ATTACK_TIMER_BITS-1:0] attack_timer;
        reg [1:0] attack_dir;
        reg [7:0] attack_origin, attack_tile;
        reg attack_neighbor_valid, hit;
        assign contact_hits[player_index]=hit;

        // Probe one edge-sharing tile per clock for this player.
        always @(posedge clk) begin
            if(!contact_enabled) begin
                attack_dir<=0;
                attack_neighbor_valid<=0;
            end else begin
                attack_dir<=attack_dir+1'b1;
                attack_origin<=contact_tile;
                case(attack_dir)
                    2'd0: begin attack_tile<=contact_tile-8'd1;  attack_neighbor_valid<=contact_tile[3:0]!=0; end
                    2'd1: begin attack_tile<=contact_tile+8'd1;  attack_neighbor_valid<=contact_tile[3:0]!=15; end
                    2'd2: begin attack_tile<=contact_tile-8'd16; attack_neighbor_valid<=contact_tile[7:4]!=0; end
                    2'd3: begin attack_tile<=contact_tile+8'd16; attack_neighbor_valid<=contact_tile[7:4]!=15; end
                endcase
            end
        end

        // Multiple adjacent zombies share this player's cooldown.
        always @(posedge clk) begin
            hit<=0;
            if(!contact_enabled) attack_timer<=0;
            else if(attack_timer!=0) attack_timer<=attack_timer-1'b1;
            else if(attack_neighbor_valid && attack_origin==contact_tile &&
                    !map_bits[attack_origin] && !map_bits[attack_tile] &&
                    occupied[attack_tile] && !remove_enemy) begin
                hit<=1;
                attack_timer<=ATTACK_COOLDOWN_CYCLES-1;
            end
        end
    end endgenerate

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
