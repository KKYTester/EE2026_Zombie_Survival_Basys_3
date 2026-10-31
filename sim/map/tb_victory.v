`timescale 1ns / 1ps
// Whole-top test of the new end of the game and of the reload controls:
//  - left-click fires; six rounds empty the magazine and reload by themselves;
//    right-click and btnL reload a partial magazine; fire ignored while reloading;
//  - frame capture carries ammo / reloading / drop to the display;
//  - with WIN_WAVE=2, clearing waves 1 and 2 (btnR stand-in kills) ends in
//    VICTORY after the WAVE CLEAR pause (flow state 5, menu screen 4);
//  - victory ignores input until over_ready, other buttons do nothing, then a
//    click returns to the title; the next game starts at wave 1 with 3 hearts
//    and a full magazine.
module tb_victory;
    reg clk=0;
    always #5 clk=~clk;
    reg btnC=0,btnU=1,btnL=0,btnR=0,btnD=0;
    wire [15:0] led; wire [7:0] JB; wire [6:0] seg; wire dp; wire [3:0] an; wire ps2c,ps2d;
    map_preview_top #(.STAGE(3),.DEBOUNCE_CYCLES(4),.USE_MOUSE(0),
        .GEN_SHIFT(8),.COUNT_SHIFT(7),.OVER_SHIFT(9),.TINT_SHIFT(6),.BANNER_SHIFT(9),
        .BLINK_SHIFT(5),.SPAWN_SHIFT(6),.CLEAR_SHIFT(8),.FLASH_SHIFT(4),.RECOIL_SHIFT(6),
        .RELOAD_SHIFT(7),.WIN_WAVE(2)) dut(
        .clk(clk),.sw0(1'b0),.btnC(btnC),.btnU(btnU),.btnL(btnL),.btnR(btnR),.btnD(btnD),
        .PS2Clk(ps2c),.PS2Data(ps2d),.led(led),.JB(JB),.seg(seg),.dp(dp),.an(an));
    integer failures=0,cycles,shots=0,k,ammo_frames=0;
    always @(posedge clk) if(dut.game.shot_fired) shots=shots+1;
    always @(posedge dut.game.oled_clk) if(dut.game.oled_frame_begin) begin
        if(dut.game.frame_screen==3 && dut.game.frame_ammo!=6) ammo_frames=ammo_frames+1;
    end
    task fail;
        input [511:0] msg;
        begin failures=failures+1; $display("FAIL victory: %0s",msg); end
    endtask
    task press;   // 0=C 1=R 2=D 3=L
        input integer which;
        begin
            @(negedge clk);
            case(which) 0: btnC=1; 1: btnR=1; 2: btnD=1; default: btnL=1; endcase
            repeat(12) @(negedge clk);
            btnC=0; btnR=0; btnD=0; btnL=0;
            repeat(12) @(negedge clk);
        end
    endtask
    task left_click;
        begin @(negedge clk); dut.sim_mouse_left=1; repeat(4) @(negedge clk); dut.sim_mouse_left=0; repeat(4) @(negedge clk); end
    endtask
    task right_click;
        begin @(negedge clk); dut.sim_mouse_right=1; repeat(4) @(negedge clk); dut.sim_mouse_right=0; repeat(4) @(negedge clk); end
    endtask
    task wait_weapon_ready;
        begin
            cycles=0; while(dut.game.weapon_state!=0 && cycles<5000) begin @(negedge clk); cycles=cycles+1; end
            if(dut.game.weapon_state!=0) fail("weapon did not return to ready");
        end
    endtask
    task wait_state;
        input [2:0] s;
        begin
            cycles=0;
            while(dut.game.flow_state!==s && cycles<400000) begin @(posedge clk); #1; cycles=cycles+1; end
            if(dut.game.flow_state!==s) fail("flow did not reach the expected state");
        end
    endtask
    task clear_wave;
        begin
            k=0;
            while(dut.game.remaining!=0 && k<400) begin
                if(dut.game.alive!=0) press(1); else @(negedge clk);
                k=k+1;
            end
            if(dut.game.remaining!=0) fail("could not clear the wave");
        end
    endtask
    initial begin
        repeat(40) @(negedge clk); btnU=0;
        while(!led[0]) @(negedge clk);
        press(0); wait_state(3); repeat(4) @(negedge clk);
        if(dut.game.ammo!=6) fail("game did not start with a full magazine");
        // ---- six left-clicks empty the magazine, then it reloads itself ----
        repeat(5) begin left_click; wait_weapon_ready; end
        left_click;
        if(shots!=6 || dut.game.ammo!=0) fail("six clicks did not fire six rounds");
        cycles=0; while(!dut.game.weapon_reloading && cycles<500) begin @(negedge clk); cycles=cycles+1; end
        if(!dut.game.weapon_reloading) fail("empty magazine did not reload");
        left_click; press(0);                                   // fire while reloading: ignored
        wait_weapon_ready;
        if(shots!=6 || dut.game.ammo!=6) fail("fired during reload or no refill");
        // ---- right-click and btnL reload a partial magazine ----
        left_click; wait_weapon_ready; right_click; repeat(3) @(negedge clk);
        if(!dut.game.weapon_reloading) fail("right-click did not reload");
        wait_weapon_ready;
        left_click; wait_weapon_ready; press(3);
        if(!dut.game.weapon_reloading) fail("btnL did not reload");
        wait_weapon_ready;
        if(dut.game.ammo!=6 || shots!=8) fail("ammo/shot count after manual reloads");
        right_click; repeat(3) @(negedge clk);
        if(dut.game.weapon_reloading) fail("reload with a full magazine");
        // A frame takes ~1.6M clocks, far longer than this test's reload, so check
        // the frame capture with a partly used magazine (it stays at 5).
        left_click; wait_weapon_ready;
        cycles=0; while(ammo_frames==0 && cycles<4000000) begin @(negedge clk); cycles=cycles+1; end
        if(ammo_frames==0 || dut.game.frame_ammo!=5 || dut.game.frame_drop!=0) fail("display never captured the ammo count");
        press(3); wait_weapon_ready;
        // ---- clear waves 1 and 2: victory ----
        if(dut.game.flow_state!=3 || dut.game.wave!=1) fail("not in wave 1");
        clear_wave;
        cycles=0; while(dut.game.wave!=2 && cycles<20000) begin @(posedge clk); #1; cycles=cycles+1; end
        if(dut.game.wave!=2) fail("wave 2 did not start");
        if(dut.game.flow_state!=3) fail("won after wave 1");
        clear_wave;
        cycles=0; while(!dut.game.wave_clear && cycles<200) begin @(posedge clk); #1; cycles=cycles+1; end
        if(!dut.game.wave_clear) fail("no WAVE CLEAR after the last wave");
        if(dut.game.flow_state!=3) fail("victory before the WAVE CLEAR pause");
        wait_state(5);
        // ---- victory screen input ----
        left_click; press(0);                                   // too early: ignored
        if(dut.game.flow_state!=5) fail("victory accepted input before the delay");
        if(dut.game.wave!=2) fail("wave changed at victory");
        if(dut.game.zombies!=0) fail("zombies left after victory");
        cycles=0; while(dut.game.menu_screen!=4 && cycles<4000000) begin @(posedge clk); #1; cycles=cycles+1; end
        if(dut.game.menu_screen!=4) fail("display did not show the victory screen");
        if(dut.game.flow_state==5) begin wait(dut.game.over_ready); repeat(4) @(negedge clk); end
        press(1); press(2); press(3); right_click;              // other inputs do nothing
        if(dut.game.flow_state!=5) fail("victory left on another button");
        left_click;
        if(dut.game.flow_state!=0) fail("click on victory did not return to the title");
        // ---- next game starts fresh ----
        press(0); wait_state(3); repeat(4) @(negedge clk);
        if(dut.game.wave!=1 || dut.game.health!=3 || dut.game.ammo!=6 || dut.game.game_won) fail("next game did not start fresh");
        if(failures==0) $display("PASS victory: click fires, 6-round magazine with automatic reload, right-click and btnL reload, fire ignored during reload, ammo/reload reach the display, WAVE CLEAR then VICTORY after wave WIN_WAVE, victory input delay, other inputs ignored, click returns to title, next game fresh (%0d shots)",shots);
        else $display("FAIL victory total=%0d",failures);
        $finish;
    end
    initial begin #400000000; fail("global timeout"); $finish; end
endmodule
