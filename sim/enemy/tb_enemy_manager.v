`timescale 1ns / 1ps
module tb_enemy_manager;
    reg clk=0, rst=1, clear=0, playing=1, ready=1;
    reg [255:0] map_bits=0;
    reg req=0, defeat=0;
    reg move_tick=0, spawn_busy=0;
    reg [7:0] player_tile=8'h42;
    reg [7:0] tile=0;
    reg [2:0] id=0;
    wire ack, dead, valid;
    wire [255:0] occupied;
    wire [7:0] active, hp;
    wire [31:0] x,y;
    wire [1:0] kind,state;
    wire [15:0] cooldown;
    integer acks=0, deaths=0, i;
    always #5 clk=~clk;
    always @(posedge clk) begin
        #1;
        if(ack) acks=acks+1;
        if(dead) deaths=deaths+1;
    end
    enemy_manager dut(.clk(clk),.rst(rst),.clear(clear),.playing(playing),
        .map_ready(ready),.map_bits(map_bits),.spawn_req(req),.spawn_tile(tile),
        .debug_defeat(defeat),.spawn_ack(ack),.enemy_defeated(dead),
        .move_tick(move_tick),.spawn_busy(spawn_busy),.player_tile(player_tile),
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

        // Wall on the preferred axis forces a step on the other axis.
        clear=1; step; clear=0;
        player_tile=8'h25; map_bits[8'h12]=1;
        spawn(8'h11); sweep;
        id=0; #1;
        check(occupied==(256'd1<<8'h21) && x==384 && y==640,
              "wall fallback or position/mask mismatch");
        map_bits[8'h22]=1; sweep;
        check(occupied==(256'd1<<8'h21),"blocked zombie moved");
        map_bits=0;

        // Two zombies want tile 32. Only the first can claim it.
        clear=1; step; clear=0;
        player_tile=8'h42; spawn(8'h31); spawn(8'h33);
        map_bits[8'h43]=1;
        spawn_busy=1; sweep;
        check(occupied[8'h31] && occupied[8'h33],"movement during spawn search");
        spawn_busy=0; sweep;
        check(occupied==((256'd1<<8'h32)|(256'd1<<8'h33)),"two slots claimed one tile");
        sweep;
        check(!occupied[8'h42] && occupied[8'h32],"zombie stepped onto player");

        // A removal between validation and commit invalidates the pending move.
        clear=1; step; clear=0; map_bits=0;
        spawn(8'h02);
        move_tick=1; step; move_tick=0; repeat(3) step;
        defeat=1; step; defeat=0; repeat(48) step;
        check(active==0 && occupied==0,"interrupted move resurrected removed zombie");
        $display("TB_ENEMY_MANAGER: PASS"); $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
