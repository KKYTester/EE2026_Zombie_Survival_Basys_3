`timescale 1ns / 1ps
module tb_enemy_diagonal_contact;
    reg clk=0, clear=1, req=0, tick=0;
    reg [255:0] walls=0;
    wire hit,ack;
    wire [11:0] x,y;
    integer hits=0;
    always #5 clk=~clk;
    always @(posedge clk) if(hit) hits=hits+1;
    enemy_manager #(.MAX_ENEMIES(1),.USE_PLAYER_POSITIONS(1),.ATTACK_COOLDOWN_CYCLES(100)) dut(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.spawn_req(req),.spawn_tile(8'h11),.debug_defeat(1'b0),
        .move_tick(tick),.spawn_busy(1'b0),.player_tile(8'h22),.shot_fired(1'b0),
        .player_pos_x(32'd512),.player_pos_y(32'd512),.aim(2'd0),
        .player_active(1'b1),.player2_active(1'b0),.player2_tile(8'd0),
        .shot_fired_p2(1'b0),.aim_p2(2'd0),.render_x(x),.render_y(y),
        .read_id(1'b0),.spawn_ack(ack),.player_hit(hit));
    task step; begin @(negedge clk); end endtask
    task spawn;
        begin req=1; step; if(!ack) $fatal(1,"contact spawn"); req=0; step; end
    endtask
    initial begin
        repeat(2) step; clear=0; spawn;
        repeat(30) step;
        if(hits!=1) $fatal(1,"zombie in diagonal contact range could not attack");
        while(!dut.field_ready) step;
        tick=1; step; tick=0; while(dut.move_state!=0) step;
        if(x!=384 || y!=384) $fatal(1,"diagonal contact did not stop movement");
        clear=1; step; clear=0; hits=0; walls[8'h12]=1; spawn;
        repeat(30) step;
        if(hits) $fatal(1,"diagonal contact cut a side wall");
        clear=1; step; clear=0; walls=0; walls[8'h21]=1; spawn;
        repeat(30) step;
        if(hits) $fatal(1,"diagonal contact cut the other side wall");
        $display("TB_ENEMY_DIAGONAL_CONTACT: PASS"); $finish;
    end
    initial begin #100000; $fatal(1,"diagonal contact timeout"); end
endmodule
