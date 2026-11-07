`timescale 1ns / 1ps
// Health and magazine pickups:
//  pickup_manager - placement at each wave start (floor, no zombie, not on the
//    other pickup, at least 4 tiles from live players; relaxed when nothing
//    qualifies), new wave replaces uncollected pickups, collection by P1/P2
//    with health only below full hearts, P1 wins a tie, leaving play clears.
//  player_health  - heal +1 up to 3, never revives 0, a hit wins a tie.
//  weapon_ctrl    - magazine upgrade 6 -> 9 max with an instant full reload,
//    including mid-reload; a new game starts at 6 again.
module tb_pickups;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, playing=0, place=0;
    reg [255:0] walls, blocked=0;
    reg [7:0] random=8'h37, p1=8'h11, p2=8'hEE;
    reg p1_on=1, p2_on=1, p1_hurt=0, p2_hurt=0;
    wire hv, mv, h1, m1, h2, m2; wire [7:0] ht, mt;
    pickup_manager dut(.clk(clk),.rst(rst),.playing(playing),.place(place),.map_bits(walls),
        .blocked(blocked),.random(random),.p1_tile(p1),.p2_tile(p2),.p1_active(p1_on),.p2_active(p2_on),
        .p1_hurt(p1_hurt),.p2_hurt(p2_hurt),.health_valid(hv),.health_tile(ht),.mag_valid(mv),.mag_tile(mt),
        .p1_heal(h1),.p1_mag(m1),.p2_heal(h2),.p2_mag(m2));
    integer failures=0, i, n, heals1=0, mags1=0, heals2=0, mags2=0;
    always @(posedge clk) begin heals1=heals1+h1; mags1=mags1+m1; heals2=heals2+h2; mags2=mags2+m2; end
    task fail(input [8*72-1:0] m); begin failures=failures+1; $display("FAIL pickups: %0s", m); end endtask
    function integer cheb(input [7:0] a, input [7:0] b);
        integer dx, dy; begin
            dx=a[3:0]>b[3:0] ? a[3:0]-b[3:0] : b[3:0]-a[3:0];
            dy=a[7:4]>b[7:4] ? a[7:4]-b[7:4] : b[7:4]-a[7:4];
            cheb = dx>dy ? dx : dy;
        end
    endfunction
    task do_place; begin
        @(negedge clk); place=1; @(negedge clk); place=0;
        repeat(1200) @(negedge clk);
    end endtask
    task check_spot(input [7:0] t, input [8*20-1:0] what); begin
        if(walls[t]) fail({what," on a wall"});
        if(blocked[t]) fail({what," on a zombie"});
        if(p1_on && cheb(t,p1)<4) fail({what," too close to P1"});
        if(p2_on && cheb(t,p2)<4) fail({what," too close to P2"});
    end endtask

    // player_health
    reg h_start=0, h_play=0, h_hit=0, h_heal=0; wire [1:0] hearts; wire dmg;
    player_health hp(.clk(clk),.rst(rst),.play_start(h_start),.playing(h_play),.hit(h_hit),
        .heal(h_heal),.health(hearts),.damage(dmg));
    task pulse_hit; begin @(negedge clk); h_hit=1; @(negedge clk); h_hit=0; end endtask
    task pulse_heal; begin @(negedge clk); h_heal=1; @(negedge clk); h_heal=0; end endtask
    // weapon_ctrl
    reg w_play=0, w_fire=0, w_reload=0, w_up=0;
    wire w_flash, w_recoil, w_shot, w_rel; wire [3:0] w_ammo, w_cap; wire [4:0] w_drop; wire [1:0] w_st, w_ph;
    weapon_ctrl #(.FLASH_SHIFT(2),.RECOIL_SHIFT(4),.RELOAD_SHIFT(6)) gun(.clk(clk),.rst(rst),.playing(w_play),
        .fire(w_fire),.reload(w_reload),.upgrade(w_up),.flash(w_flash),.recoil(w_recoil),.shot_fired(w_shot),
        .ammo(w_ammo),.capacity(w_cap),.reloading(w_rel),.drop(w_drop),.state(w_st),.reload_phase(w_ph));
    task fire_once; begin
        @(negedge clk); w_fire=1; @(negedge clk); w_fire=0;
        while(w_st!=0) @(negedge clk);
    end endtask
    task upgrade; begin @(negedge clk); w_up=1; @(negedge clk); w_up=0; @(negedge clk); end endtask

    initial begin
        // Map: border walls, a wall column at x=8 with a gap.
        walls=0;
        for(i=0;i<16;i=i+1) begin walls[{4'd0,i[3:0]}]=1; walls[{4'd15,i[3:0]}]=1;
            walls[{i[3:0],4'd0}]=1; walls[{i[3:0],4'd15}]=1; walls[{i[3:0],4'd8}]=1; end
        walls[8'h78]=0;
        blocked[8'h55]=1; blocked[8'h99]=1;
        repeat(3) @(negedge clk); rst=0; playing=1;
        // ---- placement over many seeds ----
        for(n=0;n<40;n=n+1) begin
            random=$random; p1=8'h11+n; if(walls[p1]) p1=8'h22;
            do_place;
            if(!hv || !mv) fail("pickups not placed");
            if(ht==mt) fail("both pickups on one tile");
            check_spot(ht,"health"); check_spot(mt,"magazine");
        end
        // ---- collection ----
        p1=8'h22; p2=8'hDD; random=8'h91; do_place;
        p1=ht; p1_hurt=0; repeat(5) @(negedge clk);
        if(!hv || heals1!=0) fail("health taken at full hearts");
        p1_hurt=1; repeat(3) @(negedge clk);
        if(hv || heals1!=1) fail("hurt P1 did not take health once");
        p1=mt; repeat(3) @(negedge clk);
        if(mv || mags1!=1) fail("P1 did not take the magazine once");
        do_place;
        p1=mt; p2=mt; repeat(3) @(negedge clk);
        if(mags1!=2 || mags2!=0) fail("P1 should win a tie on the magazine");
        p1=8'h22; p2=ht; p2_hurt=1; repeat(3) @(negedge clk);
        if(heals2!=1 || hv) fail("hurt P2 did not take health");
        // Downed P2 cannot collect.
        do_place; p2_on=0; p2=mt; repeat(3) @(negedge clk);
        if(!mv || mags2!=0) fail("downed P2 collected a pickup");
        p2_on=1; p2=8'hDD;
        // New wave replaces uncollected pickups; leaving play clears them.
        random=8'h13; do_place;
        if(!hv || !mv) fail("new wave did not place pickups");
        playing=0; @(negedge clk); @(negedge clk);
        if(hv || mv) fail("pickups stayed after leaving play");
        playing=1;
        // ---- tiny map: only tiles near the players are free -> relaxed placement ----
        walls={256{1'b1}}; walls[8'h33]=0; walls[8'h34]=0; walls[8'h35]=0; walls[8'h36]=0; blocked=0;
        p1=8'h33; p2=8'h36;
        do_place;
        if(!hv || !mv) fail("relaxed placement failed on a small map");
        if(ht==p1 || ht==p2 || mt==p1 || mt==p2 || ht==mt) fail("relaxed placement on a player or doubled");
        // ---- player_health ----
        @(negedge clk); h_start=1; @(negedge clk); h_start=0; h_play=1;
        pulse_heal; if(hearts!=3) fail("heal above 3 hearts");
        pulse_hit; pulse_hit; if(hearts!=1) fail("hits");
        pulse_heal; if(hearts!=2) fail("heal +1");
        pulse_heal; pulse_heal; if(hearts!=3) fail("heal not capped at 3");
        pulse_hit; pulse_hit; pulse_hit; if(hearts!=0) fail("down");
        pulse_heal; if(hearts!=0) fail("heal revived a downed player");
        // ---- weapon_ctrl ----
        w_play=1; repeat(3) @(negedge clk);
        if(w_cap!=6 || w_ammo!=6) fail("weapon does not start at 6/6");
        fire_once; fire_once; if(w_ammo!=4) fail("firing");
        upgrade; if(w_cap!=7 || w_ammo!=7 || w_st!=0) fail("upgrade did not give 7 full rounds");
        // Mid-reload upgrade: refill and raise at once.
        @(negedge clk); w_reload=0; fire_once; @(negedge clk); w_reload=1; @(negedge clk); w_reload=0;
        repeat(20) @(negedge clk);
        if(!w_rel) fail("reload did not start");
        upgrade; if(w_rel || w_cap!=8 || w_ammo!=8 || w_drop!=0) fail("upgrade during reload");
        upgrade; upgrade; upgrade;
        if(w_cap!=9 || w_ammo!=9) fail("magazine not capped at 9");
        for(i=0;i<9;i=i+1) fire_once;
        while(w_rel || w_st!=0) @(negedge clk);
        if(w_ammo!=9) fail("auto reload did not refill to the bigger magazine");
        w_play=0; repeat(2) @(negedge clk); w_play=1; repeat(2) @(negedge clk);
        if(w_cap!=6 || w_ammo!=6) fail("new game did not reset the magazine to 6");
        if(failures==0) $display("TB_PICKUPS: PASS (placement rules over 40 seeds, health only when hurt, P1 wins ties, downed player cannot collect, new wave replaces, cleared outside play, relaxed placement; heal +1 capped, no revive; magazine 6->9 with instant reload, mid-reload upgrade, reset per game)");
        else $display("TB_PICKUPS: FAIL total=%0d", failures);
        $finish;
    end
endmodule
