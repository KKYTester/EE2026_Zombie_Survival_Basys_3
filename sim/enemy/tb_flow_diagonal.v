`timescale 1ns / 1ps
module tb_flow_diagonal;
    reg clk=0, reset=1, enabled=1;
    reg [255:0] walls=0;
    reg [7:0] goal=8'h88, goal2=8'h11, read_tile=0;
    reg live1=1, live2=0, limited=0;
    wire ready, reachable, in_field, second_goal;
    wire [2:0] direction;
    integer dist[0:255], queue[0:255];
    reg owner[0:255];
    integer trial, seed=2606;
    integer h,t,i,j,x,y,nx,ny,n,dx,dy,cycles,tx,ty;
    reg [7:0] directions_seen=0;
    always #5 clk=~clk;
    flow_field dut(.clk(clk),.reset(reset),.enabled(enabled),.walls(walls),
        .goal(goal),.goal2(goal2),.goal_active(live1),.goal2_active(live2),.limit_range(limited),
        .read_tile(read_tile),.ready(ready),.read_reachable(reachable),.read_direction(direction),
        .read_in_field(in_field),.read_second_goal(second_goal));
    task step; begin @(negedge clk); end endtask
    task verify(input restart);
        begin
            if(restart) begin reset=1; step; reset=0; end
            else step; // Let changed goals or range invalidate ready.
            for(i=0;i<256;i=i+1) dist[i]=-1;
            h=0; t=0;
            if(live1 && !walls[goal]) begin queue[t]=goal; t=t+1; dist[goal]=0; owner[goal]=0; end
            if(live2 && !walls[goal2] && dist[goal2]<0) begin
                queue[t]=goal2; t=t+1; dist[goal2]=0; owner[goal2]=1;
            end
            // Independent software-style BFS; neighbor order deliberately differs.
            while(h<t) begin
                n=queue[h]; h=h+1; x=n%16; y=n/16;
                for(dy=-1;dy<=1;dy=dy+1) for(dx=-1;dx<=1;dx=dx+1) begin
                    nx=x+dx; ny=y+dy;
                    if((!limited || dist[n]<6) &&
                       (dx!=0 || dy!=0) && nx>=0 && nx<16 && ny>=0 && ny<16)
                        if(!walls[ny*16+nx] && dist[ny*16+nx]<0 &&
                           (dx==0 || dy==0 || (!walls[y*16+nx] && !walls[ny*16+x]))) begin
                            dist[ny*16+nx]=dist[n]+1;
                            owner[ny*16+nx]=owner[n];
                            if(t>=256) $fatal(1,"reference queue overflow");
                            queue[t]=ny*16+nx; t=t+1;
                        end
                end
            end
            cycles=0;
            while(!ready) begin step; cycles=cycles+1; if(cycles>4357) $fatal(1,"BFS cycle budget"); end
            if(dut.tail!=t) $fatal(1,"queue count differs from reference");
            for(i=0;i<256;i=i+1) begin
                read_tile=i; step; step;
                if(reachable!==(dist[i]>0)) $fatal(1,"reachability mismatch tile %h",i);
                if(in_field!==(dist[i]>=0) || (in_field && second_goal!==owner[i]))
                    $fatal(1,"field membership or source mismatch at tile %h",i);
                if(reachable) begin
                    x=i%16; y=i/16;
                    case(direction)
                        0: begin tx=x-1; ty=y; end
                        1: begin tx=x+1; ty=y; end
                        2: begin tx=x; ty=y-1; end
                        3: begin tx=x; ty=y+1; end
                        4: begin tx=x-1; ty=y-1; end
                        5: begin tx=x+1; ty=y+1; end
                        6: begin tx=x+1; ty=y-1; end
                        7: begin tx=x-1; ty=y+1; end
                    endcase
                    if(tx<0 || tx>15 || ty<0 || ty>15 || dist[ty*16+tx]!=dist[i]-1)
                        $fatal(1,"arrow is not a shortest legal route tile %h",i);
                    if(direction>=4 && (walls[y*16+tx] || walls[ty*16+x]))
                        $fatal(1,"diagonal cut a wall corner");
                    directions_seen[direction]=1;
                end
            end
        end
    endtask
    initial begin
        verify(1);
        if(directions_seen!=8'hff) $fatal(1,"not all eight directions exercised");
        // A divided room with a single doorway and one isolated floor tile.
        walls=0;
        for(i=0;i<16;i=i+1) begin walls[i]=1; walls[240+i]=1; walls[16*i]=1; walls[16*i+15]=1; walls[16*i+7]=1; end
        walls[8'h77]=0; walls[8'h21]=1; walls[8'h12]=1; walls[8'h22]=1;
        goal=8'hcc; verify(1);
        live2=1; goal2=8'h33; verify(1);
        // Each side-wall case must reject the tempting direct diagonal.
        walls={256{1'b1}}; walls[8'h11]=0; walls[8'h22]=0; walls[8'h12]=0;
        goal=8'h22; live2=0; verify(1);
        walls[8'h12]=1; walls[8'h21]=0; verify(1);
        walls[8'h12]=0; verify(1);
        // Interrupt an in-progress build with a new target.
        walls=0; reset=1; step; reset=0; repeat(15) step; goal=8'hee; step;
        if(ready) $fatal(1,"stale field survived goal change");
        verify(0);
        live1=0; live2=0; verify(1);
        live1=1; live2=1; goal=8'h44; goal2=8'h4c; walls=0; verify(0);
        limited=1; verify(0); // Same roots must rebuild when only the range changes.
        goal2=goal; verify(0);
        walls[goal]=1; goal2=8'hcc; verify(1);
        for(trial=0;trial<16;trial=trial+1) begin
            for(i=0;i<256;i=i+1) walls[i]=($random(seed)&7)<2;
            goal=$random(seed); goal2=$random(seed);
            verify(1);
        end
        $display("TB_FLOW_DIAGONAL: PASS"); $finish;
    end
    initial begin #1000000; $fatal(1,"diagonal BFS timeout"); end
endmodule
