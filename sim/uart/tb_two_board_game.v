`timescale 1ns / 1ps
// Two linked My_Top_Module boards (crossed UART) plus a lone board, short timings.
// Independent 2-player design: each board runs its own game on the same map.
//  1. Lone board: 1 PLAYER runs with no link.
//  2. Both linked boards start 2 PLAYERS at once: exactly one leads, both
//     play the same map with the same token.
//  3. Each board spawns its own zombies; partner status crosses the link.
//  4. Board A dies: A shows GAME OVER while B keeps playing; A returning to
//     the title does not pull it back into B's run.
//  5. B dies and returns; A starts 2 PLAYERS alone and B (on its title) joins.
module tb_two_board_game;
    reg clk=0;
    always #5 clk=~clk;
    reg a_c=0, a_d=0, a_hit=0, b_c=0, b_d=0, b_hit=0, s_c=0;
    reg b_reset=1;   // real boards never start in lockstep
    wire a_tx, b_tx, s_tx;
    tri1 a_ps2c, a_ps2d, b_ps2c, b_ps2d, s_ps2c, s_ps2d;
    localparam P_DEB=4, P_GEN=12, P_OVER=12;
`define BOARD_PARAMS .DEBOUNCE_CYCLES(P_DEB),.GEN_SHIFT(P_GEN),.OVER_SHIFT(P_OVER), \
        .SPAWN_SHIFT(10),.CLEAR_SHIFT(12),.MOVE_PERIOD(20000),.CLK_FREQ(1843200), \
        .LINK_PERIOD(4000),.LINK_TIMEOUT(200000)
    My_Top_Module #(`BOARD_PARAMS) A(.clk(clk),.btnC(a_c),.btnU(1'b0),.btnL(1'b0),
        .btnR(1'b0),.btnD(a_d),.sw0(1'b0),.sw13(a_hit),.sw14(1'b0),.sw15(1'b0),
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

    integer errors=0, i;
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
    // Each SW13 flip is one test hit; three hits end that board's run.
    task kill(input integer board); integer k; begin
        for(k=0;k<3;k=k+1) begin
            if(board==0) a_hit=~a_hit; else b_hit=~b_hit;
            repeat(60) @(posedge clk);
        end
    end endtask
    task wait_state(input integer board, input [2:0] st, input integer limit); integer w; begin
        for(w=0; w<limit && (board==0 ? A.game_state : B.game_state)!=st; w=w+1) @(posedge clk);
    end endtask

    initial begin
        repeat(100) @(posedge clk);
        b_reset=0;
        // 1. Lone board, 1 PLAYER.
        press(4);
        for(i=0;i<400000 && S.game_state!=3;i=i+1) @(posedge clk);
        if(S.game_state!=3) fail("lone board did not start 1P");
        if(S.two_player) fail("lone board run marked 2P");

        for(i=0;i<200000 && !(A.link_up && B.link_up);i=i+1) @(posedge clk);
        if(!(A.link_up && B.link_up)) fail("link did not come up");
        else $display("link up at %0t", $time);

        // 2. Both select 2 PLAYERS and start in the same clock.
        press(6);
        if(!(A.game.flow.sel && B.game.flow.sel)) fail("BTN-D did not select 2P");
        press(5);
        for(i=0;i<800000 && !(A.game_state==3 && B.game_state==3);i=i+1) @(posedge clk);
        if(A.game_state!=3 || B.game_state!=3) fail("simultaneous start: not both playing");
        if(A.leader == B.leader) fail("simultaneous start: leader not unique");
        if(A.game_token!==B.game_token) fail("simultaneous start: tokens differ");
        if(A.published_map!==B.published_map) fail("simultaneous start: maps differ");
        $display("simultaneous start: A leader=%0d B leader=%0d seed A=%h B=%h", A.leader, B.leader,
                 A.active_seed, B.active_seed);

        // 3. Own zombies on each board; partner status crosses the link.
        for(i=0;i<2000000 && !(A.render_active!=0 && B.render_active!=0);i=i+1) @(posedge clk);
        if(A.render_active==0 || B.render_active==0) fail("a board has no zombies of its own");
        if(!(A.same_game && B.same_game)) fail("boards do not see the same game");
        repeat(20000) @(posedge clk);
        if(A.peer_wave!==B.wave || B.peer_wave!==A.wave) fail("partner wave not received");
        if(A.peer_health!==B.health) fail("partner hearts not received");
        $display("zombies A=%b B=%b, A seg=%h B seg=%h", A.render_active, B.render_active,
                 A.seg_value, B.seg_value);

        // 3b. Each board sees the other player.
        if(!(A.partner_visible && B.partner_visible)) fail("partner not visible");
        if(A.partner_x!==B.player_x[15:0] || A.partner_y!==B.player_y[15:0])
            fail("A has wrong partner position");
        // Move B one tile north-east and check A's sprite inputs follow
        // (sprite drawing itself is covered by sim/enemy/tb_ally_sprite.v).
        force B.player_x = {16'd0, A.player_x[15:12]+4'd1, A.player_x[11:0]};
        force B.player_y = {16'd0, A.player_y[15:12]+4'd1, A.player_y[11:0]};
        repeat(60000) @(posedge clk);
        if(A.partner_tile!==B.player_tile) fail("A partner tile does not follow B");
        if(!A.sprite_active[8]) fail("partner sprite slot not active on A");
        if(A.sprite_x[107:96]!==B.player_x[15:4] || A.sprite_y[107:96]!==(12'd0-B.player_y[15:4]))
            fail("partner sprite coordinates wrong on A");
        else $display("partner sprite: B at tile %h fed to A's renderer", B.player_tile);
        release B.player_x; release B.player_y;

        // 4. A dies; B keeps playing.
        kill(0);
        wait_state(0, 3'd4, 20000);
        if(A.game_state!=4) fail("A did not reach GAME OVER");
        if(B.game_state!=3) fail("B stopped when A died");
        repeat(20000) @(posedge clk);
        if(B.peer_in_run) fail("B still shows partner playing");
        if(B.partner_visible) fail("B still shows the dead partner");
        if(!A.peer_in_run) fail("A does not show B still playing");
        repeat(1<<P_OVER) @(posedge clk);
        press(0);
        if(A.game_state!=0) fail("A did not return to title");
        repeat(30000) @(posedge clk);
        if(A.game_state!=0) fail("A rejoined B's ongoing run");

        // 5. B dies and returns; A starts alone and B joins.
        kill(1);
        wait_state(1, 3'd4, 20000);
        repeat((1<<P_OVER)+100) @(posedge clk);
        press(2);
        if(B.game_state!=0) fail("B did not return to title");
        press(0);   // A still has 2 PLAYERS selected
        for(i=0;i<800000 && !(A.game_state==3 && B.game_state==3);i=i+1) @(posedge clk);
        if(A.game_state!=3 || B.game_state!=3) fail("auto-join: not both playing");
        if(!A.leader || B.leader) fail("auto-join: wrong leader");
        if(A.published_map!==B.published_map) fail("auto-join: maps differ");
        $display("auto-join: seed A=%h B=%h token %h/%h", A.active_seed, B.active_seed,
                 A.game_token, B.game_token);

        if(errors==0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        $finish;
    end
endmodule
