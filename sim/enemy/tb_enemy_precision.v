`timescale 1ns / 1ps
module tb_enemy_precision;
    reg clk=0, clear=1, req=0, tick=0;
    wire [27:0] x,y;
    wire ack;
    always #5 clk=~clk;
    // Wide fractional coordinates catch overflow in lookahead and blending.
    enemy_manager #(.MAX_ENEMIES(1),.COORD_FRAC_BITS(24)) dut(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(256'd0),.spawn_req(req),.spawn_tile(8'h11),.debug_defeat(1'b0),
        .move_tick(tick),.spawn_busy(1'b0),.player_tile(8'h44),.shot_fired(1'b0),
        .aim(2'd0),.player_active(1'b1),.player2_active(1'b0),.player2_tile(8'd0),
        .shot_fired_p2(1'b0),.aim_p2(2'd0),.render_x(x),.render_y(y),
        .read_id(1'b0),.spawn_ack(ack));
    initial begin
        repeat(2) @(negedge clk); clear=0; req=1; @(negedge clk);
        if(!ack) $fatal(1,"precision spawn");
        req=0; while(!dut.field_ready) @(negedge clk);
        tick=1; @(negedge clk); tick=0;
        while(dut.move_state!=0) @(negedge clk);
        // Diagonal unit direction lies between 0.70 and 0.71 on each axis.
        if(x!=y || x-25165824<367001 || x-25165824>372245)
            $fatal(1,"wide coordinate arithmetic overflow: %d %d",x,y);
        $display("TB_ENEMY_PRECISION: PASS"); $finish;
    end
    initial begin #100000; $fatal(1,"precision timeout"); end
endmodule
