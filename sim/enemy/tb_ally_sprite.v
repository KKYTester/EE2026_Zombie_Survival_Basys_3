`timescale 1ns / 1ps
// zombie_renderer with SLOTS=9, HAS_ALLY=1: the partner (slot 8) and a zombie
// (slot 0) placed in front of a north-east facing camera must both draw, the
// partner in its blue shirt colour and the zombie in its purple one.
module tb_ally_sprite;
    reg clk=0; always #5 clk=~clk;
    reg reset=1, prepare=0, bank=0, scene_valid=0;
    reg [8:0] active=0;
    reg [8:0] dying=0;
    reg [35:0] fall=0;
    reg [107:0] zx=0, zy=0;
    reg [6:0] px=0; reg [5:0] py=0;
    wire done; wire [15:0] pixel;
    zombie_renderer #(.USE_CAMERA_POSE(1),.FOCAL_X(83),.FOCAL_Y(64),.SLOTS(9),.HAS_ALLY(1)) dut(
        .clk(clk),.reset(reset),.prepare(prepare),.display_bank(bank),.scene_valid(scene_valid),
        .camera_x(12'h180),.camera_y(12'h180),.facing(2'd0),.camera_angle(10'd0),
        .active(active),.zombie_x(zx),.zombie_y(zy),
        .hp({18{1'b1}}),.dying(dying),.fall(fall),.winding_up(9'h100),
        .pixel_x(px),.pixel_y(py),
        .wall_depth(13'd4096),.background(16'h0000),.done(done),.pixel(pixel));
    integer errors=0;
    task sample(input [6:0] x, input [5:0] y, output [15:0] c); begin
        px=x; py=y; repeat(70) @(posedge clk); c=pixel;   // 9 slots x 6 clocks + margin
    end endtask
    reg [15:0] c;
    integer x, y, ally_px, zombie_px, downed_px=0;
    initial begin
        repeat(5) @(posedge clk); reset=0;
        // Camera at (1.5,1.5) tiles facing north (angle 0, y down => smaller y ahead).
        // Partner 1 tile ahead and 0.5 left, zombie 1 tile ahead and 0.5 right.
        zx[8*12 +: 12]=12'h100; zy[8*12 +: 12]=12'h080;   // partner
        zx[0 +: 12]=12'h200;    zy[0 +: 12]=12'h080;      // zombie
        active=9'b1_0000_0001;
        @(posedge clk) prepare=1; @(posedge clk) prepare=0;
        wait(done); @(posedge clk);
        bank=1; scene_valid=1;    // show the bank just written (write_bank = !0)
        ally_px=0; zombie_px=0;
        for(x=0;x<96;x=x+1) begin
            sample(x, 6'd32, c);
            if(c==16'h1A9F) ally_px=ally_px+1;
            if(c==16'h8816) zombie_px=zombie_px+1;
        end
        $display("row 32: partner shirt pixels=%0d, zombie body pixels=%0d", ally_px, zombie_px);
        if(ally_px==0) begin $display("FAIL: partner not drawn"); errors=errors+1; end
        if(zombie_px==0) begin $display("FAIL: zombie not drawn"); errors=errors+1; end
        dying[8]=1; fall[35:32]=15;
        @(negedge clk); prepare=1; @(negedge clk); prepare=0;
        wait(done); @(negedge clk); bank=0;
        for(y=48;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            sample(x,y,c);
            if(c==16'hB5A8 || c==16'h8A45 || c==16'h5A23) downed_px=downed_px+1;
        end
        if(downed_px==0) $fatal(1,"Downed ally was not drawn lying on the floor");
        if(errors==0) $display("TB_ALLY_SPRITE: PASS"); else $display("FAILED");
        $finish;
    end
endmodule
