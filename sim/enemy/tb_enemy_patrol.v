`timescale 1ns / 1ps
module tb_enemy_patrol;
    reg clk=0, clear=1, tick=0, request=0, fire=0, live=1;
    reg [7:0] p1=8'hee, spawn_tile=0, waypoint1=8'h22, waypoint2=8'h6c;
    reg [255:0] walls;
    wire [255:0] occupied, footprint;
    wire [23:0] x, y;
    wire [1:0] state;
    wire ack;
    wire [7:0] tile0={y[11:8],x[11:8]}, tile1={y[23:20],x[23:20]};
    reg [7:0] shot_tile;
    reg crossed_door;
    integer i, j, elapsed;
    always #5 clk=~clk;

    enemy_manager #(.MAX_ENEMIES(2),.TWO_PLAYERS(1),.USE_AWARENESS(1),
        .USE_WANDER(1),.USE_PATROL(1),.ATTACK_WINDUP_CYCLES(40)) dut(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.wander_seed(16'hbeef),.patrol_tile1(waypoint1),.patrol_tile2(waypoint2),
        .spawn_req(request),.spawn_tile(spawn_tile),.debug_defeat(1'b0),.move_tick(tick),
        .spawn_busy(1'b0),.player_tile(p1),.player2_tile(8'd0),.player_active(live),
        .player2_active(1'b0),.shot_fired(fire),.shot_fired_p2(1'b0),
        .aim(2'd1),.aim_p2(2'd0),.spawn_ack(ack),.occupied(occupied),
        .spawn_occupied(footprint),.render_x(x),.render_y(y),.read_id(1'b0),.read_state(state));

    task restart;
        begin
            clear=1; @(negedge clk);
            p1=8'hee; live=1; clear=0; @(negedge clk);
        end
    endtask
    task spawn(input [7:0] tile);
        begin
            spawn_tile=tile; request=1; @(negedge clk);
            if(!ack) $fatal(1,"spawn rejected at %h",tile);
            request=0; @(negedge clk);
        end
    endtask
    task sweep;
        begin
            tick=1; @(negedge clk); tick=0;
            for(elapsed=0;dut.move_state!=0 && elapsed<18000;elapsed=elapsed+1) @(negedge clk);
            if(dut.move_state!=0 || (footprint & walls)!=0) $fatal(1,"sweep stalled or entered a wall");
        end
    endtask
    task start_patrol;
        begin
            restart; spawn(8'h23);
            repeat(63) sweep;
            if(dut.patrolling!=0 || tile0[3:0]>=7 || state!=0)
                $fatal(1,"patrol started before the wandering period");
            sweep;
            if(!dut.patrolling[0] || !dut.patrol_second[0])
                $fatal(1,"zombie failed to pick the farther waypoint");
        end
    endtask

    initial begin
        walls={256{1'b1}}; walls[8'hee]=0; walls[8'h47]=0;
        for(i=2;i<=6;i=i+1) for(j=2;j<=12;j=j+1)
            if(j!=7) walls[{i[3:0],j[3:0]}]=0;
        start_patrol;
        crossed_door=0;
        for(i=0;i<600 && dut.patrolling[0];i=i+1) begin
            sweep;
            if(tile0==8'h47) crossed_door=1;
        end
        if(!crossed_door || dut.patrolling[0] || tile0!=waypoint2 || state!=0 ||
           dut.patrol_ticks[0]!=7'd64)
            $fatal(1,"patrol did not go through the doorway and return to wandering");

        start_patrol;
        p1=tile0; sweep;
        if(state!=1 || dut.patrolling[0] || dut.patrol_ticks[0]!=7'd64)
            $fatal(1,"sight failed to cancel patrol");

        start_patrol;
        shot_tile=tile0; p1=shot_tile; fire=1; @(negedge clk); fire=0; p1=8'hee;
        while(dut.combat_locked) @(negedge clk);
        sweep;
        if(dut.patrolling[0] || !dut.memory_is_sound[0] || dut.investigate_tile[0]!=shot_tile)
            $fatal(1,"hearing failed to cancel patrol");

        walls={256{1'b1}}; walls[8'hee]=0; walls[8'h44]=0; walls[8'h45]=0;
        waypoint1=8'h44; waypoint2=8'h45; restart; spawn(waypoint1); spawn(waypoint2);
        repeat(64) sweep;
        if(dut.patrolling!=2'b01) $fatal(1,"patrol starts were not staggered");
        repeat(4) sweep;
        if(dut.patrolling!=2'b11) $fatal(1,"second slot did not begin its patrol");
        repeat(65) sweep;
        if(dut.patrolling!=0 || tile0!=waypoint1 || tile1!=waypoint2 || footprint!=occupied)
            $fatal(1,"blocked patrol failed to time out cleanly");

        walls[8'h45]=1; walls[8'h77]=0; waypoint2=8'h77;
        restart; spawn(waypoint1); repeat(64) sweep;
        if(dut.patrolling!=0 || dut.patrol_ticks[0]!=7'd64 || tile0!=waypoint1)
            $fatal(1,"unreachable waypoint did not fall back to wandering");

        $display("TB_ENEMY_PATROL: PASS"); $finish;
    end
    initial begin #15000000; $fatal(1,"patrol test timeout"); end
endmodule
