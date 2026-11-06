`timescale 1ns / 1ps
module tb_enemy_two_players;
    reg clk=0, clear=1, tick=0, req=0;
    reg live1=1, live2=1, fire1=0, fire2=0;
    reg [7:0] p1=8'h35, p2=8'h03, spawn_tile=0;
    reg [255:0] walls;
    wire ack, dead, hit, hit_id, hurt1, hurt2, ready1, ready2;
    wire [255:0] occupied;
    wire [7:0] active;
    integer hits=0, deaths=0, hurt_count1=0, hurt_count2=0;
    reg [1:0] hit_order=0;
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(hit) begin hits=hits+1; hit_order={hit_order[0],hit_id}; end
        if(dead) deaths=deaths+1;
        if(hurt1) hurt_count1=hurt_count1+1;
        if(hurt2) hurt_count2=hurt_count2+1;
    end
    enemy_manager #(.MOVE_SUBSTEPS(1),.TWO_PLAYERS(1),.INITIAL_HP(2),.ATTACK_COOLDOWN_CYCLES(64)) dut(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.spawn_req(req),.spawn_tile(spawn_tile),.debug_defeat(1'b0),
        .move_tick(tick),.spawn_busy(1'b0),.player_tile(p1),.player2_tile(p2),
        .player_active(live1),.player2_active(live2),
        .shot_fired(fire1),.shot_fired_p2(fire2),.aim(2'd0),.aim_p2(2'd2),
        .shot_ready(ready1),.shot_ready_p2(ready2),.shot_hit(hit),.shot_hit_player(hit_id),
        .player_hit(hurt1),.player_hit_p2(hurt2),.spawn_ack(ack),.enemy_defeated(dead),
        .occupied(occupied),.active(active),.read_id(3'd0));

    task spawn(input [7:0] location);
        begin
            spawn_tile=location; req=1; @(negedge clk);
            if(!ack) $fatal(1,"spawn rejected at %h",location);
            req=0; @(negedge clk);
        end
    endtask
    task sweep;
        begin
            @(negedge clk); // Let changed player inputs invalidate the old field.
            while(!dut.field_ready) @(negedge clk);
            tick=1; @(negedge clk); tick=0;
            repeat(50) @(negedge clk);
        end
    endtask

    initial begin
        // P1 is closer by coordinate distance but farther by corridor.
        walls={256{1'b1}};
        walls[8'h33]=0; walls[8'h23]=0; walls[8'h13]=0; walls[8'h03]=0;
        walls[8'h43]=0; walls[8'h53]=0; walls[8'h54]=0; walls[8'h55]=0;
        walls[8'h45]=0; walls[8'h35]=0;
        repeat(2) @(negedge clk); clear=0;
        spawn(8'h33); sweep;
        if(!occupied[8'h23]) $fatal(1,"did not chase nearest player by walkable distance");
        live2=0; sweep;
        if(!occupied[8'h33]) $fatal(1,"did not retarget after P2 disconnected");
        live1=0; sweep;
        if(!occupied[8'h33]) $fatal(1,"enemy moved with no active players");

        // Two simultaneous shots consume the same enemy's two HP in order.
        clear=1; @(negedge clk); clear=0;
        walls=0; p1=8'h21; p2=8'h25; live1=1; live2=1;
        spawn(8'h23);
        if(!ready1 || !ready2) $fatal(1,"shot inputs not ready");
        fire1=1; fire2=1; @(negedge clk); fire1=0; fire2=0;
        repeat(60) @(negedge clk);
        if(hits!=2 || hit_order!=2'b01 || deaths!=1 || occupied!=0 || active!=0)
            $fatal(1,"concurrent shots did not produce two ordered hits and one kill");

        // Stagger contact so P2 must be able to take a hit during P1's cooldown.
        clear=1; @(negedge clk); clear=0;
        p1=8'h41; p2=8'h45; live2=0;
        spawn(8'h42); spawn(8'h44);
        repeat(8) @(negedge clk);
        if(hurt_count1!=1 || hurt_count2!=0 || ready2)
            $fatal(1,"active or disconnected player contact was counted incorrectly");
        live2=1;
        repeat(8) @(negedge clk);
        if(hurt_count1!=1 || hurt_count2!=1)
            $fatal(1,"players did not have independent contact cooldowns");
        $display("TB_ENEMY_TWO_PLAYERS: PASS"); $finish;
    end
    initial begin #200000; $fatal(1,"two-player test timeout"); end
endmodule
