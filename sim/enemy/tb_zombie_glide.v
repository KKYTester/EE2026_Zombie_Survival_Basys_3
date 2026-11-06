`timescale 1ns / 1ps
// zombie_glide: spawn snaps, a one-tile move walks in 256 unit steps at the
// set rate (never more than one unit per step), reaches the tile exactly one
// move period later, a respawn far away or a dead slot snaps, other slots
// are unaffected, and back-to-back moves keep walking without jumps.
module tb_zombie_glide;
    localparam integer STEP=4, W=12;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg [7:0] active=0;
    reg [95:0] tx=0, ty=0;
    wire [95:0] gx, gy;
    zombie_glide #(.STEP_CYCLES(STEP)) dut(.clk(clk),.rst(rst),.active(active),
        .target_x(tx),.target_y(ty),.glide_x(gx),.glide_y(gy));
    integer failures=0, i, prev, steps, cycles;
    function integer centre; input integer tile; centre = tile*256+128; endfunction
    task fail; input [511:0] m; begin failures=failures+1; $display("FAIL zombie_glide: %0s", m); end endtask
    task set_pos; input integer slot, x, y;
        begin tx[slot*W +: W]=centre(x); ty[slot*W +: W]=centre(y); end endtask
    wire [11:0] g0x=gx[0 +: 12], g0y=gy[0 +: 12], g3x=gx[36 +: 12];
    initial begin
        repeat(3) @(negedge clk); rst=0;
        // Spawn slot 0 at (2,5) and slot 3 at (9,9): both snap at once.
        set_pos(0,2,5); set_pos(3,9,9); active=8'b0000_1001;
        repeat(2) @(negedge clk);
        if(g0x!=centre(2) || g0y!=centre(5)) fail("spawn did not snap");
        if(g3x!=centre(9)) fail("second slot spawn did not snap");
        // Slot 0 moves one tile right: walks there.
        set_pos(0,3,5);
        prev=g0x; steps=0; cycles=0;
        while(g0x!=centre(3) && cycles<STEP*300) begin
            @(negedge clk); cycles=cycles+1;
            if(g0x<prev || g0x>prev+1) fail("moved more than one unit at once or backwards");
            if(g0x!=prev) steps=steps+1;
            prev=g0x;
            if(g0y!=centre(5)) fail("y moved on an x-only step");
        end
        if(g0x!=centre(3)) fail("never reached the new tile");
        if(steps!=256) fail("tile walk was not 256 unit steps");
        if(cycles<STEP*255 || cycles>STEP*257) fail("walk took the wrong time");
        if(g3x!=centre(9)) fail("other slot moved");
        // Move up: y walks down by one tile.
        set_pos(0,3,4); cycles=0;
        repeat(STEP*128) @(negedge clk);
        if(!(g0y<centre(5) && g0y>centre(4))) fail("half-way point not between tiles");
        while(g0y!=centre(4) && cycles<STEP*300) begin @(negedge clk); cycles=cycles+1; end
        if(g0y!=centre(4)) fail("vertical walk did not arrive");
        // Back-to-back moves: new target each period, never jumps.
        prev=g0x;
        for(i=4;i<=6;i=i+1) begin
            set_pos(0,i,4);
            repeat(STEP*256) begin
                @(negedge clk);
                if(g0x>prev+1 || g0x<prev) fail("jump during chained moves");
                prev=g0x;
            end
        end
        if(g0x!=centre(6)) fail("chained moves did not end on the last tile");
        // One tile ahead while still walking: keeps walking, no snap.
        set_pos(0,7,4); repeat(STEP*10) @(negedge clk); set_pos(0,8,4); @(negedge clk);
        if(g0x>centre(7)) fail("snapped when only one tile behind");
        repeat(STEP*600) @(negedge clk);
        if(g0x!=centre(8)) fail("did not catch up after a quick second move");
        // Slot reused far away while still active: snaps.
        set_pos(0,12,1); @(negedge clk); @(negedge clk);
        if(g0x!=centre(12) || g0y!=centre(1)) fail("far respawn did not snap");
        // Dead slot follows its (reset) position, then a new spawn snaps.
        active[0]=0; set_pos(0,0,0); @(negedge clk); @(negedge clk);
        if(g0x!=centre(0)) fail("inactive slot did not follow");
        set_pos(0,7,7); active[0]=1; @(negedge clk); @(negedge clk);
        if(g0x!=centre(7) || g0y!=centre(7)) fail("respawn after death did not snap");
        // Reset snaps everything.
        set_pos(3,10,9); rst=1; @(negedge clk); @(negedge clk); rst=0;
        if(g3x!=centre(10)) fail("reset did not snap");
        if(failures==0) $display("TB_ZOMBIE_GLIDE: PASS (256-step tile walk, x and y, chained moves, catch-up, snaps on spawn/respawn/death/reset)");
        else $display("TB_ZOMBIE_GLIDE: FAIL total=%0d", failures);
        $finish;
    end
endmodule
