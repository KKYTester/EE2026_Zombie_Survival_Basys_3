`timescale 1ns / 1ps
module tb_enemy_circles;
    reg clk=0, reset=1, fire=0;
    reg [255:0] walls=0;
    reg [2:0] active=0;
    reg [47:0] xs=0, ys=0;
    reg [31:0] cx=6144, cy=51200; // map (1.5,3.5)
    reg [9:0] angle=256;
    wire busy, hit;
    wire [7:0] tile;
    integer hits=0;
    always #5 clk=~clk;
    always @(posedge clk) if(hit) hits=hits+1;
    enemy_combat #(.USE_CAMERA_RAY(1),.MAX_ENEMIES(3),.COORD_FRAC_BITS(12)) dut(
        .clk(clk),.reset(reset),.enabled(1'b1),.shot_fired(fire),
        .player_tile(8'h31),.aim(2'd0),.walls(walls),.occupied(256'd0),
        .camera_x(cx),.camera_y(cy),.camera_angle(angle),.active(active),
        .position_x(xs),.position_y(ys),.busy(busy),.hit_valid(hit),.hit_tile(tile));
    task shoot(input integer expected_hits, input [7:0] expected_tile);
        begin
            fire=1; @(negedge clk); fire=0;
            // Changing the camera after acceptance must not bend the ray.
            angle=angle+512;
            while(busy) @(negedge clk);
            if(hits!=expected_hits || (expected_hits!=0 && tile!=expected_tile))
                $fatal(1,"circle result hits=%0d tile=%h",hits,tile);
            angle=angle+512;
        end
    endtask
    initial begin
        repeat(2) @(negedge clk); reset=0;
        active=1; xs[0+:16]=18432; ys[0+:16]=15565; // 4.5,3.8: tile hit, circle miss
        shoot(0,0);
        ys[0+:16]=15360; // exact tangent, 3.75
        shoot(1,8'h34);
        ys[0+:16]=15361; // just outside radius
        shoot(1,8'h34);
        ys[0+:16]=14336; walls[8'h33]=1;
        shoot(1,8'h34); // wall blocks circle
        walls=0; active=3;
        xs[16+:16]=12288; ys[16+:16]=14336; // moving center at x=3.0, lower slot farther
        shoot(2,8'h33);
        active=1; xs[0+:16]=2048; // behind origin
        shoot(2,8'h33);
        xs[0+:16]=6144; ys[0+:16]=14336; // origin inside circle
        shoot(3,8'h31);
        active=1; cx=6144; cy=51200; angle=0;
        xs[0+:16]=6144; ys[0+:16]=6144; // zero X component
        shoot(4,8'h11);
        reset=1; @(negedge clk); reset=0;
        if(busy || hit) $fatal(1,"reset did not cancel shot");
        $display("TB_ENEMY_CIRCLES: PASS"); $finish;
    end
    initial begin #100000; $fatal(1,"circle timeout"); end
endmodule
