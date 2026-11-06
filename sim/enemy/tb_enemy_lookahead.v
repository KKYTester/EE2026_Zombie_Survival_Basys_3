`timescale 1ns / 1ps
module tb_enemy_lookahead;
    reg clk=0, clear=1, tick=0, req=0, defeat=0;
    reg [255:0] walls={256{1'b1}};
    reg [7:0] goal=8'h42, spawn_tile=8'h11;
    wire [95:0] xs, ys;
    wire [7:0] active;
    wire [255:0] occupied, reserved;
    wire ack;
    integer i;
    always #5 clk=~clk;
    enemy_manager dut(.clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.spawn_req(req),.spawn_tile(spawn_tile),.debug_defeat(defeat),
        .move_tick(tick),.spawn_busy(1'b0),.player_tile(goal),.shot_fired(1'b0),.aim(2'd0),
        .player_active(1'b1),.player2_active(1'b0),.player2_tile(8'd0),.shot_fired_p2(1'b0),
        .aim_p2(2'd0),.occupied(occupied),.spawn_occupied(reserved),.active(active),
        .spawn_ack(ack),.render_x(xs),.render_y(ys),.read_id(3'd0));
    task step; begin @(negedge clk); end endtask
    task spawn(input [7:0] tile);
        begin spawn_tile=tile; req=1; step; if(!ack) $fatal(1,"lookahead spawn"); req=0; step; end
    endtask
    task sweep;
        begin while(!dut.field_ready) step; tick=1; step; tick=0;
            while(dut.move_state!=0) step;
        end
    endtask
    always @(posedge clk) begin
        #1;
        if(!clear) begin
            if((occupied & walls)!=0) $fatal(1,"lookahead entered wall");
            for(i=0;i<8;i=i+1) if(active[i] &&
                !occupied[{ys[12*i+8+:4],xs[12*i+8+:4]}]) $fatal(1,"occupancy mismatch");
        end
    end
    initial begin
        walls[8'h11]=0; walls[8'h12]=0; walls[8'h22]=0; walls[8'h32]=0; walls[8'h42]=0;
        repeat(2) step; clear=0; spawn(8'h11);
        repeat(24) sweep;
        if(xs[0+:12]!=576 || ys[0+:12]!=384 || !reserved[8'h22])
            $fatal(1,"quarter-tile lookahead or reservation");
        sweep; sweep;
        if(xs[0+:12]<=576 || ys[0+:12]<=384 || xs[0+:12]>=640)
            $fatal(1,"direction did not blend before the corner");
        repeat(100) sweep;
        if(xs[0+:12]<632 || ys[0+:12]<896) $fatal(1,"failed to follow L path");
        clear=1; step; clear=0; goal=8'h32;
        spawn(8'h22); spawn(8'h11);
        repeat(60) sweep;
        if(xs[12+:12]!=640 || ys[12+:12]!=384 || !occupied[8'h22])
            $fatal(1,"lookahead cut into a blocked path");
        defeat=1; step; defeat=0; step;
        repeat(90) sweep;
        if(ys[12+:12]<=384) $fatal(1,"blocked zombie failed to resume");
        clear=1; step;
        if(active || reserved || dut.moving) $fatal(1,"lookahead reset retained reservations");
        $display("TB_ENEMY_LOOKAHEAD: PASS"); $finish;
    end
    initial begin #1000000; $fatal(1,"lookahead timeout"); end
endmodule

