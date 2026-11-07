`timescale 1ns / 1ps
module tb_enemy_hearing;
    localparam IDLE=0, CHASE=1, MEMORY=2, SEARCH=3;
    reg clk=0, clear=1, tick=0, req=0, defeat=0;
    reg live1=1, live2=1, fire1=0, fire2=0;
    reg [7:0] p1=8'h6d, p2=8'h6e, spawn_tile=0;
    reg [31:0] shot_x1=0, shot_y1=0, shot_x2=0, shot_y2=0;
    reg [255:0] walls;
    wire ack, ready1, ready2;
    wire [1:0] active, state;
    wire [23:0] x, y;
    wire [255:0] occupied, spawn_occupied;
    integer i, cycles;

    always #5 clk=~clk;
    enemy_manager #(.MAX_ENEMIES(2),.TWO_PLAYERS(1),.USE_AWARENESS(1),
        .USE_CAMERA_RAY(1),.ATTACK_WINDUP_CYCLES(40)) dut(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.spawn_req(req),.spawn_tile(spawn_tile),.debug_defeat(defeat),
        .move_tick(tick),.spawn_busy(1'b0),.player_tile(p1),.player2_tile(p2),
        .player_active(live1),.player2_active(live2),.shot_fired(fire1),.shot_fired_p2(fire2),
        .camera_x(shot_x1),.camera_y(shot_y1),.camera_angle(10'd0),
        .camera2_x(shot_x2),.camera2_y(shot_y2),.camera2_angle(10'd0),
        .aim(2'd0),.aim_p2(2'd0),.spawn_ack(ack),.active(active),
        .shot_ready(ready1),.shot_ready_p2(ready2),.occupied(occupied),
        .spawn_occupied(spawn_occupied),.render_x(x),.render_y(y),
        .read_id(1'b0),.read_state(state));

    task reset_round;
        begin
            clear=1; @(negedge clk);
            p1=8'h6d; p2=8'h6e; live1=1; live2=1;
            clear=0; @(negedge clk);
        end
    endtask
    task spawn(input [7:0] tile);
        begin
            spawn_tile=tile; req=1; @(negedge clk);
            if(!ack) $fatal(1,"spawn rejected at %h",tile);
            req=0; @(negedge clk);
        end
    endtask
    task wait_combat;
        begin
            for(cycles=0;dut.combat_locked && cycles<1500;cycles=cycles+1) @(negedge clk);
            if(dut.combat_locked) $fatal(1,"combat stalled");
        end
    endtask
    task pulse_shots(input [1:0] mask);
        begin
            if((mask[0] && !ready1) || (mask[1] && !ready2)) $fatal(1,"mailbox unexpectedly busy");
            {fire2,fire1}=mask; @(negedge clk); {fire2,fire1}=0;
            // Move the packet pose immediately after acceptance.
            shot_x1=0; shot_y1=0; shot_x2=0; shot_y2=0;
        end
    endtask
    task shoot(input [1:0] mask, input [7:0] a, b);
        begin
            shot_x1={16'd0,a[3:0],12'h800};
            shot_y1=32'd65536-{16'd0,a[7:4],12'h800};
            shot_x2={16'd0,b[3:0],12'h800};
            shot_y2=32'd65536-{16'd0,b[7:4],12'h800};
            pulse_shots(mask); wait_combat;
        end
    endtask
    task await_sweep;
        begin
            for(cycles=0;dut.move_state!=0 && cycles<18000;cycles=cycles+1) @(negedge clk);
            if(dut.move_state!=0) $fatal(1,"hearing sweep stalled");
        end
    endtask
    task sweep;
        begin
            tick=1; @(negedge clk); tick=0;
            if(dut.move_state==0) $fatal(1,"movement tick not accepted");
            await_sweep;
        end
    endtask
    task investigate(input [7:0] tile);
        begin
            if(state!=MEMORY || !dut.memory_is_sound[0] || dut.investigate_tile[0]!=tile)
                $fatal(1,"expected sound target %h, got %h state %d",tile,dut.investigate_tile[0],state);
        end
    endtask

    initial begin
        // From 42, tile 51 takes two hops around one corner. The route to
        // 65 takes five, 66 takes six, and 67 takes seven.
        walls={256{1'b1}};
        for(i=1;i<=10;i=i+1) walls[8'h40+i]=0;
        walls[8'h51]=0; walls[8'h55]=0; walls[8'h65]=0; walls[8'h66]=0;
        walls[8'h67]=0; walls[8'h6d]=0; walls[8'h6e]=0; walls[8'h77]=0;

        reset_round; spawn(8'h42);
        shoot(2'b01,8'h67,0); sweep;
        if(state!=IDLE) $fatal(1,"heard seven-hop shot");
        shoot(2'b01,8'h66,0); sweep; investigate(8'h66);
        if(x[11:0]<=12'h280) $fatal(1,"did not start walking around the corner");
        // A wall tile and an invalid position must leave the current memory alone.
        shoot(2'b01,8'h54,0); sweep; investigate(8'h66);
        shot_x1=32'h10000; shot_y1=32'h9800; pulse_shots(2'b01); wait_combat;
        sweep; investigate(8'h66);

        // Two accepted shots in one sweep select the shortest legal route.
        shoot(2'b11,8'h65,8'h51); sweep; investigate(8'h51);
        shoot(2'b10,0,8'h65); sweep; investigate(8'h65);
        for(i=0;i<220 && state!=SEARCH;i=i+1) sweep;
        if(state!=SEARCH || x[11:0]!=12'h580 || y[11:0]!=12'h680 || spawn_occupied!=occupied)
            $fatal(1,"investigation did not finish at the old firing tile");
        repeat(24) sweep;
        if(state!=IDLE) $fatal(1,"consumed sound kept refreshing search");

        reset_round; spawn(8'h42);
        shoot(2'b11,8'h44,8'h51); sweep; investigate(8'h44); // Equal hop cost.
        shoot(2'b11,8'h51,8'h51); sweep; investigate(8'h51); // Same source.
        shoot(2'b11,8'h54,8'h65); sweep; investigate(8'h65); // Invalid first root.

        reset_round; spawn(8'h42);
        shoot(2'b01,8'h51,0); shoot(2'b01,8'h65,0); sweep; investigate(8'h65);
        live2=0; @(negedge clk);
        shot_x2=32'h1800; shot_y2=32'ha800; fire2=1; @(negedge clk); fire2=0;
        sweep; investigate(8'h65);

        reset_round; spawn(8'h42); p1=8'h46;
        shoot(2'b10,0,8'h51); sweep;
        if(state!=CHASE || dut.memory_is_sound[0] || dut.last_seen[0]!=8'h46)
            $fatal(1,"sound distracted a zombie with a visible target");
        p1=8'h6d; sweep;
        if(state!=MEMORY || dut.memory_is_sound[0]) $fatal(1,"discarded sound replayed after sight loss");
        shoot(2'b10,0,8'h65); sweep; investigate(8'h65);
        if(dut.last_seen[0]!=8'h46) $fatal(1,"sound overwrote last-seen tile");
        p2=8'h47; sweep;
        if(state!=CHASE || dut.memory_is_sound[0] || dut.last_seen[0]!=8'h47)
            $fatal(1,"visible player did not override investigation");

        reset_round; spawn(8'h42); spawn(8'h48);
        shoot(2'b11,8'h65,8'h51); sweep; investigate(8'h51);
        if(!dut.memory_is_sound[1] || dut.investigate_tile[1]!=8'h65)
            $fatal(1,"zombies did not choose independently");

        reset_round; spawn(8'h42);
        // An event arriving after the batch was frozen is heard next sweep.
        tick=1; @(negedge clk); tick=0;
        shoot(2'b01,8'h65,0); await_sweep;
        if(state!=IDLE) $fatal(1,"mid-sweep event changed the active batch");
        sweep; investigate(8'h65);

        // A shot can interrupt a build without replacing its frozen source.
        shoot(2'b01,8'h66,0);
        tick=1; @(negedge clk); tick=0;
        while(dut.move_state!=dut.MOVE_HEAR_WAIT) @(negedge clk);
        shoot(2'b10,0,8'h51); await_sweep; investigate(8'h66);
        sweep; investigate(8'h51);

        shoot(2'b01,8'h51,0);
        defeat=1; @(negedge clk); defeat=0;
        if(active!=0 || spawn_occupied!=0) $fatal(1,"removal left occupied tiles");
        spawn(8'h42); sweep;
        if(state!=IDLE || dut.memory_is_sound[0]) $fatal(1,"new slot heard old shot");
        shoot(2'b01,8'h51,0); reset_round; spawn(8'h42); sweep;
        if(state!=IDLE) $fatal(1,"pending shot survived reset");

        // Exact north-grid boundary belongs to the south row used by combat.
        shot_x2=32'h5800; shot_y2=32'ha000;
        pulse_shots(2'b10); wait_combat; sweep; investigate(8'h65);

        walls[8'h67]=1;
        reset_round; spawn(8'h77);
        shoot(2'b01,8'h66,0); sweep;
        if(state!=IDLE) $fatal(1,"sound cut a closed diagonal into a disconnected tile");
        shoot(2'b01,8'h77,0); sweep;
        if(state!=SEARCH || !dut.memory_is_sound[0] || dut.investigate_tile[0]!=8'h77)
            $fatal(1,"shot on current tile did not start a local search");

        $display("TB_ENEMY_HEARING: PASS"); $finish;
    end
    initial begin #15000000; $fatal(1,"hearing test timeout"); end
endmodule
