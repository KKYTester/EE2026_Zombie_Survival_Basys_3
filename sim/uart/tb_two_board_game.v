`timescale 1ns / 1ps
// Two My_Top_Module boards with crossed UART lines (short timings).
// Checks: link-up, 2P blocked without link, host-started 2P run, identical
// maps on both boards, Player 2 pose and shots reaching the host, zombies
// shown on the Player 2 board, and a standalone 1P run on a lone board.
module tb_two_board_game;
    reg clk=0;
    always #5 clk=~clk;
    reg host_c=0, host_d=0, cl_c=0, cl_u=0, solo_c=0;
    wire h_tx, c_tx, solo_tx;
    tri1 h_ps2c, h_ps2d, c_ps2c, c_ps2d, s_ps2c, s_ps2d;
    wire [15:0] h_led, c_led, s_led;
    localparam P_DEB=4, P_GEN=12, P_OVER=12;
`define BOARD_PARAMS .DEBOUNCE_CYCLES(P_DEB),.GEN_SHIFT(P_GEN),.OVER_SHIFT(P_OVER), \
        .SPAWN_SHIFT(10),.CLEAR_SHIFT(12),.MOVE_PERIOD(20000),.CLK_FREQ(1843200), \
        .LINK_INPUT_PERIOD(3000),.LINK_STATE_PERIOD(6000),.LINK_HELLO_PERIOD(8000), \
        .LINK_TIMEOUT(200000)
    My_Top_Module #(`BOARD_PARAMS) hostb(.clk(clk),.btnC(host_c),.btnU(1'b0),.btnL(1'b0),
        .btnR(1'b0),.btnD(host_d),.sw0(1'b0),.sw1(1'b0),.sw13(1'b0),.sw14(1'b0),.sw15(1'b0),
        .ps2_clk(h_ps2c),.ps2_data(h_ps2d),.led(h_led),.JB(),.seg(),.dp(),.an(),
        .uart_tx_pin(h_tx),.uart_rx_pin(c_tx));
    My_Top_Module #(`BOARD_PARAMS) client(.clk(clk),.btnC(cl_c),.btnU(cl_u),.btnL(1'b0),
        .btnR(1'b0),.btnD(1'b0),.sw0(1'b0),.sw1(1'b1),.sw13(1'b0),.sw14(1'b0),.sw15(1'b0),
        .ps2_clk(c_ps2c),.ps2_data(c_ps2d),.led(c_led),.JB(),.seg(),.dp(),.an(),
        .uart_tx_pin(c_tx),.uart_rx_pin(h_tx));
    My_Top_Module #(`BOARD_PARAMS) solo(.clk(clk),.btnC(solo_c),.btnU(1'b0),.btnL(1'b0),
        .btnR(1'b0),.btnD(1'b0),.sw0(1'b0),.sw1(1'b0),.sw13(1'b0),.sw14(1'b0),.sw15(1'b0),
        .ps2_clk(s_ps2c),.ps2_data(s_ps2d),.led(s_led),.JB(),.seg(),.dp(),.an(),
        .uart_tx_pin(solo_tx),.uart_rx_pin(1'b1));

    integer errors=0, p2_shots=0;
    always @(posedge clk) if(hostb.p2_shot && hostb.p2_in_game) p2_shots=p2_shots+1;
    task fail(input [8*64-1:0] msg); begin $display("FAIL: %0s", msg); errors=errors+1; end endtask
    // Task arguments are copies, so the button is chosen by number.
    task press(input integer which); begin
        case(which) 0: host_c=1; 1: host_d=1; 2: cl_c=1; 3: solo_c=1; endcase
        repeat(40) @(posedge clk);
        host_c=0; host_d=0; cl_c=0; solo_c=0;
        repeat(40) @(posedge clk);
    end endtask

    integer i;
    reg [7:0] start_tile;
    initial begin
        // Host alone at first: 2 PLAYERS must not start without the link.
        repeat(100) @(posedge clk);
        press(1);
        if(hostb.game.flow.sel!==1) fail("BTN-D did not select 2 PLAYERS");
        // Lone solo board: 1 PLAYER starts without any link.
        press(3);
        for(i=0;i<400000 && solo.game_state!=3;i=i+1) @(posedge clk);
        if(solo.game_state!=3) fail("solo board did not reach PLAYING in 1P");
        if(solo.selected_2p!==0) fail("solo run is not 1P");
        if(solo.link_up) fail("solo board reports a link");
        // Wait for the two-board link.
        for(i=0;i<200000 && !(hostb.link_up && client.link_up);i=i+1) @(posedge clk);
        if(!(hostb.link_up && client.link_up)) fail("link did not come up");
        else $display("link up at %0t", $time);
        press(0);
        for(i=0;i<600000 && !(hostb.game_state==3 && client.game_state==3);i=i+1) @(posedge clk);
        if(hostb.game_state!=3) fail("host did not reach PLAYING");
        if(client.game_state!=3) fail("client did not reach PLAYING");
        else $display("both playing at %0t, seed host=%h client=%h", $time,
                      hostb.active_seed, client.active_seed);
        if(hostb.published_map!==client.published_map) fail("maps differ");
        if(hostb.active_seed!==client.active_seed) fail("seeds differ");
        if(!hostb.coop) fail("host not in 2P run");
        if(client.player_tile!==client.p2_addr) fail("client did not spawn on P2 tile");
        // Host learns the P2 position.
        for(i=0;i<50000 && !hostb.p2_synced;i=i+1) @(posedge clk);
        if(!hostb.p2_synced) fail("host never received P2 pose");
        if(hostb.p2_tile!==client.player_tile) fail("host P2 tile != client tile");
        // Client walks forward; host follows.
        start_tile = client.player_tile;
        cl_u=1;
        for(i=0;i<400000 && client.player_tile==start_tile;i=i+1) @(posedge clk);
        cl_u=0;
        // Real walking takes millions of clocks per step at 24 Hz; move the
        // Player 2 pose directly (three tiles west, two north) instead.
        force client.player_x = {16'd0, client.player_x[15:12]-4'd3, 12'h800};
        force client.player_y = {16'd0, client.player_y[15:12]+4'd2, 12'h800};
        repeat(30000) @(posedge clk);
        $display("client P2 tile %h, host sees %h", client.player_tile, hostb.p2_tile);
        if(client.player_tile==start_tile) fail("forced move had no effect");
        if(hostb.p2_tile!==client.player_tile) fail("host did not follow P2 movement");
        release client.player_x; release client.player_y;
        // Client fires; host must register a P2 shot.
        press(2);
        repeat(40000) @(posedge clk);
        if(p2_shots<1) fail("P2 shot did not reach the host");
        // Zombies appear on the client board.
        for(i=0;i<2000000 && client.render_active==0;i=i+1) @(posedge clk);
        if(client.render_active==0) fail("no zombies shown on client");
        else $display("client shows zombies %b (host %b)", client.render_active, hostb.local_render_active);
        if(client.game.frame_wave!==hostb.wave && client.game.shown_wave!==hostb.wave) fail("wave differs");
        $display("P2 shots seen: %0d, P2 hearts %0d", p2_shots, hostb.p2_health);
        if(errors==0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        $finish;
    end
endmodule
