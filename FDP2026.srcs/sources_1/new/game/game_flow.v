`timescale 1ns / 1ps
// Game flow:
//   TITLE -> GENERATING -> PLAYING -> GAME OVER -> TITLE
//                                 \-> VICTORY  -> TITLE
//  - Title: mouse hover highlights an option, left-click on it confirms.
//    BTN-D toggles the selection (ENABLE_2P = 1) and BTN-C confirms it.
//    2 PLAYERS can only be confirmed while the other board is linked.
//  - Confirming consumes the press: it never reaches the playing state.
//  - Generating: requests one new map (the seed is whatever the free-running
//    counter holds at that moment) and shows the screen for at least
//    2^GEN_SHIFT clocks so the player can read it.
//  - A ready map enters PLAYING directly and pulses play_start for one clock.
//  - Playing ends when health_zero (GAME OVER) or when the last wave is
//    survived (game_won, VICTORY); losing the last heart wins over winning.
//    Both end screens ignore input for 2^OVER_SHIFT clocks (over_ready=0),
//    then a click or btnC returns to the title.
//
// Two boards (2 PLAYERS): both players are in ONE shared run. The board that
// starts is the leader: it picks the map and a new game token and runs the
// waves and zombies for both players. A linked board on its title screen joins
// any new leader game it sees: it waits for the leader's final seed (sent once
// the leader is PLAYING), generates the same map from it and starts. If both
// boards start at once, the lower priority value follows the other.
// The leader ends the run (health_zero: both players down, or game_won); the
// follower's run ends with the leader's (or when the leader is lost).
module game_flow #(parameter ENABLE_2P = 0, parameter GEN_SHIFT = 26,
                   parameter OVER_SHIFT = 27)(
    input wire clk, input wire rst,
    input wire btn_c, input wire btn_d, input wire btn_l, input wire btn_r, // one-clock pulses
    input wire [6:0] mouse_x, input wire [5:0] mouse_y,
    input wire mouse_left, input wire mouse_event,
    input wire map_ready, input wire map_busy,
    input wire health_zero, input wire game_won,
    input wire [15:0] random,          // free-running counter (token/priority source)
    // The other board's status (valid while link_up).
    input wire link_up,
    input wire [2:0] peer_state, input wire peer_2p, input wire peer_leader,
    input wire [7:0] peer_token, input wire [15:0] peer_priority,
    output reg [2:0] state,            // 0 title, 1 generating, 2 reserved, 3 playing, 4 game over, 5 victory
    output reg sel,                    // 0 = 1 PLAYER, 1 = 2 PLAYERS
    output reg regenerate,             // one-clock new-map request
    output reg play_start,             // one-clock pulse when playing begins
    output wire [5:0] progress,
    output wire over_ready,
    // This board's two-board role, sent to the other board.
    output reg two_player,             // the current/last run is a 2-player run
    output reg leader,                 // this board picked the map
    output reg [7:0] token,            // game token: own (leader) or joined (follower)
    output reg [15:0] start_priority,
    output wire use_peer_seed);        // generate from the leader's seed
    localparam S_TITLE=3'd0, S_GEN=3'd1, S_PLAY=3'd3, S_OVER=3'd4, S_WIN=3'd5;
    localparam MAX_SHIFT = (GEN_SHIFT > OVER_SHIFT) ? GEN_SHIFT : OVER_SHIFT;
    // Option rectangles, identical to menu_screens.
    localparam OPT_X0=18, OPT_X1=77, OPT1_Y0=26, OPT1_Y1=34, OPT2_Y0=35, OPT2_Y1=43;
    reg [MAX_SHIFT:0] timer;
    reg [2:0] timer_state;
    reg requested, seen_busy, left_prev;
    wire in_x = mouse_x>=OPT_X0 && mouse_x<=OPT_X1;
    wire over_1p = in_x && mouse_y>=OPT1_Y0 && mouse_y<=OPT1_Y1;
    wire over_2p = in_x && mouse_y>=OPT2_Y0 && mouse_y<=OPT2_Y1 && ENABLE_2P;
    wire click = mouse_left && !left_prev;
    wire click_confirm = click && (over_1p || (over_2p && link_up));
    wire button_confirm = btn_c && (!sel || link_up);
    wire timer_current = state==timer_state;
    wire gen_done = timer_current && timer[GEN_SHIFT];
    wire over_done = timer_current && timer[OVER_SHIFT];
    assign progress = (state!=S_GEN || !timer_current) ? 6'd0 :
                      (gen_done ? 6'd63 : timer[GEN_SHIFT-1 -: 6]);
    assign over_ready = (state==S_OVER || state==S_WIN) && over_done;

    // Observe the registered state instead of decoding transitions from the
    // link and health inputs in the timer's enable/reset path. The first
    // clock of a new screen initializes its timer; stale counts are masked.
    always @(posedge clk) begin
        if(rst) begin timer_state<=S_TITLE; timer<=0; end
        else begin
            timer_state<=state;
            if(!timer_current) timer<=0;
            else if((timer_state==S_GEN && !timer[GEN_SHIFT]) ||
                    ((timer_state==S_OVER || timer_state==S_WIN) && !timer[OVER_SHIFT]))
                timer<=timer+1'b1;
        end
    end

    // A leader game of the other board that is starting or running.
    wire peer_leading = ENABLE_2P && link_up && peer_2p && peer_leader &&
                        (peer_state==S_GEN || peer_state==S_PLAY);
    wire following = two_player && !leader;
    assign use_peer_seed = following;
    // Both boards started at once: the lower priority follows. An exact tie
    // makes both re-roll their priority until the values differ.
    wire yield = peer_leading && (peer_state==S_PLAY || peer_priority>start_priority);
    wire [7:0] new_token = (random[7:0]==8'd0 || random[7:0]==token) ?
                           token+8'd1 : random[7:0];

    always @(posedge clk) begin
        if(rst) begin
            state<=S_TITLE; sel<=0; regenerate<=0; play_start<=0;
            requested<=0; seen_busy<=0; left_prev<=0;
            two_player<=0; leader<=0; token<=0; start_priority<=0;
        end else begin
            regenerate<=0; play_start<=0;
            left_prev<=mouse_left;
            case(state)
                S_TITLE: begin
                    if(mouse_event && over_1p) sel<=0;
                    if(mouse_event && over_2p) sel<=1;
                    if(ENABLE_2P && btn_d) sel<=~sel;
                    if(peer_leading && peer_token!=token) begin
                        // The other board started a new 2-player game: join it.
                        sel<=1; two_player<=1; leader<=0; token<=peer_token;
                        state<=S_GEN; requested<=0; seen_busy<=0;
                    end else if(button_confirm || click_confirm) begin
                        two_player <= click_confirm ? over_2p : sel;
                        leader <= click_confirm ? over_2p : sel;
                        if(click_confirm) sel<=over_2p;
                        if(click_confirm ? over_2p : sel) begin
                            token<=new_token; start_priority<=random;
                        end
                        state<=S_GEN; requested<=0; seen_busy<=0;
                    end
                end
                S_GEN: begin
                    if(following) begin
                        if(!(peer_leading && peer_token==token)) state<=S_TITLE; // leader left
                        else if(peer_state==S_PLAY) begin
                            // The leader's seed is final: build the same map.
                            if(!requested && !map_busy) begin regenerate<=1; requested<=1; end
                            if(requested && map_busy) seen_busy<=1;
                            if(seen_busy && map_ready && !map_busy) begin
                                state<=S_PLAY; play_start<=1;
                            end else if(seen_busy && !map_busy && !map_ready) begin
                                requested<=0; seen_busy<=0;
                            end
                        end
                    end else if(two_player && yield) begin
                        // Started together with the other board: use its map.
                        leader<=0; token<=peer_token; requested<=0; seen_busy<=0;
                    end else begin
                        // Exact priority tie: re-roll (the boards' counters drift apart).
                        if(two_player && peer_leading && peer_state==S_GEN &&
                           peer_priority==start_priority)
                            start_priority <= random ^ {random[7:0],random[15:8]};
                        if(!requested && !map_busy) begin regenerate<=1; requested<=1; end
                        if(requested && map_busy) seen_busy<=1;
                        if(gen_done && seen_busy && map_ready && !map_busy) begin
                            state<=S_PLAY; play_start<=1;
                        end else if(seen_busy && !map_busy && !map_ready) begin
                            // Generation ended in an error: ask again with a new seed.
                            requested<=0; seen_busy<=0;
                        end
                    end
                end
                S_PLAY: begin
                    if(following) begin
                        // Shared run: it ends when the leader's run ends.
                        if(!(link_up && peer_2p && peer_token==token) ||
                           peer_state==S_OVER || peer_state==S_TITLE) begin
                            state<=S_OVER;
                        end else if(peer_state==S_WIN) state<=S_WIN;
                    end else if(health_zero && !play_start) state<=S_OVER;
                    else if(game_won && !play_start) state<=S_WIN;
                end
                S_OVER, S_WIN: begin
                    if(over_done && (btn_c || click)) state<=S_TITLE;
                end
                default: state<=S_TITLE;
            endcase
        end
    end
endmodule
