`timescale 1ns / 1ps
module tb_camera_enemy;
    reg clk=0, clear=1, req=0, fire=0;
    reg [255:0] walls=0;
    reg [7:0] spawn_tile=8'h37;
    reg [9:0] angle=0;
    wire ack, hit, dead;
    wire [7:0] hp, active;
    integer hits=0, kills=0;
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(hit) hits=hits+1;
        if(dead) kills=kills+1;
    end
    enemy_manager #(.USE_CAMERA_RAY(1)) enemies(
        .clk(clk),.rst(1'b0),.clear(clear),.playing(1'b1),.map_ready(1'b1),
        .map_bits(walls),.spawn_req(req),.spawn_tile(spawn_tile),.debug_defeat(1'b0),
        .move_tick(1'b0),.spawn_busy(1'b0),.player_tile(8'h55),
        .shot_fired(fire),.aim(2'd0),.camera_x(32'd22528),.camera_y(32'd43008),
        .camera_angle(angle),.shot_hit(hit),.enemy_defeated(dead),.spawn_ack(ack),
        .player_active(1'b1),.player2_active(1'b0),.shot_fired_p2(1'b0),
        .player2_tile(8'd0),.aim_p2(2'd0),.read_id(3'd0),.read_hp(hp),.active(active));
    task shoot(input [9:0] heading);
        begin
            angle=heading; fire=1; @(negedge clk); fire=0;
            angle=heading+10'd256; // Pose must be captured with the shot.
            repeat(800) @(negedge clk);
        end
    endtask
    initial begin
        repeat(2) @(negedge clk); clear=0;
        req=1; @(negedge clk);
        if(!ack) $fatal(1,"camera test spawn");
        req=0; @(negedge clk);
        shoot(0);
        if(hits!=0 || hp!=3) $fatal(1,"north shot hit a northeast enemy");
        walls[8'h46]=1;
        shoot(128);
        if(hits!=0 || hp!=3) $fatal(1,"diagonal shot went through a wall");
        walls[8'h46]=0;
        shoot(128);
        if(hits!=1 || hp!=2) $fatal(1,"diagonal camera shot missed");
        shoot(128); shoot(128);
        if(hits!=3 || kills!=1 || active!=0) $fatal(1,"camera kill accounting");
        $display("TB_CAMERA_ENEMY: PASS"); $finish;
    end
    initial begin #100000; $fatal(1,"camera combat timeout"); end
endmodule
