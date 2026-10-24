`timescale 1ns / 1ps
// Top-level controls through a whole game: title -> generating -> countdown ->
// playing (wave banner, zombies spawn, btnR defeats them, WAVE CLEAR, next wave,
// btnD damage + tint, low-health blink,
// SW0 overlay) -> game over (input delay, btnC) -> title, then reset.
module tb_controls;
    reg clk=0;
    always #5 clk=~clk;
    reg sw0=0,btnC=0,btnU=1,btnL=0,btnR=0,btnD=0;
    reg last_frame_begin=0;
    reg [1:0] last_health=3; reg [6:0] last_wave=1;
    // HUD state seen by the display may only change at frame_begin or reset.
    always @(posedge dut.oled_clk) begin
        if(!dut.oled_reset && !last_frame_begin &&
           (dut.frame_health!==last_health || dut.frame_wave!==last_wave))
            fail("HUD changed between frame boundaries");
        last_frame_begin=dut.frame_begin;
        last_health=dut.frame_health; last_wave=dut.frame_wave;
    end
    wire [15:0] led;
    wire [7:0] JB;
    wire [6:0] seg; wire dp; wire [3:0] an;
    wire ps2c, ps2d;
    map_preview_top #(.STAGE(3),.DEBOUNCE_CYCLES(4),.USE_MOUSE(0),
        .GEN_SHIFT(8),.COUNT_SHIFT(7),.OVER_SHIFT(9),.TINT_SHIFT(6),.BANNER_SHIFT(9),
        .BLINK_SHIFT(5),.SPAWN_SHIFT(6),.CLEAR_SHIFT(8),.FLASH_SHIFT(4),.RECOIL_SHIFT(6)) dut(
        .clk(clk),.sw0(sw0),.btnC(btnC),.btnU(btnU),.btnL(btnL),.btnR(btnR),.btnD(btnD),
        .PS2Clk(ps2c),.PS2Data(ps2d),.led(led),.JB(JB),.seg(seg),.dp(dp),.an(an));
    integer failures=0,cycles,requests=0,digits_seen=0,damages=0,blink_hi,blink_lo,i;
    reg [1:0] last_digit=0;
    reg [15:0] saved_seed;
    reg [255:0] saved_map;
    always @(posedge clk) if(dut.regenerate) requests=requests+1;
    always @(posedge clk) if(dut.damage) damages=damages+1;
    integer shots=0;
    always @(posedge clk) if(dut.shot_fired) shots=shots+1;
    always @(posedge clk) if(dut.flow_state==2 && dut.count_digit!=last_digit) begin
        if(last_digit!=0 && dut.count_digit!=last_digit-1) fail("countdown skipped a digit");
        last_digit=dut.count_digit; digits_seen=digits_seen+1;
    end
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
    task wait_state;
        input [2:0] s;
        begin
            cycles=0;
            while(dut.flow_state!==s && cycles<200000) begin @(posedge clk); #1; cycles=cycles+1; end
            if(dut.flow_state!==s) fail("flow did not reach the expected state");
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
    task press;   // 0=C 1=R 2=D
        input integer which;
        begin
            @(negedge clk);
            case(which) 0: btnC=1; 1: btnR=1; default: btnD=1; endcase
            repeat(12) @(negedge clk);
            btnC=0; btnR=0; btnD=0;
            repeat(12) @(negedge clk);
        end
    endtask
    task start_game;
        begin
            last_digit=0; digits_seen=0;
            press(0);
            wait_state(3'd3);
            repeat(4) @(negedge clk);
        end
    endtask
    initial begin
        repeat(40) @(negedge clk); btnU=0;
        wait_ready;                                   // boot map (seed 1ACE)
        if(dut.flow_state!=0) fail("did not boot to the title screen");
        if(dut.seed!=16'h1ACE) fail("boot seed");
        press(1);                                     // 2P disabled
        if(dut.menu_sel!=0) fail("2P selectable while disabled");
        // Bounce shorter than the debounce threshold must not start the game.
        repeat(3) begin @(negedge clk); btnC=1; @(negedge clk); btnC=0; end
        repeat(15) @(negedge clk);
        if(requests!=0 || dut.flow_state!=0) fail("bounce accepted");
        // ---- Start a game ----
        start_game;
        if(requests!=1) fail("start did not request exactly one map");
        if(digits_seen!=3) fail("countdown did not show 3, 2, 1");
        if(!led[0] || led[3:1]!=0) fail("map not ready when play began");
        if(dut.seed==0 || dut.seed==16'h1ACE) fail("start did not use a new nonzero seed");
        if(dut.health!=3 || dut.wave!=1) fail("game did not start with 3 hearts at wave 1");
        if(!dut.banner) fail("no WAVE banner at play start");
        if(dut.tint) fail("tint without damage");
        repeat(600) @(negedge clk);
        if(dut.banner) fail("banner did not time out");
        // ---- btnC in play fires the gun (and nothing else) ----
        press(0);
        if(requests!=1 || dut.flow_state!=3) fail("btnC in play regenerated or left play");
        if(shots!=1) fail("btnC in play did not fire exactly one shot");
        repeat(100) @(negedge clk);
        if(dut.weapon_recoil || dut.weapon_flash) fail("recoil/flash did not end");
        // ---- zombies spawn; btnR defeats them; WAVE CLEAR; wave 2 ----
        cycles=0; while(dut.alive!=3 && cycles<20000) begin @(posedge clk); #1; cycles=cycles+1; end
        if(dut.alive!=3 || dut.remaining!=3) fail("wave 1 did not spawn 3 zombies");
        if(dut.zombies==0) fail("no zombie tiles marked");
        press(1);
        if(dut.remaining!=2 || dut.alive!=2) fail("btnR did not defeat a zombie");
        press(1); press(1);
        cycles=0; while(!dut.wave_clear && cycles<100) begin @(posedge clk); #1; cycles=cycles+1; end
        if(!dut.wave_clear) fail("no WAVE CLEAR after the last zombie");
        cycles=0; while(dut.wave!=2 && cycles<5000) begin @(posedge clk); #1; cycles=cycles+1; end
        if(dut.wave!=2 || dut.remaining!=5) fail("wave 2 did not start with 5 zombies");
        repeat(3) @(negedge clk);
        if(!dut.banner) fail("no banner on wave change");
        // ---- btnD: damage, tint ----
        press(0+2);
        if(dut.health!=2 || damages!=1) fail("btnD did not take exactly one heart");
        if(!dut.tint) fail("no red tint after damage");
        repeat(100) @(negedge clk);
        if(dut.tint) fail("tint did not time out");
        if(dut.low_blink) fail("low-health blink with 2 hearts");
        // ---- one heart left: blinking ----
        press(2);
        if(dut.health!=1) fail("second damage");
        blink_hi=0; blink_lo=0;
        for(i=0;i<200;i=i+1) begin @(negedge clk); if(dut.low_blink) blink_hi=blink_hi+1; else blink_lo=blink_lo+1; end
        if(blink_hi==0 || blink_lo==0) fail("low-health heart does not flash");
        // ---- SW0 overlay and frame capture ----
        repeat(700) @(negedge clk);                   // let banner/tint expire
        saved_seed=dut.seed; saved_map=dut.published_map;
        sw0=1; wait_mode(1);
        if(dut.frame_screen!==3) fail("frame did not capture the playing screen");
        if(dut.frame_health!==1 || dut.frame_wave!==2) fail("frame did not capture health/wave");
        if(dut.frame_zombies===256'd0) fail("frame did not capture zombie tiles");
        @(negedge dut.oled_clk); #1;
        if(dut.last_pixel_data!==16'hFFFF) fail("map border missing at last pixel");
        sw0=0; wait_mode(0);
        @(negedge dut.oled_clk); #1;
        if(dut.pixel_data!==dut.play_pixel_data || dut.last_pixel_data!==16'h3166)
            fail("play view or last-pixel composition mismatch");
        if(dut.seed!==saved_seed || dut.published_map!==saved_map || requests!=1)
            fail("SW0 regenerated or changed the map");
        // ---- last heart: game over ----
        press(2);
        repeat(4) @(negedge clk);
        if(dut.health!=0 || dut.flow_state!=4) fail("losing the last heart did not end the game");
        press(0);                                     // too early: ignored
        if(dut.flow_state!=4) fail("game over accepted input before the delay");
        wait(dut.over_ready); repeat(4) @(negedge clk);
        press(2); press(1);                           // other buttons do nothing
        if(dut.flow_state!=4) fail("game over left on btnD/btnR");
        press(0);
        if(dut.flow_state!=0) fail("btnC on game over did not return to the title");
        // ---- second game starts fresh ----
        start_game;
        if(requests!=2 || dut.health!=3 || dut.wave!=1) fail("second game did not restart at 3 hearts, wave 1");
        if(JB[2]!==0) fail("unused OLED pin");
        // ---- reset ----
        btnU=1; repeat(40) @(negedge clk); btnU=0;
        wait_ready;
        if(dut.seed!=16'h1ACE || dut.flow_state!=0) fail("reset did not restore title and boot seed");
        if(failures==0) $display("PASS controls: title, debounce, one map per game, countdown, wave banner, zombies spawn, btnR defeats, WAVE CLEAR, wave 2, btnD damage with tint, low-health flash, SW0 overlay without regeneration, game over with input delay, retry, reset");
        else $display("FAIL controls total=%0d",failures);
        $finish;
    end
    initial begin #120000000; fail("global timeout"); $finish; end
endmodule
