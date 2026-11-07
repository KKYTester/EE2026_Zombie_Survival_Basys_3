`timescale 1ns / 1ps
module tb_enemy_awareness;
    localparam IDLE=0, CHASE=1, LAST_SEEN=2, SEARCH=3;
    reg clk=0, clear=1, tick=0, req=0, defeat=0, spawn_busy=0;
    reg live1=1, live2=0;
    reg [7:0] p1=0, p2=0, spawn_tile=0;
    reg [255:0] walls=0;
    wire ack, hit1, hit2;
    wire [1:0] active, windup;
    wire [23:0] x, y;
    wire [255:0] occupied, spawn_occupied;
    wire [1:0] state;
    wire sight_checks_done;
    integer i, wait_cycles, hits1=0, hits2=0;
    reg [11:0] old_x;

    always #5 clk=~clk;
    always @(posedge clk) begin
        if(clear) begin hits1<=0; hits2<=0; end
        else begin
            if(hit1) hits1<=hits1+1;
            if(hit2) hits2<=hits2+1;
        end
    end
    sight_checks rays(.clk(clk),.done(sight_checks_done));
    enemy_manager #(.MAX_ENEMIES(2),.TWO_PLAYERS(1),.USE_AWARENESS(1),.USE_PLAYER_POSITIONS(1),
        .ATTACK_WINDUP_CYCLES(40),.ATTACK_RECOVERY_CYCLES(10)) dut(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.spawn_req(req),.spawn_tile(spawn_tile),.debug_defeat(defeat),
        .move_tick(tick),.spawn_busy(spawn_busy),.player_tile(p1),.player2_tile(p2),
        .player_pos_x({20'd0,p1[3:0],8'h80}),.player_pos_y({20'd0,p1[7:4],8'h80}),
        .player2_pos_x({20'd0,p2[3:0],8'h80}),.player2_pos_y({20'd0,p2[7:4],8'h80}),
        .player_active(live1),.player2_active(live2),.shot_fired(1'b0),.shot_fired_p2(1'b0),
        .aim(2'd0),.aim_p2(2'd0),.spawn_ack(ack),.active(active),
        .player_hit(hit1),.player_hit_p2(hit2),.render_windup(windup),
        .render_x(x),.render_y(y),.occupied(occupied),.spawn_occupied(spawn_occupied),
        .read_id(1'b0),.read_state(state));

    task restart;
        begin
            clear=1; @(negedge clk);
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
    task sweep;
        begin
            tick=1; @(negedge clk); tick=0;
            for(wait_cycles=0; dut.move_state!=0 && wait_cycles<9500; wait_cycles=wait_cycles+1)
                @(negedge clk);
            if(dut.move_state!=0) $fatal(1,"awareness sweep stalled");
        end
    endtask

    initial begin
        p1=8'h4b; restart; spawn(8'h44); sweep;
        if(state!=IDLE || x[11:0]!=12'h480 || spawn_occupied!=occupied)
            $fatal(1,"zombie saw a player seven tiles away");
        p1=8'h4a; tick=1; @(negedge clk); tick=0;
        while(!dut.finish_awareness || dut.move_id!=0) @(negedge clk);
        spawn_busy=1;
        @(negedge clk); old_x=x[11:0];
        if(state!=CHASE || old_x<=12'h480)
            $fatal(1,"zombie failed to acquire a player at the six-tile boundary");
        spawn_busy=0; wait(dut.move_state==0); @(negedge clk);
        if(x[11:0]!=old_x) $fatal(1,"spawn interruption repeated an already committed move");

        walls=0; walls[8'h54]=1; p1=8'h64; p2=8'h48; live2=1;
        restart; spawn(8'h44); sweep;
        if(state!=CHASE || x[11:0]<=12'h480 || dut.last_seen[0]!=p2)
            $fatal(1,"closer hidden P1 distracted zombie from visible P2");

        walls=0; p1=8'h41; p2=8'h46;
        restart; spawn(8'h44); sweep;
        if(dut.preferred_player[0]!=1'b1) $fatal(1,"did not prefer nearer P2");
        p1=8'h42; sweep;
        if(dut.preferred_player[0]!=1'b1) $fatal(1,"equal-distance tie lost P2");
        p1=8'h43; old_x=x[11:0]; sweep;
        if(dut.preferred_player[0]!=1'b0 || x[11:0]>=old_x)
            $fatal(1,"zombie failed to turn when P1 became closer");
        live1=0; sweep;
        if(dut.preferred_player[0]!=1'b1 || dut.last_seen[0]!=p2)
            $fatal(1,"zombie failed to switch to visible P2 after P1 went down");

        live1=1; p1=8'h42; p2=8'h48;
        restart; spawn(8'h44); spawn(8'h46); sweep;
        if(dut.preferred_player!=2'b10 || x[11:0]>=12'h480 || x[23:12]<=12'h680)
            $fatal(1,"both zombies did not choose targets independently");

        p1=8'h41; p2=8'h47;
        restart; spawn(8'h44);
        tick=1; @(negedge clk); tick=0;
        while(dut.move_state!=dut.MOVE_ROUTE_WAIT) @(negedge clk);
        live1=0;
        wait(dut.move_state==0); @(negedge clk);
        if(state!=CHASE || dut.last_seen[0]!=p2 || x[11:0]<=12'h480)
            $fatal(1,"a player who died during the route build retained priority");
        p1=p2; live1=1; sweep;
        if(dut.preferred_player[0]!=1'b1 || dut.last_seen[0]!=p2)
            $fatal(1,"shared goal tile did not keep the preferred player");
        live1=0; live2=0;
        repeat(10) sweep;
        if(state!=IDLE || spawn_occupied!=occupied)
            $fatal(1,"losing both players left an active pursuit or stale reservation");

        live1=1;
        live2=0; p1=8'h47; walls={256{1'b1}};
        for(i=1;i<=10;i=i+1) walls[8'h40+i]=0;
        walls[8'h57]=0; walls[8'h67]=0; walls[8'h66]=0; walls[8'h65]=0;
        restart; spawn(8'h44); sweep;
        if(state!=CHASE) $fatal(1,"could not see player down the hallway");
        p1=8'h65; sweep;
        if(state!=LAST_SEEN || dut.last_seen[0]!=8'h47)
            $fatal(1,"followed the hidden player's new position");
        for(i=0;i<150 && state!=SEARCH;i=i+1) sweep;
        if(state!=SEARCH || x[11:0]!=12'h780 || y[11:0]!=12'h480 || spawn_occupied!=occupied)
            $fatal(1,"search did not begin at the saved tile centre with reservations released");
        repeat(23) sweep;
        if(state!=SEARCH) $fatal(1,"search expired early");
        sweep;
        if(state!=IDLE || x[11:0]!=12'h780 || y[11:0]!=12'h480)
            $fatal(1,"search did not expire into stationary idle");
        p1=8'h49; sweep;
        if(state!=CHASE || x[11:0]<=12'h780)
            $fatal(1,"zombie did not reacquire a player entering sight");
        defeat=1; @(negedge clk); defeat=0;
        if(active!=0 || spawn_occupied!=0) $fatal(1,"death leaked a reservation");
        p1=8'h65; spawn(8'h44); sweep;
        if(state!=IDLE || dut.memory_left[0]!=0 || x[11:0]!=12'h480)
            $fatal(1,"reused slot inherited a previous target");

        walls=0; p1=8'h43; p2=8'h45; live2=1;
        restart; spawn(8'h44); sweep;
        repeat(20) @(negedge clk);
        if(windup!=2'b01) $fatal(1,"visible tied P1 did not get the initial windup");
        live1=0;
        repeat(65) @(negedge clk);
        if(hits1!=0 || hits2!=0) $fatal(1,"windup jumped to P2");
        sweep;
        repeat(65) @(negedge clk);
        if(hits1!=0 || hits2!=1) $fatal(1,"visible P2 did not get a separate strike");

        wait(sight_checks_done);
        $display("TB_ENEMY_AWARENESS: PASS"); $finish;
    end
    initial begin #10000000; $fatal(1,"awareness test timeout"); end
endmodule

module sight_checks(input wire clk, output reg done=0);
    reg reset=1, start=0;
    reg [255:0] walls=0;
    reg [7:0] from_tile=0, to_tile=0;
    wire ray_done, visible;
    integer dx, dy, x, y, wx, wy, seed=18341, n;
    zombie_sight dut(.clk(clk),.reset(reset),.start(start),.walls(walls),
        .from_tile(from_tile),.to_tile(to_tile),.done(ray_done),.visible(visible));

    // Every grid crossing for a delta of up to six divides this interval.
    // Sample the closed tile squares, including corner-only intersections.
    function reference_visible;
        input [7:0] origin, target, wall;
        integer sx, sy, ex, ey, wx, wy, t, px, py;
        begin
            sx=origin[3:0]; sy=origin[7:4]; ex=target[3:0]; ey=target[7:4];
            wx=wall[3:0]; wy=wall[7:4];
            reference_visible=ex-sx<=6 && sx-ex<=6 && ey-sy<=6 && sy-ey<=6;
            for(t=0;t<=120;t=t+1) begin
                px=120*sx+60+t*(ex-sx);
                py=120*sy+60+t*(ey-sy);
                if(px>=120*wx && px<=120*(wx+1) && py>=120*wy && py<=120*(wy+1))
                    reference_visible=0;
            end
        end
    endfunction
    task check(input [7:0] a, b, wall);
        integer clocks;
        begin
            from_tile=a; to_tile=b; walls=0; walls[wall]=1;
            start=1; @(negedge clk); start=0;
            for(clocks=0;!ray_done && clocks<32;clocks=clocks+1) @(negedge clk);
            if(!ray_done || visible!==reference_visible(a,b,wall))
                $fatal(1,"sight mismatch from %h to %h with blocker %h",a,b,wall);
        end
    endtask
    initial begin
        @(negedge clk); reset=0;
        check(8'h00,8'h00,8'hff);
        check(8'h00,8'h00,8'h00);
        check(8'hff,8'h99,8'hff);
        check(8'h00,8'h66,8'h01);
        check(8'h00,8'h66,8'h10);
        for(n=0;n<4;n=n+1) begin
            for(dx=0;dx<=6;dx=dx+1) for(dy=0;dy<=6;dy=dy+1) begin
                x=8+((n&1) ? -dx : dx);
                y=8+((n&2) ? -dy : dy);
                check(8'h88,{y[3:0],x[3:0]},8'hff);
                check({y[3:0],x[3:0]},8'h88,8'h88);
                wx=8+((n&1) ? -1 : 1)*($random(seed)&7);
                wy=8+((n&2) ? -1 : 1)*($random(seed)&7);
                check(8'h88,{y[3:0],x[3:0]},{wy[3:0],wx[3:0]});
            end
        end
        done=1;
    end
endmodule
