`timescale 1ns / 1ps
module tb_enemy_diagonal;
    reg clk=0, clear=1, tick=0, req=0, defeat=0, fire=0;
    reg [255:0] walls=0;
    reg [7:0] spawn_tile=0, goal=8'h44;
    wire [95:0] xs,ys;
    wire [7:0] active;
    wire [255:0] occupied, reserved;
    wire ack, hit, kill;
    integer i,j, shot_number, clocks, hits=0, kills=0;
    reg [255:0] expected_reservations;
    reg [7:0] a,b;
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(hit) hits<=hits+1;
        if(kill) kills<=kills+1;
    end
    enemy_manager dut(.clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.spawn_req(req),.spawn_tile(spawn_tile),.debug_defeat(defeat),
        .move_tick(tick),.spawn_busy(1'b0),.player_tile(goal),.shot_fired(fire),.aim(2'd0),
        .player_active(1'b1),.player2_active(1'b0),.player2_tile(8'd0),.shot_fired_p2(1'b0),
        .aim_p2(2'd0),.occupied(occupied),.spawn_occupied(reserved),.active(active),
        .spawn_ack(ack),.shot_hit(hit),.shot_kill(kill),.render_x(xs),.render_y(ys),.read_id(3'd0));
    task step; begin @(negedge clk); end endtask
    task spawn(input [7:0] tile);
        begin spawn_tile=tile; req=1; step; if(!ack) $fatal(1,"diagonal spawn"); req=0; step; end
    endtask
    task sweep;
        begin while(!dut.field_ready) step; tick=1; step; tick=0; while(dut.move_state!=0) step; end
    endtask
    always @(posedge clk) begin
        #1;
        if(!clear) begin
            expected_reservations=occupied;
            for(i=0;i<8;i=i+1) if(active[i] && dut.moving[i]) begin
                a=dut.travel_origin[i]; b=dut.travel_destination[i];
                expected_reservations[a]=1; expected_reservations[b]=1;
                if(a[3:0]!=b[3:0] && a[7:4]!=b[7:4]) begin
                    expected_reservations[{a[7:4],b[3:0]}]=1;
                    expected_reservations[{b[7:4],a[3:0]}]=1;
                end
                if(dut.has_look_reservation[i]) begin
                    a=b; b=dut.look_reservation[i];
                    expected_reservations[b]=1;
                    if(a[3:0]!=b[3:0] && a[7:4]!=b[7:4]) begin
                        expected_reservations[{a[7:4],b[3:0]}]=1;
                        expected_reservations[{b[7:4],a[3:0]}]=1;
                    end
                end
            end
            if(reserved!==expected_reservations) $fatal(1,"cached reservation ownership mismatch");
            if((occupied & walls)!=0) $fatal(1,"diagonal entered wall");
            for(i=0;i<8;i=i+1) if(active[i]) begin
                if(!occupied[{ys[12*i+8+:4],xs[12*i+8+:4]}]) $fatal(1,"diagonal occupancy mismatch");
                for(j=i+1;j<8;j=j+1) if(active[j] &&
                    {ys[12*i+8+:4],xs[12*i+8+:4]}=={ys[12*j+8+:4],xs[12*j+8+:4]})
                    $fatal(1,"diagonal zombies overlap");
            end
        end
    end
    initial begin
        repeat(2) step; clear=0; spawn(8'h11); sweep;
        if(xs[0+:12]<=384 || ys[0+:12]<=384 || xs[0+:12]-384>6 || xs[0+:12]!=ys[0+:12])
            $fatal(1,"diagonal movement or speed scaling");
        if(!reserved[8'h11] || !reserved[8'h12] || !reserved[8'h21] || !reserved[8'h22])
            $fatal(1,"diagonal side cells not reserved");
        spawn_tile=8'h12; req=1; step; if(ack) $fatal(1,"spawn into diagonal side"); req=0; step;
        repeat(60) sweep;
        if(xs[0+:12]<=640 || ys[0+:12]<=640) $fatal(1,"diagonal did not arrive and continue");
        defeat=1; step; defeat=0; step;
        if(active || reserved) $fatal(1,"death leaked a moving diagonal reservation");
        // Inject conflicting legal routes to isolate reservation arbitration.
        clear=1; step; clear=0; spawn(8'h11); spawn(8'h12);
        while(!dut.field_ready) step;
        dut.routes.arrows[8'h11]=5; dut.routes.arrows[8'h12]=7;
        dut.routes.arrows[8'h22]=4; dut.routes.arrows[8'h21]=6;
        sweep;
        if(dut.moving || xs[0+:12]!=384 || xs[12+:12]!=640 || ys[12+:12]!=384)
            $fatal(1,"crossing diagonal swept squares were not blocked");
        defeat=1; step; defeat=0; step;
        if(reserved[8'h21] || reserved[8'h22]) $fatal(1,"death leaked diagonal reservation");
        sweep;
        if(!dut.moving[1]) $fatal(1,"crossing wait did not resume after release");
        // Opposite edges cannot swap through one another.
        clear=1; step; clear=0; spawn(8'h11); spawn(8'h12);
        while(!dut.field_ready) step;
        dut.routes.arrows[8'h11]=1; dut.routes.arrows[8'h12]=0;
        sweep;
        if(dut.moving || xs[0+:12]!=384 || xs[12+:12]!=640) $fatal(1,"head-on swap accepted");
        // Recheck a stale/invalid diagonal arrow against actual map walls.
        clear=1; step; clear=0; walls[8'h12]=1; spawn(8'h11);
        while(!dut.field_ready) step;
        dut.routes.arrows[8'h11]=5;
        sweep;
        if(dut.moving || xs[0+:12]!=384 || ys[0+:12]!=384) $fatal(1,"stale diagonal crossed side wall");
        clear=1; step;
        if(active || reserved) $fatal(1,"diagonal reset retained reservations");

        // Shoot the second slot while it owns a diagonal and its lookahead.
        // The first slot is moving too and must keep its separate reservation.
        walls=0; clear=0; goal=8'h44;
        spawn(8'h66); spawn(8'h11); sweep;
        if(dut.moving[1:0]!=2'b11 || dut.has_look_reservation[1:0]!=2'b11 || !reserved[8'h33])
            $fatal(1,"test did not reserve both moving footprints");
        goal=8'h10;
        for(shot_number=1;shot_number<=3;shot_number=shot_number+1) begin
            fire=1; step; fire=0;
            for(clocks=0;hits<shot_number && clocks<1500;clocks=clocks+1) step;
            if(hits!=shot_number) $fatal(1,"moving zombie did not take the shot");
            if(shot_number<3 && (kills!=0 || active!=8'h03 || !reserved[8'h33]))
                $fatal(1,"nonlethal shot changed a reservation");
        end
        if(kills!=1 || active!=8'h01 || reserved[8'h11] || reserved[8'h12] ||
           reserved[8'h21] || reserved[8'h22] || reserved[8'h33] || !reserved[8'h55])
            $fatal(1,"lethal shot did not release only the hit zombie's full footprint");
        $display("TB_ENEMY_DIAGONAL: PASS"); $finish;
    end
    initial begin #1000000; $fatal(1,"diagonal movement timeout"); end
endmodule
