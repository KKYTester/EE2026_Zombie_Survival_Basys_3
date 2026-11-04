`timescale 1ns / 1ps
module map_renderer_tb;
    reg clk=0, display_clk=0;
    always #5 clk=~clk;
    always #80 display_clk=~display_clk;
    reg reset=1, frame_begin=0;
    reg [12:0] pixel_index=0;
    wire [15:0] pixel_data;
    wire [9:0] depth;
    Map_Renderer #(.CLK_HZ(2400000)) dut (.clk(clk), .reset(reset), .display_clk(display_clk),
        .frame_begin(frame_begin), .pixel_index(pixel_index), .pixel_data(pixel_data), .column_depth(depth));
    reg [16:0] expected0[0:95], expected1[0:95];
    integer p, c, row, h, top, fd, bank;
    reg [16:0] expected;
    reg [15:0] expected_color;
    reg [7:0] r,g,b;
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
                expected=which==0 ? expected0[c] : expected1[c];
                h=expected[6:0]; top=(64-h)/2;
                expected_color=row<top ? 16'h18e7 : row<top+h ? 16'hbdf7 : 16'h3184;
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
    initial begin
        $readmemh("frame0.mem",expected0);
        $readmemh("frame1.mem",expected1);
        repeat (4) @(negedge display_clk);
        #1; if (pixel_data !== 0 || depth !== 1023) $fatal(1,"Display reset");
        reset=0;
        wait(dut.state==dut.WAIT_RAY);
        // Simultaneously change position and angle during the first scan.
        // Its results must still match the original snapshot.
        force dut.x_coord=32'd18432;
        force dut.y_coord=32'd26624;
        force dut.theta=32'd256;
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
        release dut.x_coord; release dut.y_coord; release dut.theta;
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
        $display("PASS: 96-column reference; pixel colours/depth; snapshot; two banks; boundary swap; reset/restart");
        $finish;
    end
    initial begin #5000000; $fatal(1,"Renderer simulation timeout"); end
endmodule
