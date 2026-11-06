`timescale 1ns / 1ps
module tb_enemy_smooth;
    reg clk=0, clear=1, tick=0, req=0, defeat=0, fire=0;
    reg [7:0] player_tile=8'h13, spawn_tile=8'h11;
    reg [31:0] player_x=896, player_y=384;
    wire [255:0] occupied, spawn_occupied;
    wire [7:0] active, hp;
    wire [95:0] xs, ys;
    wire hit, dead, ack;
    wire [15:0] dot_pixel;
    zombie_overlay #(.USE_FRACTIONAL_POSITIONS(1)) dots(
        .px(7'd37),.py(6'd5),.minimap_mode(1'b1),.zombies(occupied),
        .active(active),.position_x(xs),.position_y(ys),
        .pixel_in(16'd0),.pixel_out(dot_pixel));
    integer damage=0, kills=0;
    reg [255:0] expected;
    integer i;
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(hit) damage=damage+1;
        if(dead) kills=kills+1;
        #1;
        expected=0;
        for(i=0;i<8;i=i+1) if(active[i]) begin
            if(expected[{ys[12*i+8+:4],xs[12*i+8+:4]}])
                $fatal(1,"two live zombies share a tile");
            expected[{ys[12*i+8+:4],xs[12*i+8+:4]}]=1;
        end
        if(!clear && occupied!==expected) $fatal(1,"physical occupancy differs from positions");
    end
    enemy_manager #(.USE_PLAYER_POSITIONS(1),.ATTACK_COOLDOWN_CYCLES(32)) enemies(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(256'd0),.spawn_req(req),.spawn_tile(spawn_tile),.debug_defeat(defeat),
        .move_tick(tick),.spawn_busy(1'b0),.player_tile(player_tile),
        .player_pos_x(player_x),.player_pos_y(player_y),.player2_pos_x(32'd0),.player2_pos_y(32'd0),
        .shot_fired(fire),.aim(2'd2),.shot_hit(),.player_hit(hit),
        .player_active(1'b1),.player2_active(1'b0),.player2_tile(8'd0),
        .shot_fired_p2(1'b0),.aim_p2(2'd0),.spawn_ack(ack),.enemy_defeated(dead),
        .occupied(occupied),.spawn_occupied(spawn_occupied),.active(active),
        .render_x(xs),.render_y(ys),.read_id(3'd0),.read_hp(hp));
    task step; begin @(negedge clk); end endtask
    task spawn(input [7:0] tile);
        begin
            spawn_tile=tile; req=1; step;
            if(!ack) $fatal(1,"spawn rejected");
            req=0; step;
        end
    endtask
    task sweep;
        begin
            while(!enemies.field_ready) step;
            tick=1; step; tick=0;
            repeat(70) step;
        end
    endtask
    task shoot;
        begin fire=1; step; fire=0; repeat(500) step; end
    endtask
    task direction_trip(input [7:0] goal, input [31:0] target_x, target_y,
                        input [11:0] expected_x, expected_y);
        begin
            clear=1; step; clear=0;
            player_tile=goal; player_x=target_x; player_y=target_y;
            spawn(8'h55);
            repeat(32) sweep;
            if(xs[0+:12]!=expected_x || ys[0+:12]!=expected_y ||
               spawn_occupied!=occupied || enemies.moving!=0)
                $fatal(1,"fractional direction or tile-boundary error for goal %h",goal);
        end
    endtask
    initial begin
        repeat(2) step; clear=0; spawn(8'h11);
        if(dot_pixel!=16'hf800) $fatal(1,"initial fractional minimap dot");
        sweep;
        if(xs[0+:12]!=392 || damage!=0 || !occupied[8'h11] ||
           !spawn_occupied[8'h12])
            $fatal(1,"first update must be 1/32 tile with destination reserved");
        repeat(7) sweep;
        if(dot_pixel!=0) $fatal(1,"minimap dot did not move by one pixel");
        repeat(8) sweep;
        if(xs[0+:12]!=512 || damage!=0 || occupied[8'h11] || !occupied[8'h12] ||
           !spawn_occupied[8'h11])
            $fatal(1,"midpoint occupancy, source reservation or contact range");
        // The old source is reserved for clearance but must not be a shootable enemy.
        spawn_tile=8'h11; req=1; step;
        if(ack) $fatal(1,"spawn accepted into a reserved source");
        req=0; step;
        shoot;
        if(hp!=2 || xs[0+:12]!=512) $fatal(1,"shot did not hit the actual moving zombie");
        shoot; shoot;
        if(active!=0 || occupied!=0 || spawn_occupied!=0 || kills!=1)
            $fatal(1,"death did not release the movement reservations");
        spawn(8'h11);
        repeat(32) sweep;
        if(xs[0+:12]!=640 || enemies.moving!=0 || spawn_occupied!=occupied || damage==0)
            $fatal(1,"arrival, slot reuse or actual-distance contact");

        clear=1; step; clear=0; player_tile=8'h15; player_x=1408; damage=0;
        spawn(8'h11); spawn(8'h12);
        repeat(16) sweep;
        if(xs[0+:12]!=384 || xs[12+:12]!=768 || !spawn_occupied[8'h12])
            $fatal(1,"trailing zombie entered a reserved source");
        repeat(17) sweep;
        if(xs[0+:12]!=392 || xs[12+:12]!=904)
            $fatal(1,"corridor queue did not continue after arrival");
        // A player at the far edge of its tile still has to be reachable.
        clear=1; step; clear=0; player_tile=8'h13; player_x=1000;
        spawn(8'h12);
        repeat(14) sweep;
        if(xs[0+:12]!=744 || damage==0)
            $fatal(1,"zombie did not approach the player's fractional position");
        repeat(4) sweep;
        if(xs[0+:12]!=744) $fatal(1,"zombie crossed its contact distance");
        clear=1; step; clear=0;
        if(spawn_occupied!=0 || active!=0 || enemies.moving!=0)
            $fatal(1,"reset retained a movement reservation");
        direction_trip(8'h52,640,1408,1152,1408);
        direction_trip(8'h25,1408,640,1408,1152);
        direction_trip(8'h85,1408,2176,1408,1664);
        $display("TB_ENEMY_SMOOTH: PASS"); $finish;
    end
    initial begin #700000; $fatal(1,"smooth movement timeout"); end
endmodule
