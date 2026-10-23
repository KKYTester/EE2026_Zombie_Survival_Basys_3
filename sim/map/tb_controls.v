`timescale 1ns / 1ps
module tb_controls;
    reg clk=0;
    always #5 clk=~clk;
    reg sw0=0,btnC=0,btnU=1;
    reg [6:0] health_switches=0;
    reg [3:0] wave_switches=0;
    reg [6:0] saved_health,saved_wave;
    reg [15:0] expected_hud;
    reg last_frame_begin=0;
    reg [6:0] last_health=0,last_wave=0;
    // A changed health/wave snapshot must follow frame_begin or reset.
    always @(posedge dut.oled_clk) begin
        if(!dut.oled_reset && !last_frame_begin &&
           (dut.frame_health!==last_health || dut.frame_wave!==last_wave))
            fail("HUD changed between frame boundaries");
        last_frame_begin=dut.frame_begin;
        last_health=dut.frame_health; last_wave=dut.frame_wave;
    end
    wire [15:0] led;
    wire [7:0] JB;
    map_preview_top #(.STAGE(3),.DEBOUNCE_CYCLES(4)) dut(
        .clk(clk),.sw0(sw0),.sw_wave(wave_switches),.sw_health(health_switches),.btnC(btnC),.btnU(btnU),.led(led),.JB(JB));
    integer failures=0,cycles,requests=0;
    reg [15:0] saved_seed;
    reg [255:0] saved_map;
    always @(posedge clk) if(dut.regenerate) requests=requests+1;
    task fail;
        input [511:0] msg;
        begin failures=failures+1; $display("FAIL controls: %0s",msg); end
    endtask
    task wait_ready;
        begin
            cycles=0;
            while(!led[0] && cycles<41000) begin @(posedge clk); #1; cycles=cycles+1; end
            if(!led[0] || led[3:1]!=0 || led[15]) fail("ready/LED state");
        end
    endtask
    task wait_mode;
        input expected;
        begin
            cycles=0;
            while(dut.frame_mode!==expected && cycles<2000000) begin
                @(posedge clk); #1; cycles=cycles+1;
            end
            if(dut.frame_mode!==expected) fail("mode did not change at next frame");
        end
    endtask
    initial begin
        repeat(40) @(negedge clk); btnU=0;
        wait_ready;
        // Bounce shorter than debounce threshold must not regenerate.
        repeat(3) begin
            @(negedge clk); btnC=1;
            @(negedge clk); btnC=0;
        end
        repeat(15) @(negedge clk);
        if(requests!=0) fail("bounce accepted");
        btnC=1; repeat(20) @(negedge clk);
        wait_ready;
        repeat(40) @(negedge clk);
        if(requests!=1) fail("held press repeated or missing");
        if(dut.seed==0 || dut.seed==16'h1ACE) fail("button did not latch nonzero counter seed");
        btnC=0; repeat(20) @(negedge clk);
        saved_seed=dut.seed; saved_map=dut.published_map;
        health_switches=127; wave_switches=15;
        sw0=1; wait_mode(1);
        if(dut.frame_health!==99 || dut.frame_wave!==15) fail("HUD switches not clamped/captured with SW0");
        if(dut.frame_mode!==1) fail("zoom map not selected");
        @(negedge dut.oled_clk); #1;
        if(dut.last_pixel_data!==16'hFFFF) fail("zoom border missing at last pixel");
        saved_health=dut.frame_health; saved_wave=dut.frame_wave;
        health_switches=24; wave_switches=7;
        repeat(8) @(negedge clk);
        if(dut.hud_sync2!=={7'd24,4'd7}) fail("HUD switch synchronizers");
        if(dut.frame_health!==saved_health || dut.frame_wave!==saved_wave)
            fail("HUD switches changed snapshot before next frame");
        sw0=0; wait_mode(0);
        if(dut.frame_health!==24 || dut.frame_wave!==7) fail("HUD snapshot not refreshed");
        @(negedge dut.oled_clk); #1;
        if(dut.pixel_data!==dut.hud_pixel_data || dut.last_pixel_data!==16'h3166)
            fail("HUD view or last-pixel composition mismatch");
        if(dut.seed!==saved_seed || dut.published_map!==saved_map || requests!=1)
            fail("SW0 regenerated or changed the map");
        if(JB[2]!==0) fail("unused OLED pin");
        btnU=1; repeat(40) @(negedge clk); btnU=0;
        wait_ready;
        if(dut.seed!=16'h1ACE) fail("button reset did not restore boot seed");
        if(failures==0) $display("PASS controls: debounce, held press, seed latch, frame mode, synchronized/frame-held HUD switches, no SW regeneration, reset");
        else $display("FAIL controls total=%0d",failures);
        $finish;
    end
    initial begin #60000000; fail("global timeout"); $finish; end
endmodule
