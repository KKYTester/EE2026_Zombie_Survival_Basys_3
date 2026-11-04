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
    localparam [31:0] MAP_LIMIT = 32'd16 << COORD_FRAC_BITS;
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
    integer select_i, mask_i, reset_i;

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

    // Rebuild the tile mask from live records; bounds checks prevent wrapping.
    always @* begin
        occupied=0;
        for(mask_i=0; mask_i<MAX_ENEMIES; mask_i=mask_i+1)
            if(active[mask_i] && pos_x[mask_i]<MAP_LIMIT && pos_y[mask_i]<MAP_LIMIT)
                occupied[{pos_y[mask_i][COORD_FRAC_BITS +: 4],
                          pos_x[mask_i][COORD_FRAC_BITS +: 4]}]=1'b1;
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
    always @(posedge clk) begin
        spawn_ack<=0; enemy_defeated<=0;
        if(rst || clear) begin
            active<=0; request_seen<=0;
            for(reset_i=0; reset_i<MAX_ENEMIES; reset_i=reset_i+1) begin
                pos_x[reset_i]<=0; pos_y[reset_i]<=0; hp[reset_i]<=0;
                kind[reset_i]<=0; behaviour[reset_i]<=IDLE; cooldown[reset_i]<=0;
            end
        end else begin
            // A held request is accepted once; a low cycle rearms it.
            if(!spawn_req) request_seen<=0;
            if(accept_spawn) begin
                active[free_id]<=1;
                pos_x[free_id]<=({28'd0,spawn_tile[3:0]} << COORD_FRAC_BITS) + HALF_TILE;
                pos_y[free_id]<=({28'd0,spawn_tile[7:4]} << COORD_FRAC_BITS) + HALF_TILE;
                hp[free_id]<=INITIAL_HP; kind[free_id]<=0;
                behaviour[free_id]<=IDLE; cooldown[free_id]<=0;
                spawn_ack<=1; request_seen<=1;
            end
            // Free/live selectors use pre-edge state, so simultaneous updates
            // target different slots. A full pool retries on the next cycle.
            if(playing && debug_defeat && live_found) begin
                active[live_id]<=0; hp[live_id]<=0;
                behaviour[live_id]<=IDLE; cooldown[live_id]<=0;
                enemy_defeated<=1;
            end
        end
    end
endmodule
