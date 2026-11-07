`timescale 1ns / 1ps
// Two linked My_Top_Module boards (crossed UART) plus a lone board, short timings.
// Shared 2-player design: the starting board (leader) runs the zombies for
// both players; the other board (follower) shows them and plays in the same run.
//  1. Lone board: 1 PLAYER runs with no link.
//  2. Both linked boards start 2 PLAYERS at once: exactly one leads and both
//     play the same map. Both boards are then reset.
//  3. A starts 2 PLAYERS alone; B (on its title) joins: same map, A leads.
//  4. Shared zombies: B shows A's zombies and runs none itself; partner
//     position and visibility cross the link.
//  5. Two B shots survive dropped status and ACK frames, without duplication
//     or substitution of the newest aiming angle. Leader owns B's damage.
//  6. B goes down first: the run continues for A. The downed B cannot
//     restart: BTN-C does nothing, and resetting B makes it rejoin the same
//     run still with no hearts. Then A goes down: both boards end.
module tb_two_board_game;
    reg clk=0;
    always #5 clk=~clk;
    reg a_c=0, a_d=0, a_hit=0, b_c=0, b_d=0, b_hit=0, s_c=0;
    reg a_reset=0, b_reset=1;   // real boards never start in lockstep
    reg block_a_to_b=0,block_b_to_a=0;
    wire a_tx, b_tx, s_tx;
    tri1 a_ps2c, a_ps2d, b_ps2c, b_ps2d, s_ps2c, s_ps2d;
    // GENERATING lasts 2^P_GEN clocks: keep it many link periods long, as on the
    // boards (0.67 s vs 20 ms), so simultaneous starts see each other.
    localparam P_DEB=4, P_GEN=17, P_OVER=12;
`define BOARD_PARAMS .DEBOUNCE_CYCLES(P_DEB),.GEN_SHIFT(P_GEN),.OVER_SHIFT(P_OVER), \
        .SPAWN_SHIFT(10),.CLEAR_SHIFT(12),.MOVE_PERIOD(20000),.CLK_FREQ(1843200), \
        .LINK_PERIOD(16000),.LINK_TIMEOUT(400000),.FLASH_SHIFT(5),.RECOIL_SHIFT(7),.RELOAD_SHIFT(6)
    My_Top_Module #(`BOARD_PARAMS) A(.clk(clk),.btnC(a_c),.btnU(1'b0),.btnL(1'b0),
        .btnR(1'b0),.btnD(a_d),.sw0(1'b0),.sw13(a_hit),.sw14(1'b0),.sw15(a_reset),
        .ps2_clk(a_ps2c),.ps2_data(a_ps2d),.led(),.JB(),.seg(),.dp(),.an(),
        .uart_tx_pin(a_tx),.uart_rx_pin(block_b_to_a ? 1'b1 : b_tx));
    My_Top_Module #(`BOARD_PARAMS) B(.clk(clk),.btnC(b_c),.btnU(1'b0),.btnL(1'b0),
        .btnR(1'b0),.btnD(b_d),.sw0(1'b0),.sw13(b_hit),.sw14(1'b0),.sw15(b_reset),
        .ps2_clk(b_ps2c),.ps2_data(b_ps2d),.led(),.JB(),.seg(),.dp(),.an(),
        .uart_tx_pin(b_tx),.uart_rx_pin(block_a_to_b ? 1'b1 : a_tx));
    My_Top_Module #(`BOARD_PARAMS) S(.clk(clk),.btnC(s_c),.btnU(1'b0),.btnL(1'b0),
        .btnR(1'b0),.btnD(1'b0),.sw0(1'b0),.sw13(1'b0),.sw14(1'b0),.sw15(1'b0),
        .ps2_clk(s_ps2c),.ps2_data(s_ps2d),.led(),.JB(),.seg(),.dp(),.an(),
        .uart_tx_pin(s_tx),.uart_rx_pin(1'b1));

    integer errors=0, i, n, b_shots=0, b_noises=0;
    reg watch_p2_hit=0, a_marked=0;
    always @(posedge clk) if(watch_p2_hit && A.hit_marker) a_marked=1;
    reg [9:0] first_angle,second_angle;
    reg [7:0] first_noise_tile, second_noise_tile;
    reg captured_noise=0;
    always @(posedge clk) if(A.partner_shot && A.partner_in_game) begin
        if(b_shots==0) first_angle=A.partner_shot_angle;
        if(b_shots==1) second_angle=A.partner_shot_angle;
        b_shots=b_shots+1;
    end
    always @(posedge clk) captured_noise<=A.enemies.g_hearing.capture2;
    always @(negedge clk) if(captured_noise) begin
        if(A.enemies.g_hearing.pending_tile2!==(b_noises==0 ? first_noise_tile : second_noise_tile))
            fail("hearing used live P2 position instead of firing tile");
        b_noises=b_noises+1;
    end
    task fail(input [8*64-1:0] msg); begin $display("FAIL: %0s", msg); errors=errors+1; end endtask
    // Task arguments are copies, so buttons are chosen by number.
    // 0 A-C, 1 A-D, 2 B-C, 3 B-D, 4 S-C, 5 A-C+B-C together, 6 A-D+B-D together.
    task press(input integer which); begin
        case(which)
            0: a_c=1; 1: a_d=1; 2: b_c=1; 3: b_d=1; 4: s_c=1;
            5: begin a_c=1; b_c=1; end 6: begin a_d=1; b_d=1; end
        endcase
        repeat(40) @(posedge clk);
        a_c=0; a_d=0; b_c=0; b_d=0; s_c=0;
        repeat(40) @(posedge clk);
    end endtask
    // A's own hearts: each SW13 flip is one test hit.
    task hit_a(input integer n); integer k; begin
        for(k=0;k<n;k=k+1) begin a_hit=~a_hit; repeat(60) @(posedge clk); end
    end endtask
    // B's hearts live on the leader A: pulse A's zombie-hit-on-P2 signal.
    task hit_b(input integer n); integer k; begin
        for(k=0;k<n;k=k+1) begin
            force A.zombie_hit_p2=1; @(posedge clk); #1 release A.zombie_hit_p2;
            repeat(60) @(posedge clk);
        end
    end endtask
    task wait_both(input [2:0] st, input integer limit); integer w; begin
        for(w=0; w<limit && !(A.game_state==st && B.game_state==st); w=w+1) @(posedge clk);
    end endtask

    initial begin
        repeat(100) @(posedge clk);
        b_reset=0;
        // 1. Lone board, 1 PLAYER.
        press(4);
        for(i=0;i<400000 && S.game_state!=3;i=i+1) @(posedge clk);
        if(S.game_state!=3) fail("lone board did not start 1P");
        if(S.two_player) fail("lone board run marked 2P");

        for(i=0;i<300000 && !(A.link_up && B.link_up);i=i+1) @(posedge clk);
        if(!(A.link_up && B.link_up)) fail("link did not come up");
        else $display("link up at %0t", $time);

        // 2. Both select 2 PLAYERS and start in the same clock.
        press(6);
        if(!(A.game.flow.sel && B.game.flow.sel)) fail("BTN-D did not select 2P");
        press(5);
        wait_both(3'd3, 800000);
        if(A.game_state!=3 || B.game_state!=3) fail("simultaneous start: not both playing");
        if(A.leader == B.leader) fail("simultaneous start: leader not unique");
        if(A.published_map!==B.published_map) fail("simultaneous start: maps differ");
        $display("simultaneous start: A leader=%0d B leader=%0d seed %h/%h", A.leader, B.leader,
                 A.active_seed, B.active_seed);
        // Reset both boards back to the title.
        a_reset=1; b_reset=1; repeat(50) @(posedge clk); a_reset=0;
        repeat(1000) @(posedge clk); b_reset=0;
        for(i=0;i<300000 && !(A.link_up && B.link_up);i=i+1) @(posedge clk);

        // 3. A starts 2 PLAYERS alone; B joins from its title.
        press(1); press(0);
        wait_both(3'd3, 800000);
        if(A.game_state!=3 || B.game_state!=3) fail("join: not both playing");
        if(!A.leader || B.leader) fail("join: A should lead, B follow");
        if(A.published_map!==B.published_map) fail("join: maps differ");
        if(B.player_tile!==B.p2_addr) fail("follower did not spawn on the P2 tile");
        $display("shared run: seed %h, A spawn %h, B spawn %h", A.active_seed, A.player_tile, B.player_tile);

        // 4. Shared zombies.
        for(i=0;i<2000000 && A.local_render_active==0;i=i+1) @(posedge clk);
        repeat(40000) @(posedge clk);
        if(A.local_render_active==0) fail("leader spawned no zombies");
        if(B.local_render_active!=0) fail("follower runs zombies of its own");
        if(B.render_active!==A.local_render_active) fail("follower does not show the leader's zombies");
        if(!A.partner_in_game) fail("leader does not treat the follower as Player 2");
        if(!(A.partner_visible && B.partner_visible)) fail("partner not visible");
        if(A.partner_tile!==B.player_tile) fail("leader has wrong Player 2 tile");
        $display("zombies: leader %b, follower shows %b", A.local_render_active, B.render_active);

        // 4b. Effects: the leader's own hit turns only its crosshair red; a hit
        // by the follower's shot turns the follower's crosshair red over the
        // link; the leader's WAVE CLEAR pause starts the follower's banner;
        // zombie hit points reach the follower for its health bars.
        if(B.render_hp!==A.local_render_hp) fail("follower did not receive the zombie hit points");
        force A.local_render_windup=8'd1;
        for(i=0;i<80000 && B.render_windup[0]!==1'b1;i=i+1) @(posedge clk);
        if(B.render_windup[0]!==1'b1) fail("follower did not receive the attack warning");
        release A.local_render_windup;
        for(i=0;i<80000 && B.render_windup[0]!==1'b0;i=i+1) @(posedge clk);
        if(B.render_windup[0]!==1'b0) fail("follower attack warning did not clear");
        @(negedge clk); force A.shot_hit=1; force A.shot_hit_player=0;
        @(negedge clk); release A.shot_hit; release A.shot_hit_player;
        repeat(4) @(posedge clk);
        if(!A.game.hit_on) fail("leader's hit did not turn its crosshair red");
        if(B.game.hit_on) fail("leader's hit turned the follower's crosshair red");
        for(i=0;i<300000 && A.game.hit_on;i=i+1) @(posedge clk);
        watch_p2_hit=1;
        @(negedge clk); force A.shot_hit=1; force A.shot_hit_player=1;
        @(negedge clk); release A.shot_hit; release A.shot_hit_player;
        for(i=0;i<200000 && !B.game.hit_on;i=i+1) @(posedge clk);
        if(!B.game.hit_on) fail("follower's hit did not turn its crosshair red");
        if(a_marked) fail("follower's hit turned the leader's crosshair red");
        watch_p2_hit=0;
        force A.game.wave_clear=1;
        repeat(4) @(posedge clk);
        if(!A.game.banner_live) fail("leader's WAVE CLEAR banner did not start");
        for(i=0;i<200000 && !B.game.banner_source;i=i+1) @(posedge clk);
        if(!B.game.banner_source) fail("follower did not see WAVE CLEAR");
        repeat(4) @(posedge clk);
        if(!B.game.banner_live) fail("follower's WAVE CLEAR banner did not start");
        release A.game.wave_clear;
        for(i=0;i<200000 && B.game.banner_source;i=i+1) @(posedge clk);
        if(B.game.banner_live) fail("follower banner did not end with the pause");
        $display("effects: hit markers on the right board, WAVE CLEAR on both, hit points shared");
        // 4c. Kill scores: two P1 kills and one P2 kill counted on the leader,
        // and the follower shows the same counts.
        if(A.kills_p1!==0 || A.kills_p2!==0) fail("kill scores not zero at the start of the run");
        for(i=0;i<3;i=i+1) begin
            @(negedge clk); force A.shot_hit=1; force A.shot_kill=1; force A.shot_hit_player=(i==2);
            @(negedge clk); release A.shot_hit; release A.shot_kill; release A.shot_hit_player;
            repeat(4) @(negedge clk);
        end
        if(A.kills_p1!==2 || A.kills_p2!==1) fail("leader did not count the kills per player");
        for(i=0;i<200000 && !(B.game.p1_kills==2 && B.game.p2_kills==1);i=i+1) @(posedge clk);
        if(B.game.p1_kills!==2 || B.game.p2_kills!==1) fail("follower does not show the leader's kill scores");
        $display("kills: P1 %0d, P2 %0d on both boards", A.game.p1_kills, B.game.p2_kills);
        // 4d. Pickups: the leader places one health and one magazine pickup per
        // wave and the follower shows the same ones. P2 standing on the
        // magazine upgrades the follower's gun to 7 full rounds; a hurt P2 on
        // the health pickup gets a heart back on both boards.
        for(i=0;i<400000 && !(A.pickups[16] && A.pickups[17]);i=i+1) @(posedge clk);
        if(!(A.pickups[16] && A.pickups[17])) fail("leader placed no pickups");
        for(i=0;i<200000 && B.pickups!==A.pickups;i=i+1) @(posedge clk);
        if(B.pickups!==A.pickups) fail("follower does not show the leader's pickups");
        if(B.game.ammo_capacity!==6) fail("follower magazine not 6 at the start");
        force A.partner_tile = A.pickups[15:8];
        for(i=0;i<300000 && B.game.ammo_capacity!=7;i=i+1) @(posedge clk);
        release A.partner_tile;
        if(B.game.ammo_capacity!==7 || B.game.ammo!==7) fail("P2 magazine pickup did not upgrade the follower's gun");
        if(A.game.ammo_capacity!==6) fail("P2's magazine upgraded the leader's gun");
        if(A.pickups[17]) fail("magazine pickup not removed after P2 took it");
        hit_b(1); repeat(2000) @(posedge clk);
        i=A.partner_hearts;
        force A.partner_tile = A.pickups[7:0];
        repeat(200) @(posedge clk);
        release A.partner_tile;
        if(A.partner_hearts!==i+1) fail("P2 health pickup did not restore a heart");
        for(n=0;n<200000 && B.health!==A.partner_hearts;n=n+1) @(posedge clk);
        if(B.health!==A.partner_hearts) fail("follower hearts not updated after the health pickup");
        $display("pickups: shared %h, P2 magazine -> %0d rounds, P2 hearts %0d -> %0d", A.pickups, B.game.ammo_capacity, i, A.partner_hearts);

        // 5. Follower fires twice during a short packet blackout. Both shots
        // keep their original poses even after moving. Block the return path
        // so the first accepted event is resent until a valid ACK gets back.
        block_b_to_a=1;
        force B.player_angle=32'd511;
        first_noise_tile=B.player_tile;
        press(2);
        repeat(500) @(posedge clk);
        force B.player_angle=32'd777;
        force B.player_x=32'hd800;
        #1 second_noise_tile=B.player_tile;
        press(2);
        force B.player_angle=32'd900;
        force B.player_x=32'hc800;
        repeat(40000) @(posedge clk);
        if(b_shots!=0 || B.shots.count!=2) fail("shots did not queue during packet loss");
        block_a_to_b=1; block_b_to_a=0;
        repeat(75000) @(posedge clk);
        if(b_shots!=1 || b_noises!=1 || B.shots.count!=2) fail("lost ACK caused duplicate or retired a shot");
        block_a_to_b=0;
        repeat(120000) @(posedge clk);
        if(b_shots!=2 || b_noises!=2 || B.shots.count!=0) fail("retry did not deliver exactly two shots");
        if(first_angle!=511 || second_angle!=777) fail("retry used live pose instead of firing pose");
        if(A.link_gaps==0) fail("missing status packets were not detected");
        release B.player_angle;
        release B.player_x;
        // Zombies may also reach B during the test, so check the hearts went
        // down and that both boards agree on the count.
        hit_b(1);
        repeat(30000) @(posedge clk);
        if(A.partner_hearts>=3) fail("leader did not take a heart from Player 2");
        if(B.health!==A.partner_hearts) fail("follower's hearts differ from the leader's count");
        $display("P2 shots seen by leader: %0d, B hearts %0d", b_shots, B.health);

        // 6. B goes down first; it must not be able to come back.
        hit_b(3);
        repeat(30000) @(posedge clk);
        if(B.health!==0 || A.partner_hearts!==0) fail("B not down");
        if(A.game_state!=3 || B.game_state!=3) fail("run ended while A was still alive");
        if(A.partner_in_game) fail("zombies still target the downed B");
        // A downed player's BTN-C / click cannot restart anything.
        press(2); press(2);
        repeat(30000) @(posedge clk);
        if(B.game_state!=3 || B.health!==0) fail("downed B changed state with BTN-C");
        // Resetting the downed board: it rejoins the same run, still down.
        b_reset=1; repeat(50) @(posedge clk); b_reset=0;
        for(i=0;i<800000 && B.game_state!=3;i=i+1) @(posedge clk);
        repeat(30000) @(posedge clk);
        if(B.game_state!=3) fail("reset B did not rejoin the run");
        if(B.game_token!==A.game_token) fail("reset B joined a different run");
        if(B.health!==0) fail("reset B came back with hearts (respawn exploit)");
        if(B.game.ammo_capacity!==7) fail("rejoining follower lost its magazine upgrade");
        if(b_shots!=2) fail("reset of the follower created an extra shot");
        if(A.game_state!=3 || A.health==0) fail("A's run was disturbed by B's reset");
        $display("downed B after reset: state %0d, hearts %0d, A hearts %0d", B.game_state, B.health, A.health);
        // A goes down too: the run ends on both boards.
        hit_a(3);
        wait_both(3'd4, 200000);
        if(A.game_state!=4 || B.game_state!=4) fail("run did not end on both boards");
        if(A.game.p1_kills<2 || B.game.p1_kills!==A.game.p1_kills || B.game.p2_kills!==A.game.p2_kills)
            fail("kill scores lost at game over");
        else $display("both down: both boards show GAME OVER");

        if(errors==0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        $finish;
    end
endmodule
