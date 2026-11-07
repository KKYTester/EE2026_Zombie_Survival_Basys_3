`timescale 1ns / 1ps
module tb_zombie_renderer;
    reg clk=0, reset=1, prepare=0, bank=0, scene_valid=0;
    reg [1:0] facing=0;
    reg [7:0] active=0;
    reg [95:0] xs=0, ys=0;
    reg [6:0] x=0;
    reg [5:0] y=0;
    reg occluder=0;
    wire [12:0] depth = (occluder && x<48) ? 13'd256 : 13'd4096;
    wire done, wall_done;
    wire [15:0] pixel;
    reg [255:0] map_bits=0;
    wire [12:0] map_depth;
    wire [5:0] wall_top;
    always #5 clk=~clk;

    zombie_renderer sprites(.clk(clk),.reset(reset),.prepare(prepare),
        .display_bank(bank),.scene_valid(scene_valid),.camera_x(12'd384),
        .camera_y(12'd384),.facing(facing),.active(active),.zombie_x(xs),.zombie_y(ys),
        .hp({16{1'b1}}),.dying(8'd0),.fall(32'd0),
        .pixel_x(x),.pixel_y(y),.wall_depth(depth),.background(16'h1234),
        .done(done),.pixel(pixel));
    demo_wall_view walls(.clk(clk),.reset(reset),.prepare(prepare),.display_bank(bank),
        .map_bits(map_bits),.camera_tile(8'h11),.facing(facing),.pixel_x(x),
        .done(wall_done),.wall_depth(map_depth),.wall_top(wall_top));

    task prepare_scene;
        begin
            prepare=1; @(negedge clk); prepare=0;
            while(!done || !wall_done) @(negedge clk);
        end
    endtask
    task expect_pixel(input [6:0] px, input [5:0] py, input [15:0] expected);
        begin
            x=px; y=py;
            repeat(56) @(negedge clk);   // 8 slots x 6 clocks + margin
            if(pixel!==expected)
                $fatal(1,"pixel (%0d,%0d): got %h expected %h",x,y,pixel,expected);
        end
    endtask
    initial begin
        repeat(2) @(negedge clk); reset=0;
        map_bits[8'h13]=1;
        map_bits[8'h41]=1;
        active=3;
        xs[0 +:12]=1408; ys[0 +:12]=384;  // Farther sprite in the first slot.
        xs[12+:12]=896;  ys[12+:12]=384;
        prepare_scene; bank=1; scene_valid=1;
        expect_pixel(48,26,16'h8816);      // Near torso covers far head.
        if(map_depth!=384 || wall_top!=11) $fatal(1,"incorrect east wall projection");
        expect_pixel(54,32,16'h8816);      // Near sprite is wider.
        expect_pixel(48,44,16'h1234);      // Transparent gap between legs.
        occluder=1;
        expect_pixel(47,32,16'h1234);
        expect_pixel(48,32,16'h8816);      // Occlusion is per column.
        occluder=0;

        active=1;
        prepare_scene;
        expect_pixel(49,26,16'h8816);      // The new bank is still hidden.
        bank=0;
        expect_pixel(48,26,16'h57c5);      // Far head is now visible.
        expect_pixel(54,32,16'h1234);      // Outside the far sprite.

        xs[0+:12]=128;
        prepare_scene; bank=1;
        expect_pixel(48,32,16'h1234);      // Behind the camera.

        facing=1; xs[0+:12]=384; ys[0+:12]=896;
        prepare_scene; bank=0;
        expect_pixel(48,32,16'h8816);
        if(map_depth!=640 || wall_top!=20) $fatal(1,"incorrect south wall projection");
        $display("TB_ZOMBIE_RENDERER: PASS"); $finish;
    end
    initial begin #3_000_000; $fatal(1,"renderer timeout"); end
endmodule
