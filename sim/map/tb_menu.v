`timescale 1ns / 1ps
// Mouse on the title screen (via the top's simulation mouse hook) and
// spot checks of the menu pixels.
module tb_menu;
    reg clk=0;
    always #5 clk=~clk;
    reg btnU=1;
    wire [15:0] led; wire [7:0] JB; wire [6:0] seg; wire dp; wire [3:0] an; wire ps2c,ps2d;
    map_preview_top #(.STAGE(3),.DEBOUNCE_CYCLES(4),.USE_MOUSE(0),
        .GEN_SHIFT(8),.COUNT_SHIFT(7)) dut(
        .clk(clk),.sw0(1'b0),.btnC(1'b0),.btnU(btnU),
        .btnL(1'b0),.btnR(1'b0),.btnD(1'b0),.PS2Clk(ps2c),.PS2Data(ps2d),
        .led(led),.JB(JB),.seg(seg),.dp(dp),.an(an));
    // Independent pixel probe of the menu renderer.
    reg [6:0] px; reg [5:0] py; reg [1:0] scr; reg sel;
    reg [3:0] wt=1, wo=2; reg ovr=0;
    wire [15:0] pix;
    menu_screens #(.ENABLE_2P(0)) probe(.px(px),.py(py),.screen(scr),.sel(sel),
        .cursor_x(7'd90),.cursor_y(6'd50),.show_cursor(1'b1),.count_digit(2'd3),
        .progress(6'd32),.wave_tens(wt),.wave_ones(wo),.over_ready(ovr),.pixel(pix));
    integer failures=0,requests=0,x,y,lit;
    always @(posedge clk) if(dut.regenerate) requests=requests+1;
    task fail;
        input [511:0] msg;
        begin failures=failures+1; $display("FAIL menu: %0s",msg); end
    endtask
    task move;   // pointer move event
        input [6:0] mx; input [5:0] my;
        begin
            @(negedge clk); dut.sim_mouse_x=mx; dut.sim_mouse_y=my; dut.sim_mouse_event=1;
            @(negedge clk); dut.sim_mouse_event=0;
            repeat(3) @(negedge clk);
        end
    endtask
    task click;
        begin
            @(negedge clk); dut.sim_mouse_left=1;
            repeat(5) @(negedge clk); dut.sim_mouse_left=0;
            repeat(5) @(negedge clk);
        end
    endtask
    task probe_at;
        input [6:0] x; input [5:0] y; input [1:0] s; input sl;
        begin px=x; py=y; scr=s; sel=sl; #1; end
    endtask
    initial begin
        // ---- Pixel spot checks ----
        lit=0;
        for(y=3;y<=12;y=y+1) for(x=25;x<=70;x=x+1) begin
            probe_at(x,y,0,0); if(pix==16'hE145) lit=lit+1;
        end
        if(lit<60) fail("title text missing");
        probe_at(19,30,0,0); if(pix!==16'h2921) fail("1P highlight band missing");
        probe_at(19,39,0,1); if(pix===16'h2921) fail("disabled 2P drew a highlight");
        lit=0;
        for(x=21;x<=64;x=x+1) begin probe_at(x,39,0,0); if(pix==16'h4208) lit=lit+1; end
        if(lit==0) fail("2P text not drawn in disabled grey");
        probe_at(90,50,0,0); if(pix!==16'hEF7D) fail("cursor tip missing");
        probe_at(95,63,0,0); if(pix!==16'h1162 && pix!==16'h19E3) fail("title ground at last pixel");
        probe_at(16,41,1,0); if(pix!==16'h2EEA) fail("progress bar fill");
        probe_at(79,41,1,0); if(pix!==16'h39E8) fail("progress bar background");
        lit=0;
        for(y=14;y<=33;y=y+1) for(x=42;x<=53;x=x+1) begin
            probe_at(x,y,2,0); if(pix==16'hF645) lit=lit+1;
        end
        if(lit<100) fail("countdown digit missing");
        // Game over: big red title, wave line, hint only when ready.
        lit=0;
        for(y=10;y<=19;y=y+1) for(x=13;x<=82;x=x+1) begin
            probe_at(x,y,3,0); if(pix==16'hE145) lit=lit+1;
        end
        if(lit<120) fail("GAME OVER text missing");
        lit=0;
        for(y=30;y<=34;y=y+1) for(x=35;x<=61;x=x+1) begin
            probe_at(x,y,3,0); if(pix==16'hEF7D) lit=lit+1;
        end
        if(lit<30) fail("wave reached missing on game over");
        lit=0;
        for(y=52;y<=56;y=y+1) for(x=20;x<=74;x=x+1) begin
            probe_at(x,y,3,0); if(pix==16'h96F2) lit=lit+1;
        end
        if(lit!=0) fail("retry hint shown before the delay");
        ovr=1; lit=0;
        for(y=52;y<=56;y=y+1) for(x=20;x<=74;x=x+1) begin
            probe_at(x,y,3,0); if(pix==16'h96F2) lit=lit+1;
        end
        if(lit<40) fail("retry hint missing when ready");
        probe_at(50,30,3,0); if(pix===16'hFFFF) fail("cursor drawn on game over");
        // ---- Mouse behaviour on the real top ----
        repeat(40) @(negedge clk); btnU=0;
        while(!led[0]) @(negedge clk);
        move(5,5); click;                                  // click on empty space
        if(dut.flow_state!=0 || requests!=0) fail("click outside the options started a game");
        move(40,39); click;                                // disabled 2P
        if(dut.menu_sel!=0 || dut.flow_state!=0 || requests!=0) fail("disabled 2P could be selected or started");
        move(40,30);                                       // hover 1P
        if(dut.menu_sel!=0) fail("hover over 1P");
        click;
        repeat(5) @(negedge clk);
        if(dut.flow_state!=1) fail("click on 1P did not start");
        while(dut.flow_state!=3) @(negedge clk);
        if(requests!=1) fail("mouse start did not request exactly one map");
        dut.sim_mouse_left=1; repeat(10) @(negedge clk); dut.sim_mouse_left=0;
        repeat(10) @(negedge clk);
        if(requests!=1 || dut.flow_state!=3) fail("click in play changed the game");
        if(failures==0) $display("PASS menu: title/option/2P-disabled/cursor/progress/countdown/game-over pixels, mouse hover and click start, clicks outside or on 2P ignored, click consumed");
        else $display("FAIL menu total=%0d",failures);
        $finish;
    end
    initial begin #20000000; fail("global timeout"); $finish; end
endmodule
