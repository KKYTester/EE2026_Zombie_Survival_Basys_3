`timescale 1ns / 1ps
module tb_enemy_wander;
    localparam IDLE=0, CHASE=1, INVESTIGATE=2, SEARCH=3;
    reg clk=0, clear=1, tick=0, request=0, fire=0, live=1;
    reg [7:0] p1=8'hee, spawn_tile=0;
    reg [15:0] seed=16'hbeef;
    reg [255:0] walls;
    wire [255:0] occupied, footprint;
    wire [23:0] x, y;
    wire [1:0] state;
    wire ack;
    integer i, j, elapsed, explored0, explored1;
    reg [11:0] old_x;
    reg [7:0] shot_tile;
    wire [7:0] tile0={y[11:8],x[11:8]}, tile1={y[23:20],x[23:20]};
    reg [255:0] visited0, visited1;
    always #5 clk=~clk;

    enemy_manager #(.MAX_ENEMIES(2),.TWO_PLAYERS(1),.USE_AWARENESS(1),.USE_WANDER(1),
        .ATTACK_WINDUP_CYCLES(40)) dut(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.wander_seed(seed),.spawn_req(request),.spawn_tile(spawn_tile),
        .debug_defeat(1'b0),.move_tick(tick),.spawn_busy(1'b0),
        .player_tile(p1),.player2_tile(8'd0),.player_active(live),.player2_active(1'b0),
        .shot_fired(fire),.shot_fired_p2(1'b0),.aim(2'd1),.aim_p2(2'd0),
        .spawn_ack(ack),.occupied(occupied),.spawn_occupied(footprint),
        .render_x(x),.render_y(y),.read_id(1'b0),.read_state(state));

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
    task corridor;
        begin
            walls={256{1'b1}};
            for(j=1;j<=8;j=j+1) walls[8'h40+j]=0;
            walls[8'h51]=0; walls[8'h56]=0; walls[8'h66]=0; walls[8'hee]=0;
        end
    endtask

    initial begin
        walls={256{1'b1}};
        walls[8'h00]=0; walls[8'hff]=0; walls[8'hf0]=0; walls[8'hee]=0;
        seed=0; restart; spawn(8'h00);
        repeat(10) sweep;
        if(tile0!=8'h00 || footprint!=occupied) $fatal(1,"trapped zombie wrapped around a map edge");

        walls[8'h01]=0;
        restart; spawn(8'h00); spawn(8'h01);
        repeat(5) sweep;
        if(tile0!=8'h00 || tile1!=8'h01 || footprint!=occupied)
            $fatal(1,"adjacent zombies swapped through each other");

        restart; spawn(8'h00); sweep;
        if(x[11:0]<=12'h080) $fatal(1,"roaming did not find the only legal exit");
        live=0; repeat(35) sweep;
        if(footprint!=occupied || state!=IDLE) $fatal(1,"ended round left a roaming reservation");
        old_x=x[11:0]; repeat(10) sweep;
        if(x[11:0]!=old_x) $fatal(1,"zombie roamed with no living players");

        walls={256{1'b1}}; walls[8'hee]=0;
        for(i=1;i<=7;i=i+1) for(j=1;j<=7;j=j+1) walls[{i[3:0],j[3:0]}]=0;
        seed=16'hbeef; restart; spawn(8'h22); spawn(8'h66);
        visited0=0; visited1=0; explored0=0; explored1=0;
        repeat(600) begin
            sweep;
            if(tile0==tile1 || !occupied[tile0] || !occupied[tile1] || state!=IDLE)
                $fatal(1,"wandering zombies collided or stopped scanning");
            if(!visited0[tile0]) explored0=explored0+1;
            if(!visited1[tile1]) explored1=explored1+1;
            visited0[tile0]=1; visited1[tile1]=1;
        end
        if(explored0<5 || explored1<5 || visited0==visited1)
            $fatal(1,"zombies did not explore independently");

        corridor; restart; spawn(8'h44); repeat(3) sweep;
        old_x=x[11:0];
        if(old_x==12'h480) $fatal(1,"zombie did not start roaming");
        p1=old_x>12'h480 ? 8'h41 : 8'h48;
        sweep;
        if(state!=CHASE || ((p1==8'h41) ? x[11:0]>=old_x : x[11:0]<=old_x))
            $fatal(1,"sight did not interrupt and reverse roaming");

        restart; spawn(8'h44); repeat(3) sweep;
        old_x=x[11:0];
        shot_tile=old_x>12'h480 ? 8'h51 : 8'h66;
        p1=shot_tile; fire=1; @(negedge clk); fire=0; p1=8'hee;
        while(dut.combat_locked) @(negedge clk);
        sweep;
        if(state!=INVESTIGATE || !dut.memory_is_sound[0] || dut.investigate_tile[0]!=shot_tile ||
           ((shot_tile==8'h51) ? x[11:0]>=old_x : x[11:0]<=old_x))
            $fatal(1,"hearing did not interrupt roaming");
        for(i=0;i<220 && state!=SEARCH;i=i+1) sweep;
        if(state!=SEARCH || tile0!=shot_tile || footprint!=occupied)
            $fatal(1,"zombie wandered before reaching the investigation tile");
        repeat(23) sweep;
        if(state!=SEARCH || footprint!=occupied) $fatal(1,"zombie wandered during its search");
        repeat(10) sweep;
        if(state!=IDLE || footprint==occupied) $fatal(1,"roaming did not resume after search");

        $display("TB_ENEMY_WANDER: PASS"); $finish;
    end
    initial begin #15000000; $fatal(1,"wander test timeout"); end
endmodule
