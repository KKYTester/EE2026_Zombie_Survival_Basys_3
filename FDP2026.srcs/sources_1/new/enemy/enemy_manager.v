`timescale 1ns / 1ps
// Fixed slots keep zombie IDs stable until death; no records shift on removal.
module enemy_manager #(
    parameter integer MAX_ENEMIES = 8,
    parameter integer COORD_FRAC_BITS = 8, // supported range: 1..27
    parameter integer MOVE_SUBSTEPS = (COORD_FRAC_BITS>=5) ? 32 : (1<<COORD_FRAC_BITS),
    // Radii/distances below use the same fixed-point units as positions.
    parameter integer LOOKAHEAD = COORD_FRAC_BITS>=2 ? (1<<COORD_FRAC_BITS)/4 : 1,
    parameter integer HIT_RADIUS = (1<<COORD_FRAC_BITS)/4,
    parameter [7:0] INITIAL_HP = 8'd3,
    parameter integer ATTACK_COOLDOWN_CYCLES = 100_000_000,
    parameter TWO_PLAYERS = 0,
    parameter USE_CAMERA_RAY = 0,
    parameter USE_PLAYER_POSITIONS = 0,
    parameter integer ID_BITS = (MAX_ENEMIES > 1) ? $clog2(MAX_ENEMIES) : 1
)(
    input wire clk, rst, clear, playing, map_ready,
    input wire [255:0] map_bits,
    input wire spawn_req,
    input wire [7:0] spawn_tile,
    input wire debug_defeat, // one pulse removes the lowest active slot
    input wire move_tick, spawn_busy,
    input wire [7:0] player_tile,
    input wire [31:0] player_pos_x, player_pos_y, player2_pos_x, player2_pos_y,
    input wire shot_fired,
    input wire [1:0] aim,
    input wire [31:0] camera_x, camera_y,
    input wire [9:0] camera_angle,
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
    output wire [255:0] spawn_occupied,
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
    localparam integer POSITION_BITS = COORD_FRAC_BITS+4;
    localparam [1:0] IDLE = 2'd0;
    `include "Enemy_Path.vh"
    reg [31:0] pos_x [0:MAX_ENEMIES-1];
    reg [31:0] pos_y [0:MAX_ENEMIES-1];
    localparam [31:0] MOVE_STEP = (32'd1 << COORD_FRAC_BITS)/MOVE_SUBSTEPS;
    localparam [31:0] DIAGONAL_LOOKAHEAD=(64'd181*LOOKAHEAD+128)>>8;
    reg [MAX_ENEMIES-1:0] moving;
    reg [255:0] reserved;
    reg [MAX_ENEMIES-1:0] has_look_reservation;
    reg [7:0] look_reservation [0:MAX_ENEMIES-1];
    reg [7:0] travel_origin [0:MAX_ENEMIES-1], travel_destination [0:MAX_ENEMIES-1];
    reg [2:0] travel_direction [0:MAX_ENEMIES-1];
    assign spawn_occupied=occupied | reserved;
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

    enemy_combat #(.USE_CAMERA_RAY(USE_CAMERA_RAY), .MAX_ENEMIES(MAX_ENEMIES),
        .COORD_FRAC_BITS(COORD_FRAC_BITS), .HIT_RADIUS(HIT_RADIUS)) combat(
        .clk(clk),.reset(rst || clear),.enabled(playing && map_ready),
        .camera_x(camera_x),.camera_y(camera_y),.camera_angle(camera_angle),
        .shot_fired(fire_ray),.player_tile(ray_origin),.aim(ray_aim),.walls(map_bits),
        .active(active),.position_x(render_x),.position_y(render_y),
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

    localparam [4:0] MOVE_IDLE=0, MOVE_READ=1, MOVE_LOOKUP=2, MOVE_PLAN=3,
                     MOVE_CHECK=4, MOVE_APPLY=5, MOVE_NEXT=6, MOVE_ADVANCE=7,
                     MOVE_CONTACT=8, MOVE_LOOK=9, MOVE_LOOK_WAIT=10,
                     MOVE_PROJECT=11, MOVE_DISTANCE=12, MOVE_SCALE=13,
                     MOVE_OFFSET=14, MOVE_AIM=15, MOVE_DELTA=16, MOVE_BLEND=17;
    reg [4:0] move_state;
    reg [ID_BITS-1:0] move_id, first_move_id;
    wire [ID_BITS-1:0] next_move_id =
        (move_id==MAX_ENEMIES-1) ? {ID_BITS{1'b0}} : move_id+1'b1;
    reg [7:0] old_tile, target_tile, candidate;
    reg was_moving;
    reg [2:0] step_direction;
    reg [2:0] look_direction;
    reg look_valid;
    reg [7:0] look_tile;
    wire [7:0] field_read_tile = (move_state==MOVE_LOOK ||
        move_state==MOVE_LOOK_WAIT || move_state==MOVE_CONTACT) ? candidate : old_tile;
    wire field_ready, field_reachable;
    wire [2:0] field_direction;
    reg [7:0] peek_tile;
    wire [7:0] segment_origin=was_moving ? travel_origin[move_id] : old_tile;
    wire step_diagonal=segment_origin[3:0]!=candidate[3:0] && segment_origin[7:4]!=candidate[7:4];
    wire [7:0] step_side1={segment_origin[7:4],candidate[3:0]};
    wire [7:0] step_side2={candidate[7:4],segment_origin[3:0]};
    wire [7:0] peek_side1={candidate[7:4],peek_tile[3:0]};
    wire [7:0] peek_side2={peek_tile[7:4],candidate[3:0]};
    // A live trip may reuse its own cells, never another owner's cells.
    // Direct probes avoid reducing a newly decoded 256-bit footprint mask.
    function probe_available(input [7:0] probe,a,b,c,
        input in_trip,with_look, input [255:0] physical, reservations);
        begin
            probe_available=(in_trip && (segment_has(a,b,probe) ||
                (with_look && segment_has(b,c,probe)))) ||
                (!physical[probe] && !reservations[probe]);
        end
    endfunction
    wire peek_free=probe_available(peek_tile,segment_origin,candidate,look_reservation[move_id],
        was_moving,has_look_reservation[move_id],occupied,reserved);
    wire peek_side1_free=probe_available(peek_side1,segment_origin,candidate,look_reservation[move_id],
        was_moving,has_look_reservation[move_id],occupied,reserved);
    wire peek_side2_free=probe_available(peek_side2,segment_origin,candidate,look_reservation[move_id],
        was_moving,has_look_reservation[move_id],occupied,reserved);
    wire signed [6:0] turn_dot=direction_x(step_direction)*direction_x(field_direction)+
                              direction_y(step_direction)*direction_y(field_direction);
    wire peek_available=field_reachable && neighbor_valid(candidate,field_direction) &&
        turn_dot>=0 && !map_bits[peek_tile] && peek_free &&
        (!field_direction[2] || (!map_bits[peek_side1] && !map_bits[peek_side2] &&
                                peek_side1_free && peek_side2_free));
    reg [POSITION_BITS-1:0] steer_x, steer_y;
    reg signed [POSITION_BITS+2:0] steer_dx, steer_dy, velocity_x, velocity_y;
    reg signed [POSITION_BITS+2:0] along_x, along_y;
    reg [POSITION_BITS:0] axis_remaining, remaining;
    reg signed [POSITION_BITS+2:0] offset;
    reg [2:0] offset_direction;
    wire [POSITION_BITS-1:0] center_x=tile_center(candidate[3:0]);
    wire [POSITION_BITS-1:0] center_y=tile_center(candidate[7:4]);
    reg [POSITION_BITS-1:0] current_x, current_y, next_x, next_y;
    reg [POSITION_BITS-1:0] gap_x1, gap_y1, gap_x2, gap_y2;
    reg close_to_player;
    // A sign/mux operation, rather than a variable multiplier for {-1,0,1}.
    function signed [POSITION_BITS+2:0] oriented(
        input signed [POSITION_BITS+2:0] value, input signed [2:0] direction);
        begin oriented=direction<0 ? -value : direction>0 ? value : 0; end
    endfunction
    wire signed [POSITION_BITS+3:0] projected_sum=
        $signed(along_x)+$signed(along_y);
    wire signed [POSITION_BITS+3:0] projected=
        step_direction[2] ? projected_sum/2 : projected_sum;
    // Bounded constant products: no run-time division or wide direction multiply.
    (* use_dsp="no" *) wire [POSITION_BITS+9:0] scaled_axis=axis_remaining*9'd362+128;
    wire [POSITION_BITS:0] extension=remaining<LOOKAHEAD ? LOOKAHEAD-remaining : 0;
    (* use_dsp="no" *) wire [POSITION_BITS+8:0] scaled_extension=extension*8'd181+128;
    wire near_center=(current_x>center_x ? current_x-center_x : center_x-current_x)<=MOVE_STEP &&
                     (current_y>center_y ? current_y-center_y : center_y-current_y)<=MOVE_STEP;
    wire planned_arrival=MOVE_SUBSTEPS==1 ||
        (remaining<=MOVE_STEP && (look_valid || near_center));
    flow_field routes(.clk(clk),.reset(rst || clear),.enabled(playing && map_ready),
        .walls(map_bits),.goal(player_tile),.read_tile(field_read_tile),.ready(field_ready),
        .goal_active(p1_live),.goal2_active(p2_live),.goal2(player2_tile),
        .read_reachable(field_reachable),.read_direction(field_direction));
    wire can_step = (was_moving || candidate != old_tile) &&
                    (p1_live || p2_live) &&
                    (MOVE_SUBSTEPS>1 || !(p1_live && candidate==target_tile)) &&
                    (MOVE_SUBSTEPS>1 || !(p2_live && candidate==player2_tile)) &&
                    !map_bits[candidate] &&
                    (!step_diagonal || (!map_bits[step_side1] && !map_bits[step_side2])) &&
                    (was_moving || (neighbor_valid(old_tile,step_direction) &&
                     !occupied[candidate] && !reserved[candidate] &&
                     (!step_diagonal || (!occupied[step_side1] && !reserved[step_side1] &&
                                         !occupied[step_side2] && !reserved[step_side2]))));

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
                        free_found && !map_bits[spawn_tile] && !spawn_occupied[spawn_tile] &&
                        (!TWO_PLAYERS || !p1_live || spawn_tile!=player_tile) &&
                        (!p2_live || spawn_tile!=player2_tile);
    wire debug_remove = playing && !combat_locked && (debug_defeat || debug_pending) && live_found;
    wire remove_enemy = debug_remove || lethal_hit;
    wire [ID_BITS-1:0] remove_id = lethal_hit ? damage_id : live_id;
    wire [7:0] remove_tile = lethal_hit ? damage_tile :
        {pos_y[live_id][COORD_FRAC_BITS +: 4], pos_x[live_id][COORD_FRAC_BITS +: 4]};
    wire movement_enabled = playing && map_ready && !combat_locked && !spawn_busy && !spawn_req;
    wire target_changed = TWO_PLAYERS ? !field_ready : player_tile!=target_tile;
    wire [7:0] next_tile = {next_y[COORD_FRAC_BITS +:4],next_x[COORD_FRAC_BITS +:4]};
    wire apply_move = movement_enabled && !remove_enemy && !target_changed &&
                      (MOVE_SUBSTEPS==1 || !close_to_player) &&
                      move_state==MOVE_APPLY && !map_bits[next_tile] &&
                      segment_has(segment_origin,candidate,next_tile) &&
                      (next_tile==old_tile || !occupied[next_tile]);
    wire tile_changed = next_tile!=old_tile;
    reg arriving;
    wire [7:0] set_tile = apply_move ? next_tile : spawn_tile;
    wire [7:0] clear_tile = apply_move ? old_tile : remove_tile;
    wire [POSITION_BITS-1:0] target_x1 = USE_PLAYER_POSITIONS ? player_pos_x :
                                      tile_center(player_tile[3:0]);
    wire [POSITION_BITS-1:0] target_y1 = USE_PLAYER_POSITIONS ? player_pos_y :
                                      tile_center(player_tile[7:4]);
    wire [POSITION_BITS-1:0] target_x2 = USE_PLAYER_POSITIONS ? player2_pos_x :
                                      tile_center(player2_tile[3:0]);
    wire [POSITION_BITS-1:0] target_y2 = USE_PLAYER_POSITIONS ? player2_pos_y :
                                      tile_center(player2_tile[7:4]);
    wire [POSITION_BITS:0] gap1 = {1'b0,gap_x1}+{1'b0,gap_y1};
    wire [POSITION_BITS:0] gap2 = {1'b0,gap_x2}+{1'b0,gap_y2};

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
        reg [3:0] attack_dir;
        reg [7:0] attack_origin, attack_tile;
        reg attack_neighbor_valid, hit;
        wire [POSITION_BITS-1:0] contact_x = USE_PLAYER_POSITIONS ?
            (player_index==0 ? player_pos_x : player2_pos_x) : tile_center(contact_tile[3:0]);
        wire [POSITION_BITS-1:0] contact_y = USE_PLAYER_POSITIONS ?
            (player_index==0 ? player_pos_y : player2_pos_y) : tile_center(contact_tile[7:4]);
        reg found_contact;
        reg [ID_BITS-1:0] contact_id;
        integer contact_i;
        always @* begin
            found_contact=0; contact_id=0;
            for(contact_i=0;contact_i<MAX_ENEMIES;contact_i=contact_i+1)
                if(active[contact_i] &&
                   {pos_y[contact_i][COORD_FRAC_BITS +:4],
                    pos_x[contact_i][COORD_FRAC_BITS +:4]}==attack_tile) begin
                    found_contact=1; contact_id=contact_i;
                end
        end
        reg [POSITION_BITS-1:0] contact_dx, contact_dy;
        reg range_valid;
        wire [POSITION_BITS:0] contact_distance = {1'b0,contact_dx}+{1'b0,contact_dy};
        // Fractional positions prevent damage before the zombie reaches contact range.
        always @(posedge clk) begin
            range_valid<=contact_enabled && attack_neighbor_valid && found_contact &&
                         attack_origin==contact_tile && !map_bits[attack_origin] &&
                         !map_bits[attack_tile] && !remove_enemy && !accept_spawn;
            contact_dx<=pos_x[contact_id]>contact_x ?
                        pos_x[contact_id]-contact_x : contact_x-pos_x[contact_id];
            contact_dy<=pos_y[contact_id]>contact_y ?
                        pos_y[contact_id]-contact_y : contact_y-pos_y[contact_id];
            if(!contact_enabled) range_valid<=0;
        end
        wire contact_in_range = MOVE_SUBSTEPS==1 ?
            (attack_neighbor_valid && attack_origin==contact_tile &&
             !map_bits[attack_origin] && !map_bits[attack_tile] && occupied[attack_tile]) :
            (range_valid && contact_distance<=(33'd1 << COORD_FRAC_BITS));
        assign contact_hits[player_index]=hit;

        wire [7:0] contact_neighbor=neighbor_tile(contact_tile,attack_dir[2:0]);
        // Fractional movement can stop in range from a diagonal tile too.
        // Keep the original cardinal-only behavior for legacy one-step tests.
        always @(posedge clk) begin
            if(!contact_enabled) begin
                attack_dir<=0;
                attack_neighbor_valid<=0;
            end else begin
                attack_dir<=attack_dir==(MOVE_SUBSTEPS==1 ? 3 : 8) ? 0 : attack_dir+1'b1;
                attack_origin<=contact_tile;
                attack_tile<=attack_dir==8 ? contact_tile : contact_neighbor;
                attack_neighbor_valid<=attack_dir==8 ||
                    (neighbor_valid(contact_tile,attack_dir[2:0]) &&
                     (!attack_dir[2] ||
                      (!map_bits[{contact_tile[7:4],contact_neighbor[3:0]}] &&
                       !map_bits[{contact_neighbor[7:4],contact_tile[3:0]}])));
            end
        end

        // Multiple adjacent zombies share this player's cooldown.
        always @(posedge clk) begin
            hit<=0;
            if(!contact_enabled) attack_timer<=0;
            else if(attack_timer!=0) attack_timer<=attack_timer-1'b1;
            else if(contact_in_range && !remove_enemy && !accept_spawn) begin
                hit<=1;
                attack_timer<=ATTACK_COOLDOWN_CYCLES-1;
            end
        end
    end endgenerate

    wire [255:0] previous_reservation=was_moving ?
        segment_mask(travel_origin[move_id],travel_destination[move_id]) |
        (has_look_reservation[move_id] ?
         segment_mask(travel_destination[move_id],look_reservation[move_id]) : 256'd0) : 256'd0;
    wire [255:0] next_reservation=(!arriving && MOVE_SUBSTEPS>1) ?
        segment_mask(segment_origin,candidate) |
        (look_valid ? segment_mask(candidate,look_tile) : 256'd0) : 256'd0;
    wire [255:0] removed_reservation=segment_mask(travel_origin[remove_id],travel_destination[remove_id]) |
        (has_look_reservation[remove_id] ?
         segment_mask(travel_destination[remove_id],look_reservation[remove_id]) : 256'd0);
    // Read, plan, check and apply one slot at a time.
    always @(posedge clk) begin
        if(rst || clear || !playing || !map_ready) begin
            move_state<=MOVE_IDLE; move_id<=0; first_move_id<=0; target_tile<=0;
            old_tile<=0; candidate<=0; look_valid<=0; arriving<=0;
            look_direction<=0; look_tile<=0; peek_tile<=0;
            steer_x<=0; steer_y<=0; steer_dx<=0; steer_dy<=0;
            velocity_x<=0; velocity_y<=0; along_x<=0; along_y<=0;
            axis_remaining<=0; remaining<=0; offset<=0; offset_direction<=0;
            current_x<=0; current_y<=0; next_x<=0; next_y<=0;
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
                    current_x<=pos_x[move_id]; current_y<=pos_y[move_id];
                    was_moving<=moving[move_id];
                    if(moving[move_id]) begin
                        candidate<=travel_destination[move_id];
                        step_direction<=travel_direction[move_id];
                        move_state<=MOVE_CHECK;
                    end else move_state<=MOVE_LOOKUP;
                end else move_state<=MOVE_NEXT;
                MOVE_LOOKUP: move_state<=MOVE_PLAN;
                MOVE_PLAN: if(field_reachable) begin
                    step_direction<=field_direction;
                    candidate<=neighbor_tile(old_tile,field_direction);
                    move_state<=MOVE_CHECK;
                end else move_state<=MOVE_NEXT;
                MOVE_CHECK: move_state<=can_step ? MOVE_LOOK : MOVE_NEXT;
                MOVE_LOOK: move_state<=MOVE_LOOK_WAIT;
                MOVE_LOOK_WAIT: begin
                    peek_tile<=neighbor_tile(candidate,field_direction);
                    move_state<=MOVE_CONTACT;
                end
                MOVE_CONTACT: begin
                    look_valid<=peek_available && MOVE_SUBSTEPS>1;
                    look_direction<=field_direction; look_tile<=peek_tile;
                    gap_x1<=current_x>target_x1 ? current_x-target_x1 : target_x1-current_x;
                    gap_y1<=current_y>target_y1 ? current_y-target_y1 : target_y1-current_y;
                    gap_x2<=current_x>target_x2 ? current_x-target_x2 : target_x2-current_x;
                    gap_y2<=current_y>target_y2 ? current_y-target_y2 : target_y2-current_y;
                    move_state<=MOVE_SUBSTEPS==1 ? MOVE_ADVANCE : MOVE_PROJECT;
                end
                // Steering is deliberately serialized; a sweep is still <200
                // clocks for eight slots, far below the 3,125,000-clock tick.
                MOVE_PROJECT: begin
                    along_x<=oriented($signed({1'b0,center_x})-$signed({1'b0,current_x}),direction_x(step_direction));
                    along_y<=oriented($signed({1'b0,center_y})-$signed({1'b0,current_y}),direction_y(step_direction));
                    move_state<=MOVE_DISTANCE;
                end
                MOVE_DISTANCE: begin
                    axis_remaining<=projected>0 ? projected : 0;
                    move_state<=MOVE_SCALE;
                end
                MOVE_SCALE: begin
                    remaining<=step_direction[2] ? scaled_axis>>8 : axis_remaining;
                    move_state<=MOVE_OFFSET;
                end
                MOVE_OFFSET: begin
                    if(remaining>LOOKAHEAD) begin
                        offset<=$signed(step_direction[2] ? DIAGONAL_LOOKAHEAD : LOOKAHEAD)-$signed({1'b0,axis_remaining});
                        offset_direction<=step_direction;
                    end else begin
                        offset<=look_valid ? (look_direction[2] ? scaled_extension>>8 : extension) : 0;
                        offset_direction<=look_direction;
                    end
                    move_state<=MOVE_AIM;
                end
                MOVE_AIM: begin
                    steer_x<=$signed({1'b0,center_x})+oriented(offset,direction_x(offset_direction));
                    steer_y<=$signed({1'b0,center_y})+oriented(offset,direction_y(offset_direction));
                    move_state<=MOVE_DELTA;
                end
                MOVE_DELTA: begin
                    steer_dx<=$signed({1'b0,steer_x})-$signed({1'b0,current_x});
                    steer_dy<=$signed({1'b0,steer_y})-$signed({1'b0,current_y});
                    move_state<=MOVE_BLEND;
                end
                MOVE_BLEND: begin
                    velocity_x<=(steer_dx*$signed({32'd0,MOVE_STEP}))/$signed({32'd0,LOOKAHEAD});
                    velocity_y<=(steer_dy*$signed({32'd0,MOVE_STEP}))/$signed({32'd0,LOOKAHEAD});
                    move_state<=MOVE_ADVANCE;
                end
                MOVE_ADVANCE: begin
                    close_to_player<=(p1_live && (candidate==player_tile || old_tile==player_tile) &&
                                      gap1<=(33'd1 << COORD_FRAC_BITS)) ||
                                     (p2_live && (candidate==player2_tile || old_tile==player2_tile) &&
                                      gap2<=(33'd1 << COORD_FRAC_BITS));
                    // At a blended corner the endpoint tolerance is one
                    // substep; retain lateral motion instead of snapping it.
                    next_x<=MOVE_SUBSTEPS==1 || (planned_arrival && !look_valid) ?
                            center_x : $signed({1'b0,current_x})+velocity_x;
                    next_y<=MOVE_SUBSTEPS==1 || (planned_arrival && !look_valid) ?
                            center_y : $signed({1'b0,current_y})+velocity_y;
                    arriving<=planned_arrival;
                    move_state<=MOVE_APPLY;
                end
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
            active<=0; occupied<=0; reserved<=0; moving<=0; has_look_reservation<=0; request_seen<=0;
            for(reset_i=0; reset_i<MAX_ENEMIES; reset_i=reset_i+1) begin
                pos_x[reset_i]<=0; pos_y[reset_i]<=0; hp[reset_i]<=0;
                kind[reset_i]<=0; behaviour[reset_i]<=IDLE; cooldown[reset_i]<=0;
                look_reservation[reset_i]<=0;
                travel_origin[reset_i]<=0; travel_destination[reset_i]<=0;
                travel_direction[reset_i]<=0;
            end
        end else begin
            // Update the cached union atomically with its disjoint owner records.
            // Spawns see new reservations immediately; death/arrival releases all
            // endpoint/side/lookahead cells without a delayed rebuild window.
            if(apply_move) reserved<=(reserved & ~previous_reservation) | next_reservation;
            else if(remove_enemy && moving[remove_id]) reserved<=reserved & ~removed_reservation;
            // Share two mask writes across movement, spawning and removal.
            if(accept_spawn || (apply_move && tile_changed)) occupied[set_tile]<=1;
            if(remove_enemy || (apply_move && tile_changed)) occupied[clear_tile]<=0;
            // A held request is accepted once; a low cycle rearms it.
            if(!spawn_req) request_seen<=0;
            if(accept_spawn) begin
                active[free_id]<=1;
                pos_x[free_id]<=tile_center(spawn_tile[3:0]);
                pos_y[free_id]<=tile_center(spawn_tile[7:4]);
                hp[free_id]<=INITIAL_HP; kind[free_id]<=0;
                has_look_reservation[free_id]<=0;
                moving[free_id]<=0;
                behaviour[free_id]<=IDLE; cooldown[free_id]<=0;
                spawn_ack<=1; request_seen<=1;
            end
            // Free/live selectors use pre-edge state, so simultaneous updates
            // target different slots. A full pool retries on the next cycle.
            if(remove_enemy) begin
                active[remove_id]<=0; hp[remove_id]<=0;
                has_look_reservation[remove_id]<=0;
                moving[remove_id]<=0;
                behaviour[remove_id]<=IDLE; cooldown[remove_id]<=0;
                enemy_defeated<=1;
            end else if(shot_hit) hp[damage_id]<=hp[damage_id]-8'd1;
            if(apply_move) begin
                has_look_reservation[move_id]<=look_valid && !arriving;
                look_reservation[move_id]<=look_tile;
                pos_x[move_id]<=next_x;
                pos_y[move_id]<=next_y;
                moving[move_id]<=!arriving;
                if(!was_moving) begin
                    travel_origin[move_id]<=old_tile;
                    travel_destination[move_id]<=candidate;
                    travel_direction[move_id]<=step_direction;
                end
            end
        end
    end
endmodule
