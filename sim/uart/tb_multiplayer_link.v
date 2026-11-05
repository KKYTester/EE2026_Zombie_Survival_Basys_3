`timescale 1ns/1ps
module tb_multiplayer_link;
  reg clk=0, rst=1;
  always #5 clk=~clk;
  wire host_tx, client_tx;
  reg [7:0] client_controls=8'h53;
  reg [119:0] host_snapshot=120'h23456789ABCDEF0123456789ABCDEF;
  reg [71:0] host_zombies=72'hA5_0102030405060708;
  wire [7:0] host_remote_controls;
  wire host_remote_valid, client_snapshot_valid, client_zombies_valid;
  wire [119:0] client_snapshot;
  wire [71:0] client_zombies;
  wire host_up, client_up;
  wire host_packet_error, host_frame_error, client_packet_error, client_frame_error;
  multiplayer_link #(.CLK_FREQ(1843200),.INPUT_PERIOD_CYCLES(500),
    .STATE_PERIOD_CYCLES(10000),.HELLO_PERIOD_CYCLES(1000),.TIMEOUT_CYCLES(20000)) host(
    .clk(clk),.rst(rst),.host_mode(1'b1),.uart_rx_pin(client_tx),.uart_tx_pin(host_tx),
    .local_controls(8'h00),.host_snapshot(host_snapshot),.host_zombies(host_zombies),
    .remote_controls(host_remote_controls),.remote_controls_valid(host_remote_valid),
    .client_snapshot(),.client_snapshot_valid(),.client_zombies(),.client_zombies_valid(),
    .link_up(host_up),.packet_error(host_packet_error),.frame_error(host_frame_error));
  multiplayer_link #(.CLK_FREQ(1843200),.INPUT_PERIOD_CYCLES(500),
    .STATE_PERIOD_CYCLES(10000),.HELLO_PERIOD_CYCLES(1000),.TIMEOUT_CYCLES(20000)) client(
    .clk(clk),.rst(rst),.host_mode(1'b0),.uart_rx_pin(host_tx),.uart_tx_pin(client_tx),
    .local_controls(client_controls),.host_snapshot(120'b0),.host_zombies(72'b0),
    .remote_controls(),.remote_controls_valid(),
    .client_snapshot(client_snapshot),.client_snapshot_valid(client_snapshot_valid),
    .client_zombies(client_zombies),.client_zombies_valid(client_zombies_valid),
    .link_up(client_up),.packet_error(client_packet_error),.frame_error(client_frame_error));
  integer saw_input=0, saw_snapshot=0, saw_zombies=0;
  always @(posedge clk) begin
    if(host_remote_valid && host_remote_controls==client_controls) saw_input<=1;
    if(client_snapshot_valid && client_snapshot==host_snapshot) saw_snapshot<=1;
    if(client_zombies_valid && client_zombies==host_zombies) saw_zombies<=1;
  end
  initial begin
    repeat(10) @(negedge clk); rst=0;
    wait(host_up && client_up);
    $display("LINK_UP at %0t",$time);
    wait(saw_input && saw_snapshot && saw_zombies);
    $display("PASS input/state/zombie payloads at %0t",$time);
    $finish;
  end
  initial begin repeat(50000) @(posedge clk); $display("TIMEOUT host=%b client=%b input=%b state=%b zombies=%b herr=%b/%b cerr=%b/%b",host_up,client_up,saw_input,saw_snapshot,saw_zombies,host_packet_error,host_frame_error,client_packet_error,client_frame_error); $finish; end
endmodule
