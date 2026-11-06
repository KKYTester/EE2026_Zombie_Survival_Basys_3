`timescale 1ns/1ps
module tb_two_player_game;
  reg clk=0, rst=1, hL=0,cL=0,hC=0,cC=0,hD=0,cD=0;
  reg [7:0] hsw=0,csw=0;
  always #5 clk=~clk;
  wire htx,ctx; wire [15:0] hled,cled; wire [7:0] hjb,cjb;
  wire [6:0] hs,cs; wire hdp,cdp; wire [3:0] ha,ca;
  tri1 hps2c,hps2d,cps2c,cps2d;
  enemy_test_top #(.DEBOUNCE_CYCLES(5),.GEN_SHIFT(8),.OVER_SHIFT(8),.MOVE_PERIOD(1000),.PLAYER_MOVE_PERIOD(1000),.ATTACK_COOLDOWN_CYCLES(10000),.WIN_WAVE(255)) host(
    .clk(clk),.sw0(hsw[0]),.sw1(hsw[1]),.sw2(hsw[2]),.sw3(1'b1),.sw4(hsw[4]),.sw5(hsw[5]),.sw6(hsw[6]),.sw7(hsw[7]),
    .btnC(hC),.btnU(rst),.btnL(hL),.btnR(1'b0),.btnD(hD),.PS2Clk(hps2c),.PS2Data(hps2d),.led(hled),.JB(hjb),.seg(hs),.dp(hdp),.an(ha),.uart_tx_pin(htx),.uart_rx_pin(ctx));
  enemy_test_top #(.DEBOUNCE_CYCLES(5),.GEN_SHIFT(8),.OVER_SHIFT(8),.MOVE_PERIOD(1000),.PLAYER_MOVE_PERIOD(1000),.ATTACK_COOLDOWN_CYCLES(10000),.WIN_WAVE(255)) client(
    .clk(clk),.sw0(csw[0]),.sw1(csw[1]),.sw2(csw[2]),.sw3(1'b0),.sw4(csw[4]),.sw5(csw[5]),.sw6(csw[6]),.sw7(csw[7]),
    .btnC(cC),.btnU(rst),.btnL(cL),.btnR(1'b0),.btnD(cD),.PS2Clk(cps2c),.PS2Data(cps2d),.led(cled),.JB(cjb),.seg(cs),.dp(cdp),.an(ca),.uart_tx_pin(ctx),.uart_rx_pin(htx));
  defparam host.multiplayer_link_i.CLK_FREQ=1843200;
  defparam host.multiplayer_link_i.INPUT_PERIOD_CYCLES=500;
  defparam host.multiplayer_link_i.STATE_PERIOD_CYCLES=10000;
  defparam host.multiplayer_link_i.HELLO_PERIOD_CYCLES=1000;
  defparam host.multiplayer_link_i.TIMEOUT_CYCLES=50000;
  defparam client.multiplayer_link_i.CLK_FREQ=1843200;
  defparam client.multiplayer_link_i.INPUT_PERIOD_CYCLES=500;
  defparam client.multiplayer_link_i.STATE_PERIOD_CYCLES=10000;
  defparam client.multiplayer_link_i.HELLO_PERIOD_CYCLES=1000;
  defparam client.multiplayer_link_i.TIMEOUT_CYCLES=50000;
  reg [7:0] start_p2=0; reg input_seen=0,moved=0,selected=0; reg tracking=0; reg [3:0] dirs[0:3]; integer k;
  always @(posedge clk) begin
    if(host.remote_controls_valid && host.remote_controls[3:0]!=0) input_seen<=1;
    if(tracking && host.p2_current!=start_p2) moved<=1;
  end
  initial begin
    repeat(20) @(negedge clk); rst=0;
    wait(host.link_up && client.link_up); $display("PASS: handshake both boards");
    repeat(10) @(negedge clk); hD=1;cD=1; repeat(20) @(negedge clk); hD=0;cD=0;
    repeat(10) @(negedge clk); hC=1;cC=1; repeat(20) @(negedge clk); hC=0;cC=0;
    wait(host.game_state==3 && client.game_state==3); repeat(3) @(negedge clk);
    start_p2=host.p2_current; tracking=1; $display("PASS: both game cores playing; P2 starts %02h",start_p2);
    dirs[0]=1; dirs[1]=2; dirs[2]=4; dirs[3]=8;
    for(k=0;k<4 && !selected;k=k+1) begin
      csw[7:4]=dirs[k]; wait(host.remote_controls[3:0]==dirs[k]); repeat(3) @(negedge clk);
      if(host.p2_move_candidate!=host.p2_current) selected=1;
    end
    if(!selected) begin $display("FAIL: no legal P2 move from %02h",start_p2); $finish; end
    wait(input_seen); $display("PASS: client control reached host");
    wait(moved); $display("PASS: host moved P2 %02h -> %02h",start_p2,host.p2_current);
    wait(client.p2_current==host.p2_current); $display("PASS: client received updated P2 position"); $finish;
  end
  initial begin repeat(1000000) @(posedge clk); $display("TIMEOUT link=%b/%b state=%d/%d p2=%02h start=%02h input=%b moved=%b",host.link_up,client.link_up,host.game_state,client.game_state,host.p2_current,start_p2,input_seen,moved); $finish; end
endmodule
