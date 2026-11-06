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
//  5. B's shot reaches A's combat; zombie damage to B is tracked by A and
//     shown on B.
//  6. A goes down: the run continues for B. B goes down: both boards end.
module tb_two_board_game;
    reg clk=0;
    always #5 clk=~clk;
    reg a_c=0, a_d=0, a_hit=0, b_c=0, b_d=0, b_hit=0, s_c=0;
    reg a_reset=0, b_reset=1;   // real boards never start in lockstep
    wire a_tx, b_tx, s_tx;
    tri1 a_ps2c, a_ps2d, b_ps2c, b_ps2d, s_ps2c, s_ps2d;
    // GENERATING lasts 2^P_GEN clocks: keep it many link periods long, as on the
    // boards (0.67 s vs 20 ms), so simultaneous starts see each other.
    localparam P_DEB=4, P_GEN=17, P_OVER=12;
`define BOARD_PARAMS .DEBOUNCE_CYCLES(P_DEB),.GEN_SHIFT(P_GEN),.OVER_SHIFT(P_OVER), \
        .SPAWN_SHIFT(10),.CLEAR_SHIFT(12),.MOVE_PERIOD(20000),.CLK_FREQ(1843200), \
        .LINK_PERIOD(8000),.LINK_TIMEOUT(400000)
    My_Top_Module #(`BOARD_PARAMS) A(.clk(clk),.btnC(a_c),.btnU(1'b0),.btnL(1'b0),
        .btnR(1'b0),.btnD(a_d),.sw0(1'b0),.sw13(a_hit),.sw14(1'b0),.sw15(a_reset),
        .ps2_clk(a_ps2c),.ps2_data(a_ps2d),.led(),.JB(),.seg(),.dp(),.an(),
        .uart_tx_pin(a_tx),.uart_rx_pin(b_tx));
    My_Top_Module #(`BOARD_PARAMS) B(.clk(clk),.btnC(b_c),.btnU(1'b0),.btnL(1'b0),
        .btnR(1'b0),.btnD(b_d),.sw0(1'b0),.sw13(b_hit),.sw14(1'b0),.sw15(b_reset),
        .ps2_clk(b_ps2c),.ps2_data(b_ps2d),.led(),.JB(),.seg(),.dp(),.an(),
        .uart_tx_pin(b_tx),.uart_rx_pin(a_tx));
    My_Top_Module #(`BOARD_PARAMS) S(.clk(clk),.btnC(s_c),.btnU(1'b0),.btnL(1'b0),
        .btnR(1'b0),.btnD(1'b0),.sw0(1'b0),.sw13(1'b0),.sw14(1'b0),.sw15(1'b0),
        .ps2_clk(s_ps2c),.ps2_data(s_ps2d),.led(),.JB(),.seg(),.dp(),.an(),
        .uart_tx_pin(s_tx),.uart_rx_pin(1'b1));

    integer errors=0, i, b_shots=0;
    always @(posedge clk) if(A.partner_shot && A.partner_in_game) b_shots=b_shots+1;
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

        // 5. Follower's shot and hearts.
        press(2);
        repeat(60000) @(posedge clk);
        if(b_shots<1) fail("follower's shot did not reach the leader");
        // Zombies may also reach B during the test, so check the hearts went
        // down and that both boards agree on the count.
        hit_b(1);
        repeat(30000) @(posedge clk);
        if(A.partner_hearts>=3) fail("leader did not take a heart from Player 2");
        if(B.health!==A.partner_hearts) fail("follower's hearts differ from the leader's count");
        $display("P2 shots seen by leader: %0d, B hearts %0d", b_shots, B.health);

        // 6. A goes down: the run continues. Then B goes down: both end.
        hit_a(3);
        repeat(30000) @(posedge clk);
        if(A.health!==0) fail("A not down");
        if(A.game_state!=3 || B.game_state!=3) fail("run ended while B was still alive");
        hit_b(3);
        wait_both(3'd4, 100000);
        if(A.game_state!=4 || B.game_state!=4) fail("run did not end on both boards");
        else $display("both down: both boards show GAME OVER");

        if(errors==0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        $finish;
    end
endmodule
