`timescale 1ns / 1ps
// Exercise the real wave controller handshake through a complete short session.
module tb_enemy_waves;
    reg clk=0, rst=1, start=0, playing=0, defeat=0;
    reg fire=0;
    reg [7:0] player_tile=8'h11;
    reg [255:0] map_bits;
    wire req,ack,dead,clear_wave,won,spawn_busy;
    wire [7:0] tile,active;
    wire [255:0] occupied;
    wire [6:0] wave,remaining;
    wire [5:0] alive;
    wire shot_fired, shot_hit, player_hit;
    wire [2:0] ammo;
    wire [1:0] weapon_state, health;
    integer i,cycles,spawns=0,kills=0,moves=0,live_count;
    integer simultaneous=0, combat_hits=0, kills_before_restart;
    always #5 clk=~clk;
    wave_controller #(.SPAWN_SHIFT(2),.CLEAR_SHIFT(2),.MIN_DIST(2),.WIN_WAVE(2)) waves(
        .clk(clk),.rst(rst),.play_start(start),.playing(playing),.map_bits(map_bits),
        .occupied(occupied),.player_tile(player_tile),.spawn_ack(ack),.enemy_defeated(dead),
        .wave(wave),.spawn_req(req),.spawn_tile(tile),.spawn_busy(spawn_busy),
        .alive(alive),.remaining(remaining),
        .wave_clear(clear_wave),.game_won(won));
    enemy_manager #(.MOVE_SUBSTEPS(1)) enemies(.clk(clk),.rst(rst),.clear(start || !playing),
        .playing(playing),.map_ready(1'b1),.map_bits(map_bits),.spawn_req(req),
        .spawn_tile(tile),.debug_defeat(defeat),.spawn_ack(ack),.enemy_defeated(dead),
        .move_tick(1'b1),.spawn_busy(spawn_busy),.player_tile(player_tile),
        .shot_fired(shot_fired),.aim(2'd0),.shot_hit(shot_hit),.player_hit(player_hit),
        .player_active(1'b1),.player2_active(1'b0),.player2_tile(8'd0),
        .shot_fired_p2(1'b0),.aim_p2(2'd0),
        .occupied(occupied),.active(active),.read_id(3'd0),.read_active(),
        .read_x(),.read_y(),.read_hp(),.read_type(),.read_state(),.read_cooldown());
    weapon_ctrl #(.FLASH_SHIFT(3),.RECOIL_SHIFT(6),.RELOAD_SHIFT(5)) weapon(
        .clk(clk),.rst(rst),.playing(playing),.fire(fire),.reload(1'b0),
        .shot_fired(shot_fired),.ammo(ammo),.state(weapon_state),
        .flash(),.recoil(),.reloading(),.drop(),.reload_phase());
    player_health hearts(.clk(clk),.rst(rst),.play_start(start),.playing(playing),
        .hit(player_hit),.health(health),.damage());
    always @(posedge clk) if(!rst && playing && !start) begin
        if(ack) spawns=spawns+1;
        if(dead) kills=kills+1;
        if(ack && dead) simultaneous=simultaneous+1;
        if(shot_hit) combat_hits=combat_hits+1;
        if(enemies.apply_move) moves=moves+1;
    end
    initial begin
        map_bits=0;
        for(i=0;i<256;i=i+1)
            if(i%16==0 || i%16==15 || i/16==0 || i/16==15) map_bits[i]=1;
        repeat(3) @(negedge clk); rst=0; playing=1; start=1;
        @(negedge clk); start=0;
        cycles=0;
        while(!won && cycles<10000) begin
            // Interleave kills with spawning, leaving time for registered events.
            defeat=(simultaneous==0 && req && !ack && alive!=0) ||
                   (enemies.field_ready && cycles%41==0);
            @(negedge clk); cycles=cycles+1;
            live_count=0;
            for(i=0;i<8;i=i+1) live_count=live_count+active[i];
            if(live_count != alive + (ack ? 1 : 0) - (dead ? 1 : 0))
                $fatal(1,"population mismatch at cycle %0d",cycles);
            if((occupied & map_bits)!=0) $fatal(1,"enemy spawned in wall");
        end
        defeat=0;
        if(!won || wave!=2 || remaining!=0 || active!=0 || spawns!=8 || kills!=8)
            $fatal(1,"wave completion: wave=%0d spawns=%0d kills=%0d",wave,spawns,kills);
        if(moves==0) $fatal(1,"no movement during wave integration test");
        if(simultaneous==0) $fatal(1,"never exercised a spawn and defeat on the same edge");
        playing=0; repeat(3) @(negedge clk);

        // A one-tile corridor makes every spawned zombie reachable by the weapon.
        map_bits={256{1'b1}};
        for(i=17;i<=30;i=i+1) map_bits[i]=0;
        playing=1; start=1; @(negedge clk); start=0;
        if(wave!=1 || remaining!=3 || alive!=0 || active!=0)
            $fatal(1,"restart retained old state");
        while(wave==1) begin
            fire=active!=0 && weapon_state==0 && ammo!=0;
            @(negedge clk);
        end
        fire=0;
        if(wave!=2 || combat_hits!=9 || kills!=11 || remaining!=5)
            $fatal(1,"weapon kills did not advance the wave exactly once");

        // Reset with a live target, a running cooldown and damage queued.
        while(health==3 || active==0) @(negedge clk);
        while(weapon_state!=0 || ammo==0) @(negedge clk);
        fire=1; @(negedge clk); fire=0;
        while(!shot_hit) @(negedge clk);
        kills_before_restart=kills;
        rst=1; playing=0; @(negedge clk);
        if(active!=0 || occupied!=0 || shot_fired || shot_hit || player_hit || dead ||
           req || ack || enemies.g_attack[0].attack_timer!=0 || health!=3 || ammo!=6)
            $fatal(1,"reset left wave or combat state active");
        rst=0; playing=1; start=1; @(negedge clk); start=0;
        if(wave!=1 || remaining!=3 || alive!=0 || active!=0)
            $fatal(1,"mid-wave reset did not restart at wave one");
        while(!ack) begin
            @(negedge clk);
            if(health!=3 || player_hit || dead || kills!=kills_before_restart)
                $fatal(1,"combat event leaked into the new session");
        end
        if(active==0 || occupied==0) $fatal(1,"fresh spawn missing after reset");
        $display("TB_ENEMY_WAVES: PASS"); $finish;
    end
    initial begin
        #200000;
        $fatal(1,"timeout: wave=%0d active=%h health=%0d shots hit=%0d kills=%0d",
               wave,active,health,combat_hits,kills);
    end
endmodule
