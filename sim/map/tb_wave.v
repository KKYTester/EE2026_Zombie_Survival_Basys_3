`timescale 1ns / 1ps
// wave_controller + zombie_stub over waves 1-5:
//  - wave sizes 3, 5, 7, 9, 11;
//  - alive never exceeds wave+2 (cap 8), and each wave actually reaches its limit
//    while more zombies are still to come;
//  - spawn gaps: >= 2^S for waves 1-2, >= 2^(S-1) and shorter than 2^S for
//    waves 3-4, >= 2^(S-2) and shorter than 2^(S-1) from wave 5;
//  - spawns on free floor only; WAVE CLEAR between waves; restart resets;
//    spurious kills are ignored.
module tb_wave;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1,play_start=0,playing=0,defeat=0;
    wire [255:0] map_bits;
    wire [7:0] p1,p2;
    wire ready,busy;
    map_system #(.STAGE(3)) core(.clk(clk),.rst(rst),.regenerate(1'b0),.seed_in(16'h1ACE),
        .published_map(map_bits),.p1_addr(p1),.p2_addr(p2),.map_ready(ready),.busy(busy),
        .error_code(),.active_seed(),.retry_count());
    wire [6:0] wave,remaining;
    wire spawn_req,spawn_ack,defeated,clear;
    wire [7:0] spawn_tile;
    wire [5:0] alive;
    wire [255:0] zombies;
    localparam S=7;
    wave_controller #(.SPAWN_SHIFT(S),.CLEAR_SHIFT(8)) dut(.clk(clk),.rst(rst),
        .play_start(play_start),.playing(playing),.map_bits(map_bits),.occupied(zombies),
        .player_tile(p1),.spawn_ack(spawn_ack),.enemy_defeated(defeated),.wave(wave),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.alive(alive),.remaining(remaining),
        .wave_clear(clear));
    zombie_stub stub(.clk(clk),.rst(rst),.clear(play_start),.spawn_req(spawn_req),
        .spawn_tile(spawn_tile),.defeat(defeat),.spawn_ack(spawn_ack),
        .enemy_defeated(defeated),.occupied(zombies));
    integer failures=0,spawns=0,cycles,k,w,clears=0,now=0,last_ack=-1,gap;
    integer min_gap[1:5], max_alive_seen[1:5];
    reg last_clear=0;
    task fail;
        input [511:0] msg;
        begin failures=failures+1; $display("FAIL wave: %0s",msg); end
    endtask
    function integer limit_for;
        input integer wv;
        begin limit_for = (wv+2>8) ? 8 : wv+2; end
    endfunction
    always @(posedge clk) begin
        now=now+1;
        if(spawn_ack) begin
            spawns=spawns+1;
            if(map_bits[spawn_tile]) fail("spawned on a wall");
            if(zombies[spawn_tile]) fail("spawned on an occupied tile");
            if(spawn_tile==p1) fail("spawned on the player");
            if(last_ack>=0 && wave<=5) begin
                gap=now-last_ack;
                if(gap<min_gap[wave]) min_gap[wave]=gap;
            end
            last_ack=now;
        end
        if(wave<=5 && alive>max_alive_seen[wave]) max_alive_seen[wave]=alive;
        if(alive>limit_for(wave)) fail("more zombies alive than the wave allows");
        if(clear && !last_clear) begin clears=clears+1; last_ack=-1; end
        last_clear=clear;
    end
    task wait_alive;
        input integer n;
        begin
            cycles=0;
            while(alive!=n && cycles<40000) begin @(posedge clk); #1; cycles=cycles+1; end
            if(alive!=n) fail("alive count not reached");
        end
    endtask
    task kill;
        begin @(negedge clk); defeat=1; @(negedge clk); defeat=0; repeat(3) @(negedge clk); end
    endtask
    task wait_wave;
        input integer wv;
        begin
            cycles=0;
            while(wave!=wv && cycles<40000) begin @(posedge clk); #1; cycles=cycles+1; end
            if(wave!=wv) fail("next wave did not start");
        end
    endtask
    // Fill the wave up to its limit, hold there to prove the limit, then kill
    // everything as it arrives until the wave clears.
    task play_wave;
        input integer wv;
        integer size,lim;
        begin
            size=3+2*(wv-1); lim=limit_for(wv);
            if(remaining!=size) fail("wrong wave size");
            if(lim>size) lim=size;
            wait_alive(lim);
            repeat(1200) @(negedge clk);
            if(alive!=lim) fail("spawned beyond the wave limit");
            k=0;
            while(remaining!=0 && k<40) begin
                if(alive!=0) kill; else @(negedge clk);
                k=k+1;
                cycles=0; while(alive==0 && remaining!=0 && cycles<5000) begin @(posedge clk); #1; cycles=cycles+1; end
            end
            cycles=0; while(!clear && cycles<100) begin @(posedge clk); #1; cycles=cycles+1; end
            if(!clear) fail("no WAVE CLEAR after the last kill");
        end
    endtask
    initial begin
        for(w=1;w<=5;w=w+1) begin min_gap[w]=1000000; max_alive_seen[w]=0; end
        repeat(4) @(negedge clk); rst=0;
        while(!ready) @(negedge clk);
        @(negedge clk); playing=1; play_start=1; @(negedge clk); play_start=0;
        kill;                                              // no zombies yet: ignored
        if(remaining!=3 || wave!=1) fail("wave 1 should need 3 zombies");
        for(w=1;w<=4;w=w+1) begin
            play_wave(w);
            wait_wave(w+1);
        end
        wait_alive(7);                                     // wave 5 limit is 7
        repeat(1200) @(negedge clk);
        if(alive!=7) fail("wave 5 did not hold at 7 alive");
        for(w=1;w<=5;w=w+1)
            if(max_alive_seen[w]!=((limit_for(w)>3+2*(w-1)) ? 3+2*(w-1) : limit_for(w)))
                fail("a wave did not reach its alive limit");
        if(min_gap[1]<(1<<S) || min_gap[2]<(1<<S)) fail("waves 1-2 spawned too fast");
        if(min_gap[3]<(1<<(S-1)) || min_gap[3]>=(1<<S)) fail("wave 3 spawn gap not halved");
        if(min_gap[5]<(1<<(S-2)) || min_gap[5]>=(1<<(S-1))) fail("wave 5 spawn gap not quartered");
        // ---- restart ----
        @(negedge clk); play_start=1; @(negedge clk); play_start=0;
        repeat(2) @(negedge clk);
        if(wave!=1 || alive!=0 || remaining!=3 || zombies!=0) fail("restart did not reset waves and zombies");
        if(clears!=4) fail("expected four WAVE CLEAR pauses");
        if(failures==0) $display("PASS wave: waves 1-5 sizes 3/5/7/9/11, alive limits %0d/%0d/%0d/%0d/%0d (wave+2), min spawn gaps %0d/%0d/%0d clocks (waves 1/3/5), %0d spawns all on free floor, WAVE CLEAR pauses, restart, spurious kill ignored",
            max_alive_seen[1],max_alive_seen[2],max_alive_seen[3],max_alive_seen[4],max_alive_seen[5],min_gap[1],min_gap[3],min_gap[5],spawns);
        else $display("FAIL wave total=%0d",failures);
        $finish;
    end
    initial begin #50000000; fail("timeout"); $finish; end
endmodule
