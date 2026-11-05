`timescale 1ns / 1ps
module map_renderer_tb;
    reg clk=0, display_clk=0;
    always #5 clk=~clk;
    always #80 display_clk=~display_clk;
    reg reset=1, frame_begin=0;
    reg [12:0] pixel_index=0;
    wire [15:0] pixel_data;
    wire [9:0] depth;
    reg [31:0] x_coord=32'd34816, y_coord=32'd34816, theta=32'd128;
    Map_Renderer #(.CLK_HZ(2400000)) dut (.clk(clk), .reset(reset), .display_clk(display_clk),
        .frame_begin(frame_begin), .pixel_index(pixel_index), .pixel_data(pixel_data), .column_depth(depth),
        .x_coord(x_coord), .y_coord(y_coord), .theta(theta), .game_tick());
    reg [16:0] expected0[0:95], expected1[0:95], expected2[0:95];
    integer p, c, row, h, top, fd, bank;
    reg [16:0] expected;
    reg [15:0] expected_color;
    reg [7:0] r,g,b;
    function [15:0] shaded_wall(input integer camera_depth);
        integer fade, grey;
        begin
            fade=camera_depth/64;
            if (fade>7) fade=7;
            grey=23-fade;
            shaded_wall=(grey<<11) | ((2*grey+1)<<5) | grey;
        end
    endfunction
    task display_frame_start;
        begin
            @(negedge display_clk); frame_begin=1;
            @(negedge display_clk); frame_begin=0;
            #1;
        end
    endtask
    task check_frame(input integer which);
        begin
            for (p=0;p<6144;p=p+1) begin
                pixel_index=p; #1;
                c=p%96; row=p/96;
                expected=which==0 ? expected0[c] : which==1 ? expected1[c] : expected2[c];
                h=expected[6:0]; top=(64-h)/2;
                if (which==2 && (h!=18 || depth<112 || depth>113))
                    $fatal(1,"Flat wall curved at column %0d",c);
                expected_color=row<top ? 16'h18e7 : row<top+h ? shaded_wall(expected[16:7]) : 16'h3184;
                if (pixel_data !== expected_color || depth !== expected[16:7])
                    $fatal(1,"Frame %0d pixel %0d got %h depth %0d expected %h depth %0d",
                        which,p,pixel_data,depth,expected_color,expected[16:7]);
                if (which==0 && fd!=0) begin
                    r={pixel_data[15:11],pixel_data[15:13]};
                    g={pixel_data[10:5],pixel_data[10:9]};
                    b={pixel_data[4:0],pixel_data[4:2]};
                    $fwrite(fd,"%0d %0d %0d\n",r,g,b);
                end
            end
            pixel_index=8191; #1;
            if (pixel_data !== 0 || depth !== 1023) $fatal(1,"Invalid OLED pixel index");
        end
    endtask
    task check_shading_range;
        integer d, idx;
        reg [15:0] previous_color;
        begin
            // Exercise the production shade function and column colour lookup
            // at zero, every fade boundary, the clamp, and all other depths.
            // Reference frames separately check the actual per-ray bank writes.
            idx=dut.front_bank ? 96 : 0;
            pixel_index=32*96;
            previous_color=16'hffff;
            for (d=0;d<1024;d=d+1) begin
                dut.wall_greys[idx]=dut.grey_from_depth(d);
                #1;
                if (pixel_data !== shaded_wall(d) || pixel_data > previous_color)
                    $fatal(1,"Distance shade failed at depth %0d: %h",d,pixel_data);
                previous_color=pixel_data;
            end
            // A no-hit column must still show ceiling/floor, never a wall.
            dut.wall_tops[idx]=32;
            dut.wall_bottoms[idx]=32;
            #1;
            if (pixel_data !== 16'h3184) $fatal(1,"No-hit column shaded as wall");
        end
    endtask
    initial begin
        $readmemh("frame0.mem",expected0);
        $readmemh("frame1.mem",expected1);
        $readmemh("frame2.mem",expected2);
        repeat (4) @(negedge display_clk);
        #1; if (pixel_data !== 0 || depth !== 1023) $fatal(1,"Display reset");
        reset=0;
        wait(dut.state==dut.WAIT_RAY);
        // Simultaneously change position and angle during the first scan.
        // Its results must still match the original snapshot.
        x_coord=32'd18432;
        y_coord=32'd26624;
        theta=32'd256;
        wait(dut.state==dut.WAIT_SWAP);
        repeat (5) @(negedge display_clk);
        if (dut.display_valid || pixel_data !== 0) $fatal(1,"Published before frame boundary");
        display_frame_start;
        if (!dut.front_bank || !dut.display_valid) $fatal(1,"First bank swap failed");
        fd=$fopen("prototype.ppm","w");
        $fwrite(fd,"P3\n96 64\n255\n");
        check_frame(0);
        $fclose(fd);
        fd=0;
        wait(dut.state==dut.IDLE);
        wait(dut.state==dut.WAIT_RAY);
        bank=dut.front_bank;
        check_frame(0); // old frame stays visible while the next frame renders
        wait(dut.state==dut.WAIT_SWAP);
        repeat (5) @(negedge display_clk);
        if (dut.front_bank !== bank) $fatal(1,"Bank changed mid-frame");
        // Do not export the frame a second time.
        display_frame_start;
        check_frame(1);
        // A south-facing flat wall: identical wall height at all 96 columns.
        x_coord=32'd34816; y_coord=32'd18432; theta=32'd512;
        wait(dut.state==dut.IDLE);
        wait(dut.state==dut.WAIT_SWAP);
        repeat (5) @(negedge display_clk);
        display_frame_start;
        check_frame(2);
        check_shading_range;
        x_coord=32'd34816; y_coord=32'd34816; theta=32'd128;
        @(negedge display_clk); reset=1;
        repeat (3) @(negedge display_clk);
        if (dut.display_valid || pixel_data !== 0) $fatal(1,"Renderer reset failed");
        reset=0;
        wait(dut.state==dut.WAIT_RAY);
        @(negedge display_clk); reset=1;
        repeat (3) @(negedge display_clk);
        if (dut.request_toggle || dut.display_valid) $fatal(1,"Mid-frame reset failed");
        reset=0;
        wait(dut.state==dut.WAIT_SWAP);
        repeat (5) @(negedge display_clk);
        display_frame_start;
        // After reset the default viewpoint must be restored.
        check_frame(0);
        $display("PASS: 96-column cosine reference; flat wall; distance shading at all 1024 depths; pixel colours/depth; snapshot; two banks; boundary swap; reset/restart");
        $finish;
    end
    initial begin #8000000; $fatal(1,"Renderer simulation timeout"); end
endmodule
