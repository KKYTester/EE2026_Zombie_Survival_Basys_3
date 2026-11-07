`timescale 1ns / 1ps
module tb_enemy_windup;
    localparam WINDUP=96, RECOVERY=12, COOLDOWN=128;
    reg clk=0,clear=1,tick=0,req=0,defeat=0,fire=0;
    reg live1=1,live2=0;
    reg [255:0] walls=0;
    reg [7:0] p1=8'h54,p2=8'h56,tile=0;
    reg [31:0] x1=32'h480,y1=32'h580,x2=32'h680,y2=32'h580;
    wire [1:0] warnings,active;
    wire [23:0] zx,zy;
    wire ack,hit1,hit2;
    integer hits1=0,hits2=0,i;
    reg [23:0] saved_x,saved_y;
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(clear) begin hits1<=0; hits2<=0; end
        else begin
            if(hit1) hits1<=hits1+1;
            if(hit2) hits2<=hits2+1;
        end
    end
    enemy_manager #(.MAX_ENEMIES(2),.TWO_PLAYERS(1),.USE_PLAYER_POSITIONS(1),
        .ATTACK_WINDUP_CYCLES(WINDUP),.ATTACK_RECOVERY_CYCLES(RECOVERY),
        .ATTACK_COOLDOWN_CYCLES(COOLDOWN),.INITIAL_HP(1)) dut(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.spawn_req(req),.spawn_tile(tile),.debug_defeat(defeat),
        .move_tick(tick),.spawn_busy(1'b0),.player_tile(p1),.player2_tile(p2),
        .player_pos_x(x1),.player_pos_y(y1),.player2_pos_x(x2),.player2_pos_y(y2),
        .player_active(live1),.player2_active(live2),
        .shot_fired(fire),.shot_fired_p2(1'b0),.aim(2'd0),.aim_p2(2'd0),
        .spawn_ack(ack),.player_hit(hit1),.player_hit_p2(hit2),
        .render_windup(warnings),.render_x(zx),.render_y(zy),.active(active),.read_id(1'b0));
    task step; begin @(negedge clk); end endtask
    task restart;
        begin
            clear=1; step;
            if(warnings!==0 || hit1 || hit2) $fatal(1,"reset leaked attack state");
            live1=1; live2=0; p1=8'h54; p2=8'h56;
            x1=32'h480; y1=32'h580; x2=32'h680; y2=32'h580;
            walls=0; clear=0; step;
        end
    endtask
    task spawn(input [7:0] address);
        begin
            tile=address; req=1;
            for(i=0;i<400 && !ack;i=i+1) step;
            if(!ack) $fatal(1,"spawn timeout at %h",address);
            req=0; step;
        end
    endtask
    task await_warning(input [1:0] mask);
        begin
            for(i=0;i<300 && warnings!==mask;i=i+1) step;
            if(warnings!==mask) $fatal(1,"warning timeout: expected %b, got %b",mask,warnings);
        end
    endtask
    initial begin
        restart;
        for(i=0;i<5000 && !dut.field_ready;i=i+1) step;
        if(!dut.field_ready) $fatal(1,"flow field timeout");
        spawn(8'h55); await_warning(2'b01);
        saved_x=zx; saved_y=zy;
        x1=32'h460; // Give the zombie a reason to move, while it is locked.
        tick=1; step; tick=0;
        for(i=0;i<WINDUP-3;i=i+1) begin
            step;
            if(hits1!=0 || warnings!==2'b01 || zx!==saved_x || zy!==saved_y)
                $fatal(1,"early hit, missing warning, or movement during windup");
            if(i==35) x1=32'h480;
        end
        repeat(20) step;
        if(hits1!=1 || hits2!=0 || warnings!=0) $fatal(1,"stationary target did not take exactly one hit");
        repeat(COOLDOWN-20) step;
        if(hits1!=1 || warnings!=0) $fatal(1,"attack bypassed player cooldown");

        restart; spawn(8'h55); await_warning(2'b01);
        repeat(WINDUP-3) step;
        x1=32'h460; // Still on tile 54, but now more than one tile away.
        repeat(32) step;
        if(hits1!=0 || warnings!=0) $fatal(1,"same-tile dodge did not cancel impact");

        restart; spawn(8'h55); await_warning(2'b01);
        live2=1; // The same zombie is also adjacent to P2.
        repeat(7) step; live1=0;
        repeat(WINDUP-12) step;
        if(hits1!=0 || hits2!=0) $fatal(1,"attack survived target loss or jumped to P2");
        await_warning(2'b01);
        repeat(WINDUP+18) step;
        if(hits1!=0 || hits2!=1) $fatal(1,"zombie did not begin a separate attack on P2");

        restart; spawn(8'h55); await_warning(2'b01);
        fire=1; step; fire=0; // P1 fires east into the original attacker.
        for(i=0;i<WINDUP-10 && active!=0;i=i+1) step;
        if(active!=0 || warnings!=0) $fatal(1,"lethal shot did not clear the warning");
        spawn(8'h5b); // Reuse the same slot during the original windup window.
        repeat(WINDUP+18) step;
        if(hits1!=0 || hits2!=0 || warnings!=0) $fatal(1,"slot reuse inherited the old strike");

        restart; spawn(8'h55); await_warning(2'b01);
        for(i=0;i<WINDUP+16 &&
            !(dut.g_attack[0].g_windup.phase==2 && dut.g_attack[0].g_windup.verify_hit);
            i=i+1) step;
        if(i==WINDUP+16) $fatal(1,"could not reach the impact edge");
        defeat=1; step; defeat=0;
        repeat(3) step;
        if(active!=0 || warnings!=0 || hits1!=0) $fatal(1,"removal on the impact edge lost priority");

        // Both scanners request the same zombie on the same cycle.
        clear=1; step;
        p2=p1; x2=x1; y2=y1; live2=1;
        clear=0; step;
        spawn(8'h55); await_warning(2'b01);
        repeat(WINDUP+18) step;
        if(hits1!=1 || hits2!=0) $fatal(1,"simultaneous claims produced two strikes from one zombie");

        restart; p2=8'h5b; x2=32'hb80; live2=1;
        spawn(8'h55); spawn(8'h5a); await_warning(2'b11);
        repeat(WINDUP+18) step;
        if(hits1!=1 || hits2!=1) $fatal(1,"independent attackers did not each land one hit");

        restart; p1=8'h22; x1=512; y1=512; walls[8'h12]=1;
        spawn(8'h11);
        repeat(WINDUP+30) step;
        if(hits1!=0 || warnings!=0) $fatal(1,"windup went through a blocked corner");

        restart; spawn(8'h55); await_warning(2'b01);
        repeat(WINDUP) step;
        clear=1; repeat(2) step;
        if(warnings!=0 || active!=0 || hit1 || hit2) $fatal(1,"clear during a warning leaked state");
        clear=0;
        repeat(WINDUP+18) step;
        if(hits1!=0 || hits2!=0) $fatal(1,"strike survived reset");
        $display("TB_ENEMY_WINDUP: PASS");
        $finish;
    end
    initial begin #200000; $fatal(1,"windup test timeout"); end
endmodule
