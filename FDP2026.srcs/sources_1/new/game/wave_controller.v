`timescale 1ns / 1ps
// One reusable FSM runs every wave. The wave counter supplies difficulty;
// there is no separate copy of the controller for wave 1, wave 2, etc.
//
// IDLE -> SPAWN_DELAY -> FIND_TILE -> WAIT_ACK --more to spawn--> SPAWN_DELAY
//               ^                      |  \--no ACK in 2^ACK_TIMEOUT_SHIFT--/
//               |                      |     (drop request, search again)
//                              last spawn accepted
//                                      v
//                                    FIGHT -> INTERMISSION -> next wave / WON
//
// Enemies may be defeated during spawning as well as during FIGHT.
// A spawn is counted only when spawn_req is acknowledged. A wave ends only
// after its entire budget has been spawned and defeated. INTERMISSION retains
// the between-wave pause; the removed countdown/wave banners are not restored.
module wave_controller #(
    parameter MAX_ALIVE=8, parameter MAX_WAVE_SIZE=21,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter MIN_DIST=8, parameter WIN_WAVE=10, parameter TWO_PLAYERS=0,
    parameter ACK_TIMEOUT_SHIFT=12          // give up on a spawn after 2^12 clocks (~41 us)
)(
    input wire clk, input wire rst,
    input wire play_start, input wire playing,
    input wire [255:0] map_bits, input wire [255:0] occupied,
    input wire [7:0] player_tile,
    input wire [7:0] player2_tile,
    input wire player_active, player2_active,
    input wire spawn_ack, input wire enemy_defeated,
    output reg [6:0] wave,
    output reg spawn_req, output reg [7:0] spawn_tile,
    output wire spawn_busy,
    output reg [5:0] alive,
    output wire [6:0] remaining,
    output reg wave_clear,
    output reg game_won
);
    localparam [2:0] W_IDLE         = 3'd0;
    localparam [2:0] W_SPAWN_DELAY  = 3'd1;
    localparam [2:0] W_FIND_TILE    = 3'd2;
    localparam [2:0] W_WAIT_ACK     = 3'd3;
    localparam [2:0] W_INTERMISSION = 3'd4;
    localparam [2:0] W_WON          = 3'd5;
    localparam [2:0] W_FIGHT        = 3'd6;
    localparam MAX_SC = (SPAWN_SHIFT > CLEAR_SHIFT) ? SPAWN_SHIFT : CLEAR_SHIFT;
    localparam MAX_SHIFT = (MAX_SC > ACK_TIMEOUT_SHIFT) ? MAX_SC : ACK_TIMEOUT_SHIFT;
    localparam [6:0] WAVE_CAP = MAX_WAVE_SIZE;
    localparam [5:0] ALIVE_CAP = MAX_ALIVE;

    reg [2:0] state;
    reg [MAX_SHIFT:0] timer;
    reg [6:0] total, spawned, killed;
    reg finder_start,prefer_player2;
    wire finder_busy, finder_done, finder_found;
    wire [7:0] finder_tile;
    wire [15:0] random_value;

    lfsr16 rng(.clk(clk),.rst(rst),.load(1'b0),.advance(1'b1),
        .seed(16'h0001),.value(random_value));
    spawn_finder #(.MIN_DIST(MIN_DIST),.TWO_PLAYERS(TWO_PLAYERS)) finder(
        .clk(clk),.rst(rst || play_start || !playing),.start(finder_start),
        .map_bits(map_bits),.occupied(occupied),.player_tile(player_tile),
        .player2_tile(player2_tile),.player_active(player_active),.player2_active(player2_active),
        .prefer_player2(prefer_player2),
        .random_start(random_value[7:0]),.busy(finder_busy),.done(finder_done),
        .found(finder_found),.tile(finder_tile));

    // Difficulty: wave sizes 3,5,7,... capped at MAX_WAVE_SIZE; at most
    // wave+2 living enemies, capped at MAX_ALIVE. SPAWN_SHIFT must be >=2.
    assign remaining = total - killed;
    wire [7:0] next_size = {1'b0,total} + 8'd2;
    wire [7:0] wave_limit = {1'b0,wave} + 8'd2;
    wire [5:0] alive_limit = (wave_limit > {2'b00,ALIVE_CAP}) ? ALIVE_CAP : wave_limit[5:0];
    wire spawn_gap_done = (wave<=7'd2) ? timer[SPAWN_SHIFT] :
                          (wave<=7'd4) ? timer[SPAWN_SHIFT-1] : timer[SPAWN_SHIFT-2];
    wire final_wave = WIN_WAVE!=0 && wave==WIN_WAVE;
    wire wave_finished = killed==total;

    // Give population accounting one owner. An accepted spawn and an enemy
    // defeat on the same clock leave alive unchanged but count both events.
    // Keep the selected tile free until the enemy manager accepts it.
    assign spawn_busy = state==W_FIND_TILE || state==W_WAIT_ACK;
    // Count every acknowledgement, in any state: if the enemy side accepts on the
    // very clock this controller gives up (see W_WAIT_ACK), its ACK arrives one
    // clock later in W_SPAWN_DELAY and must still be counted. No new request is
    // made before a full spawn gap has passed, so a late ACK can only belong to
    // the request that was just dropped.
    wire spawn_accepted = spawn_ack;
    wire defeat_accepted = enemy_defeated && alive!=0;

    always @(posedge clk) begin
        if(rst) begin
            state<=W_IDLE;
            timer<=0;
            wave<=1;
            total<=3;
            spawned<=0;
            killed<=0;
            alive<=0;
            spawn_req<=0;
            spawn_tile<=0;
            wave_clear<=0;
            finder_start<=0;
            prefer_player2<=0;
            game_won<=0;
        end else begin
            finder_start<=0;
            if(play_start) begin
                prefer_player2<=0;
                state<=W_SPAWN_DELAY;
                timer<=0;
                wave<=1;
                total<=3;
                spawned<=0;
                killed<=0;
                alive<=0;
                spawn_req<=0;
                wave_clear<=0;
                game_won<=0;
            end else if(!playing) begin
                state<=W_IDLE;
                spawn_req<=0;
                wave_clear<=0;
                game_won<=0;
            end else begin
                if(spawn_accepted) begin
                    spawned<=spawned+1'b1;
                    prefer_player2<=~prefer_player2;
                end
                if(defeat_accepted) killed<=killed+1'b1;
                case({spawn_accepted,defeat_accepted})
                    2'b10: alive<=alive+1'b1;
                    2'b01: alive<=alive-1'b1;
                    default: ; // neither event, or both together
                endcase

                case(state)
                    W_SPAWN_DELAY: begin
                        // Wait for the gap and a free enemy slot. Kills still
                        // count while we are waiting to create the next enemy.
                        if(!spawn_gap_done) timer<=timer+1'b1;
                        if(wave_finished) begin
                            state<=W_INTERMISSION;
                            timer<=0;
                            wave_clear<=1;
                        end else if(spawn_gap_done && spawned<total && alive<alive_limit) begin
                            finder_start<=1;
                            state<=W_FIND_TILE;
                        end
                    end

                    W_FIND_TILE: begin
                        if(finder_done) begin
                            timer<=0;
                            if(finder_found) begin
                                spawn_tile<=finder_tile;
                                spawn_req<=1;
                                state<=W_WAIT_ACK;
                            end else begin
                                // No suitable floor tile: wait, then retry.
                                state<=W_SPAWN_DELAY;
                            end
                        end
                    end

                    W_WAIT_ACK: begin
                        // Hold spawn_req and spawn_tile until the enemy side
                        // accepts this enemy. A delayed ACK cannot duplicate it.
                        // If it never answers (for example the player walked
                        // onto the chosen tile), give up after 2^ACK_TIMEOUT_SHIFT
                        // clocks, wait one spawn gap and search for a new tile.
                        if(spawn_ack) begin
                            spawn_req<=0;
                            timer<=0;               // spawn gap starts from the ACK
                            state <= (spawned+7'd1==total) ? W_FIGHT : W_SPAWN_DELAY;
                        end else if(timer[ACK_TIMEOUT_SHIFT]) begin
                            spawn_req<=0;
                            timer<=0;
                            state<=W_SPAWN_DELAY;
                        end else timer<=timer+1'b1;
                    end

                    W_FIGHT: begin
                        // The full budget has been accepted. No more spawn
                        // searches or requests occur; wait for the final kills.
                        if(wave_finished) begin
                            state<=W_INTERMISSION;
                            timer<=0;
                            wave_clear<=1;
                        end
                    end

                    W_INTERMISSION: begin
                        if(timer[CLEAR_SHIFT]) begin
                            wave_clear<=0;
                            if(final_wave) begin
                                game_won<=1;
                                state<=W_WON;
                            end else begin
                                timer<=0;
                                spawned<=0;
                                killed<=0;
                                if(wave!=7'd99) wave<=wave+1'b1;
                                total <= (next_size>{1'b0,WAVE_CAP}) ? WAVE_CAP : next_size[6:0];
                                state<=W_SPAWN_DELAY;
                            end
                        end else begin
                            timer<=timer+1'b1;
                        end
                    end

                    W_WON: begin
                        // game_won stays high until play ends or restarts.
                    end

                    default: state<=W_SPAWN_DELAY;
                endcase
            end
        end
    end
endmodule
