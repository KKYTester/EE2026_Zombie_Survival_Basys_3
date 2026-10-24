`timescale 1ns / 1ps
// spawn_finder against an independent software-style BFS: every returned tile
// must be floor, unoccupied and at least MIN_DIST steps from the player;
// "not found" only when no such tile exists. Runs on 20 generated maps,
// several random starts each, with occupied tiles, plus an injected tiny map.
module tb_spawn;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1,regen=0,start=0;
    reg [15:0] seed_in=16'h1ACE;
    wire [255:0] map_bits;
    wire [7:0] p1,p2;
    wire ready,busy;
    map_system #(.STAGE(3)) core(.clk(clk),.rst(rst),.regenerate(regen),.seed_in(seed_in),
        .published_map(map_bits),.p1_addr(p1),.p2_addr(p2),.map_ready(ready),.busy(busy),
        .error_code(),.active_seed(),.retry_count());
    reg [255:0] test_map, occupied;
    reg [7:0] player, rstart;
    wire fbusy,fdone,ffound;
    wire [7:0] ftile;
    spawn_finder #(.MIN_DIST(8)) dut(.clk(clk),.rst(rst),.start(start),.map_bits(test_map),
        .occupied(occupied),.player_tile(player),.random_start(rstart),
        .busy(fbusy),.done(fdone),.found(ffound),.tile(ftile));
    integer dst[0:255];
    integer q[0:255];
    integer failures=0,checks=0,m,k,i,a,n,rd,wr,cycles,maxcyc=0,eligible;
    task fail;
        input [511:0] msg;
        begin failures=failures+1; $display("FAIL spawn: %0s",msg); end
    endtask
    task bfs;     // dst[] = walking steps from player, 999 if unreachable
        begin
            for(i=0;i<256;i=i+1) dst[i]=999;
            dst[player]=0; q[0]=player; rd=0; wr=1;
            while(rd<wr) begin
                a=q[rd]; rd=rd+1;
                for(i=0;i<4;i=i+1) begin
                    n=-1;
                    case(i) 0: if(a%16>0) n=a-1; 1: if(a%16<15) n=a+1;
                            2: if(a/16>0) n=a-16; 3: if(a/16<15) n=a+16; endcase
                    if(n>=0) if(!test_map[n] && dst[n]==999) begin dst[n]=dst[a]+1; q[wr]=n; wr=wr+1; end
                end
            end
        end
    endtask
    task run_one;
        begin
            bfs;
            eligible=0;
            for(i=0;i<256;i=i+1) if(!test_map[i] && !occupied[i] && dst[i]>=8) eligible=eligible+1;
            @(negedge clk); start=1; @(negedge clk); start=0;
            cycles=0;
            while(!fdone && cycles<400) begin @(posedge clk); #1; cycles=cycles+1; end
            if(cycles>maxcyc) maxcyc=cycles;
            checks=checks+1;
            if(!fdone) fail("finder did not finish");
            else if(ffound) begin
                if(test_map[ftile]) fail("spawned on a wall");
                if(occupied[ftile]) fail("spawned on an occupied tile");
                if(dst[ftile]<8) fail("spawned too close to the player");
            end else if(eligible!=0) fail("reported no tile although one exists");
        end
    endtask
    initial begin
        occupied=0; player=8'h11; rstart=0; test_map={256{1'b1}};
        repeat(4) @(negedge clk); rst=0;
        for(m=0;m<20;m=m+1) begin
            while(!ready) @(negedge clk);
            test_map=map_bits; player=p1;
            for(k=0;k<6;k=k+1) begin
                rstart=k*41+m*7;
                occupied=0;
                if(k>=3) begin occupied[ftile]=1; occupied[p2]=1; end
                run_one;
            end
            player=p2; rstart=8'h80; run_one;          // from the other corner
            seed_in=seed_in*16'd25173+16'd13849; if(seed_in==0) seed_in=1;
            @(negedge clk); regen=1; @(negedge clk); regen=0; repeat(3) @(negedge clk);
        end
        // Tiny map: a 3x3 room, nothing is 8 steps away -> not found.
        test_map={256{1'b1}};
        for(i=1;i<=3;i=i+1) for(k=1;k<=3;k=k+1) test_map[i*16+k]=0;
        player=8'h11; occupied=0; rstart=0; run_one;
        if(ffound) fail("found a tile in a map with no far floor");
        if(failures==0) $display("PASS spawn: %0d searches on 20 generated maps and a tiny map; every tile floor, free and >= 8 steps away (independent BFS); max %0d clocks",checks,maxcyc);
        else $display("FAIL spawn total=%0d",failures);
        $finish;
    end
    initial begin #50000000; fail("timeout"); $finish; end
endmodule
