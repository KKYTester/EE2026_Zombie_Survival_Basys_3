`timescale 1ns / 1ps
module tb_enemy_manager;
    reg clk=0, rst=1, clear=0, playing=1, ready=1;
    reg [255:0] map_bits=0;
    reg req=0, defeat=0;
    reg move_tick=0, spawn_busy=0;
    reg shot_fired=0;
    reg [1:0] aim=0;
    wire shot_hit, player_hit;
    reg [7:0] player_tile=8'h42;
    reg [7:0] tile=0;
    reg [2:0] id=0;
    wire ack, dead, valid;
    wire [255:0] occupied;
    wire [7:0] active, hp;
    wire [31:0] x,y;
    wire [1:0] kind,state;
    wire [15:0] cooldown;
    integer acks=0, deaths=0, hits=0, player_hits=0, i;
    always @(posedge clk) if(shot_hit) hits=hits+1;
    always #5 clk=~clk;
    always @(posedge clk) begin
        #1;
        if(ack) acks=acks+1;
        if(dead) deaths=deaths+1;
        if(player_hit) player_hits=player_hits+1;
    end
    enemy_manager #(.MOVE_SUBSTEPS(1),.ATTACK_COOLDOWN_CYCLES(16)) dut(
        .clk(clk),.rst(rst),.clear(clear),.playing(playing),
        .map_ready(ready),.map_bits(map_bits),.spawn_req(req),.spawn_tile(tile),
        .debug_defeat(defeat),.spawn_ack(ack),.enemy_defeated(dead),
        .move_tick(move_tick),.spawn_busy(spawn_busy),.player_tile(player_tile),
        .shot_fired(shot_fired),.aim(aim),.shot_hit(shot_hit),.player_hit(player_hit),
        .player_active(1'b1),.player2_active(1'b0),.player2_tile(8'd0),
        .shot_fired_p2(1'b0),.aim_p2(2'd0),
        .occupied(occupied),.active(active),.read_id(id),.read_active(valid),
        .read_x(x),.read_y(y),.read_hp(hp),.read_type(kind),.read_state(state),
        .read_cooldown(cooldown));

    // Drive between rising edges, then inspect settled registered outputs.
    task step; begin @(posedge clk); #2; @(negedge clk); end endtask
    task check(input condition, input [8*100-1:0] message);
        begin if(condition !== 1'b1) $fatal(1,"%0s",message); end
    endtask
    task sweep;
        begin move_tick=1; step; move_tick=0; repeat(48) step; end
    endtask
    task shoot(input [1:0] direction);
        begin
            aim=direction; shot_fired=1; step; shot_fired=0;
            aim=~direction; // Changes after the trigger must not turn the shot.
            repeat(52) step;
        end
    endtask
    task spawn(input [7:0] where);
        begin tile=where; req=1; step; check(ack,"spawn accepted"); req=0; step; end
    endtask
    initial begin
        @(negedge clk); step; rst=0;
        check(active==0 && occupied==0 && !ack && !dead,"reset clears outputs");

        // One acknowledgement even if the producer holds its request high.
        tile=8'h23; req=1; repeat(5) step;
        check(acks==1 && active==1 && occupied==(256'd1<<8'h23),"held request duplicated");
        check(valid && x==896 && y==640 && hp==3 && kind==0 && state==0 && cooldown==0,
              "spawn record / fixed-point tile center");
        req=0; step;
        // Occupied tiles and walls are not accepted.
        req=1; step; check(!ack && active==1,"duplicate tile accepted"); req=0; step;
        map_bits[8'h24]=1; tile=8'h24; req=1; step;
        check(!ack,"wall accepted"); req=0; map_bits=0; step;
        ready=0; tile=8'h25; req=1; step; check(!ack,"invalid map accepted");
        ready=1; playing=0; step; check(!ack,"spawn outside play");
        playing=1; step; check(ack,"waiting request not accepted when valid"); req=0; step;
        for(i=2;i<8;i=i+1) spawn(8'h30+i);
        check(active==8'hff && acks==8,"eight-slot capacity");

        // A pending ninth spawn waits; a death makes room on the next cycle.
        tile=8'h55; req=1; repeat(3) step; check(!ack && acks==8,"full pool overwritten");
        defeat=1; step; check(dead && !ack && active==8'hfe,"full pool death");
        defeat=0; step; check(ack && active==8'hff && acks==9,"freed slot not reused");
        id=0; #1; check(x==1408 && y==1408 && hp==3,"reused record not initialized");
        id=1; #1; check(x==1408 && y==640,"survivor ID shifted"); req=0; step;

        // A free slot allows spawn and removal together, with both events counted.
        defeat=1; step; defeat=0; step;
        tile=8'h66; req=1; defeat=1; step;
        check(ack && dead && active==8'hfd,"simultaneous spawn and death");
        check(occupied[8'h66] && !occupied[8'h25],"simultaneous occupancy update");
        req=0; defeat=0; step;
        id=1; #1; check(!valid && x==0 && hp==0,"inactive read leaked stale data");

        // Clear wins over pending operations and emits no gameplay deaths.
        clear=1; req=1; defeat=1; step;
        check(active==0 && occupied==0 && !ack && !dead,"clear priority");
        req=0; defeat=0; repeat(2) step; clear=0; step;
        defeat=1; step; check(!dead,"empty pool reported a death"); defeat=0;
        spawn(8'h77); rst=1; req=1; step;
        check(active==0 && occupied==0 && !ack && !dead,"reset during request");
        req=0; rst=0; step; spawn(8'h12);
        check(acks==12 && deaths==3,"event accounting");

        // The only route to 15 starts by stepping down, away from the goal.
        clear=1; step; clear=0;
        player_tile=8'h15; map_bits={256{1'b1}};
        map_bits[8'h11]=0; map_bits[8'h21]=0; map_bits[8'h31]=0;
        map_bits[8'h32]=0; map_bits[8'h33]=0; map_bits[8'h34]=0;
        map_bits[8'h35]=0; map_bits[8'h25]=0; map_bits[8'h15]=0;
        map_bits[8'h07]=0;
        spawn(8'h11); spawn(8'h07);
        while(!dut.field_ready) step;
        sweep;
        id=0; #1;
        check(occupied==((256'd1<<8'h21)|(256'd1<<8'h07)) && x==384 && y==640,
              "detour, isolated tile, or position/mask mismatch");
        repeat(8) sweep;
        check(occupied==((256'd1<<8'h25)|(256'd1<<8'h07)),
              "zombie did not follow corridor or stop short of player");

        // Two zombies want tile 32. Only the first can claim it.
        clear=1; step; clear=0;
        player_tile=8'h42; map_bits=0; map_bits[8'h41]=1; map_bits[8'h43]=1;
        spawn(8'h31); spawn(8'h33);
        while(!dut.field_ready) step;
        spawn_busy=1; sweep;
        check(occupied[8'h31] && occupied[8'h33],"movement during spawn search");
        spawn_busy=0; sweep;
        check(occupied==((256'd1<<8'h32)|(256'd1<<8'h33)),"two slots claimed one tile");
        sweep;
        check(!occupied[8'h42] && occupied[8'h32],"zombie stepped onto player");
        // Rebuild for a changed target. Old arrows must not be used meanwhile.
        player_tile=8'h12; sweep;
        check(occupied[8'h32] && occupied[8'h33],"stale field used after goal change");
        while(!dut.field_ready) step;
        sweep;
        check(occupied[8'h22] && occupied[8'h23],"new goal did not redirect movement");

        // Repeat the same contest with the slot that lost now going first.
        clear=1; step; clear=0;
        player_tile=8'h42; spawn(8'h31); spawn(8'h33);
        while(!dut.field_ready) step;
        sweep;
        check(occupied[8'h32] && occupied[8'h33],"slot zero did not win first contest");
        defeat=1; step; defeat=0; step;
        spawn(8'h31); sweep;
        check(occupied==((256'd1<<8'h31)|(256'd1<<8'h32)),
              "rotated sweep did not give slot one priority");

        // Rear slots wait, then move into space freed by the front zombie.
        clear=1; step; clear=0;
        player_tile=8'h15; map_bits={256{1'b1}};
        map_bits[8'h11]=0; map_bits[8'h12]=0; map_bits[8'h13]=0;
        map_bits[8'h14]=0; map_bits[8'h15]=0;
        spawn(8'h11); spawn(8'h12); spawn(8'h13);
        while(!dut.field_ready) step;
        sweep;
        check(occupied==((256'd1<<8'h11)|(256'd1<<8'h12)|(256'd1<<8'h14)),
              "corridor queue did not hold behind the front zombie");
        sweep;
        check(occupied==((256'd1<<8'h12)|(256'd1<<8'h13)|(256'd1<<8'h14)),
              "corridor queue did not advance into free tiles");

        // A removal between validation and commit invalidates the pending move.
        clear=1; step; clear=0; map_bits=0;
        spawn(8'h02);
        while(!dut.field_ready) step;
        move_tick=1; step; move_tick=0; repeat(4) step;
        defeat=1; step; defeat=0; repeat(48) step;
        check(active==0 && occupied==0,"interrupted move resurrected removed zombie");

        // No wrap at an open map edge, even with an enemy on the next row.
        clear=1; step; clear=0; map_bits=0; player_tile=8'h2f;
        spawn(8'h30); shoot(2'd0);
        id=0; #1; check(hp==3 && hits==0,"shot wrapped at right edge");

        // A wall shields the far enemy. After the wall test, rebuild the demo.
        clear=1; step; clear=0; player_tile=8'h21; map_bits[8'h23]=1;
        spawn(8'h25); shoot(2'd0);
        check(hp==3 && hits==0,"shot hit enemy through a wall");
        shoot(2'd1);
        check(hp==3 && hits==0,"empty corridor reported a hit");

        clear=1; step; clear=0; map_bits=0;
        spawn(8'h25); spawn(8'h23); // Lower slot is farther away.
        i=deaths;
        shoot(2'd0);
        check(hp==3 && hits==1 && deaths==i,"shot selected the farther slot");
        id=1; #1; check(hp==2,"first hit did not reduce HP");
        shoot(2'd0); check(hp==1 && deaths==i,"second hit killed too early");
        shoot(2'd0);
        check(hits==3 && deaths==i+1 && !valid && !occupied[8'h23] && occupied[8'h25],
              "third hit did not free exactly the nearer zombie");
        spawn(8'h24); #1;
        check(valid && hp==3,"reused slot kept old damage");

        // A ray and movement tick together use the pre-move tile ownership.
        clear=1; step; clear=0; player_tile=8'h21;
        spawn(8'h51);
        while(!dut.field_ready) step;
        aim=2'd1; shot_fired=1; move_tick=1; step;
        shot_fired=0; move_tick=0; repeat(52) step;
        id=0; #1;
        check(hp==2 && occupied[8'h51],"movement conflicted with a shot");

        // Two adjacent zombies share a single player cooldown.
        clear=1; step; clear=0; player_tile=8'h00; map_bits=0;
        spawn(8'h23); spawn(8'h21);
        i=player_hits;
        player_tile=8'h22;
        repeat(6) step;
        check(player_hits==i+1,"adjacent zombies did not produce exactly one hit");
        repeat(10) step;
        check(player_hits==i+1,"hit repeated during cooldown");
        repeat(9) step;
        check(player_hits==i+2,"adjacent zombie did not attack after cooldown");
        defeat=1; repeat(2) step; defeat=0;
        repeat(24) step;
        check(player_hits==i+2,"removed zombie still dealt damage");

        clear=1; step; clear=0; player_tile=8'h30;
        spawn(8'h2f); spawn(8'h21); // Wrapped and diagonal tiles.
        repeat(24) step;
        check(player_hits==i+2,"wrapped or diagonal attack");
        playing=0;
        player_tile=8'h2e; // Adjacent to a live zombie.
        repeat(24) step;
        check(player_hits==i+2,"attack outside gameplay");
        $display("TB_ENEMY_MANAGER: PASS"); $finish;
    end
    initial begin #200000; $fatal(1,"timeout"); end
endmodule
