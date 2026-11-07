`timescale 1ns / 1ps
module enemy_renderer_integration_tb;
    reg clk=0, reset=1;
    reg [255:0] walls;
    reg [31:0] angle=128;
    wire [15:0] wall_pixel, pixel;
    wire [9:0] depth;
    wire prepare, bank, valid, sprites_done;
    reg [95:0] xs=0, ys=0;
    reg old_bank;
    always #5 clk=~clk;

    Map_Renderer #(.USE_RUNTIME_MAP(1),.USE_PIXEL_COORDS(1),.USE_ENEMY_OVERLAY(1)) world(
        .clk(clk),.reset(reset),.map_bits(walls),
        .x_coord(32'd22528),.y_coord(32'd43008),.theta(angle),
        .game_tick(),.display_clk(clk),.frame_begin(1'b1),
        .pixel_index(13'd0),.pixel_x(7'd48),.pixel_y(6'd32),
        .pixel_data(wall_pixel),.column_depth(depth),.overlay_ready(sprites_done),
        .scene_start(prepare),.display_bank(bank),.scene_valid(valid));
    zombie_renderer #(.USE_CAMERA_POSE(1),.FOCAL_X(83),.FOCAL_Y(64)) sprites(
        .clk(clk),.reset(reset),.prepare(prepare),.display_bank(bank),.scene_valid(valid),
        .camera_x(12'd1408),.camera_y(12'd1408),.camera_angle(angle[9:0]),
        .facing(2'd0),.active(8'd1),.zombie_x(xs),.zombie_y(ys),
        .hp(16'hFFFF),.dying(8'd0),.fall(32'd0),
        .pixel_x(7'd48),.pixel_y(6'd32),.wall_depth({depth,3'b0}),
        .background(wall_pixel),.done(sprites_done),.pixel(pixel));

    task next_scan;
        begin
            wait(world.state==world.IDLE);
            @(negedge clk); old_bank=bank; force world.game_tick=1;
            @(negedge clk); release world.game_tick;
            wait(bank!=old_bank);
            repeat(36) @(negedge clk);
        end
    endtask
    initial begin
        walls=0;
        for(integer y=0;y<16;y++) for(integer x=0;x<16;x++)
            if(x==0 || x==15 || y==0 || y==15) walls[y*16+x]=1;
        xs[0+:12]=1920; ys[0+:12]=896; // Two cells east and north of the camera.
        repeat(3) @(negedge clk); reset=0;
        wait(valid); repeat(36) @(negedge clk);
        if(pixel!==16'h8816) $fatal(1,"northeast sprite not projected at screen center");
        walls[11*16+6]=1; // Wall between the camera and zombie.
        next_scan;
        if(pixel!==wall_pixel) $fatal(1,"sprite not hidden by main renderer depth");
        walls[11*16+6]=0;
        angle=512; // South-facing camera leaves the zombie behind it.
        next_scan;
        if(pixel!==wall_pixel) $fatal(1,"behind-camera sprite remained visible");
        $display("PASS: camera-angle zombie projection, shared column publication and real wall occlusion");
        $finish;
    end
    initial begin #3000000; $fatal(1,"enemy renderer integration timeout"); end
endmodule
