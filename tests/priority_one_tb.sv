`timescale 1ns/1ps
module priority_one_tb;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    task fail(input string message); $fatal(1,"FAIL: %s",message); endtask

    reg enabled=0,fire=0;
    reg [15:0] fx=0,fy=0;
    reg [9:0] fa=0;
    reg [7:0] ack=0;
    wire ready,valid;
    wire [7:0] eid;
    wire [15:0] ex,ey;
    wire [9:0] ea;
    shot_event_queue queue(.clk(clk),.reset(rst),.enabled(enabled),.fire(fire),
        .fire_x(fx),.fire_y(fy),.fire_angle(fa),.acknowledged(ack),
        .ready(ready),.valid(valid),.event_id(eid),.event_x(ex),.event_y(ey),.event_angle(ea));
    task shoot(input integer value);
        @(negedge clk); fx=value; fy=value+100; fa=value+200; fire=1;
        @(negedge clk); fire=0;
    endtask
    task check_head(input integer id,input integer value);
        if(!valid || eid!=id || ex!=value || ey!=value+100 || ea!=value+200)
            fail("event order or captured firing pose");
    endtask

    reg [255:0] walls,occupied=0;
    reg [7:0] p1=8'h11,p2=8'hee,random_start=0;
    reg p1_live=1,p2_live=1,start=0;
    reg prefer_player2=0;
    wire busy,done,found;
    wire [7:0] tile;
    spawn_finder #(.TWO_PLAYERS(1)) finder(.clk(clk),.rst(rst),.start(start),
        .map_bits(walls),.occupied(occupied),.player_tile(p1),.player2_tile(p2),
        .player_active(p1_live),.player2_active(p2_live),.prefer_player2(prefer_player2),
        .random_start(random_start),
        .busy(busy),.done(done),.found(found),.tile(tile));
    integer distance[0:255],p1_distance[0:255],q[0:255];
    bit on_preferred_side[0:255];
    integer head,tail,t,x,y,nx,ny,n,i,j,k,best,side_best,limit,waited;
    // Independent software-style BFS reference, mark at enqueue. Each legal
    // diagonal needs both orthogonal side tiles, matching actual enemy motion.
    task reference_distances(input bit use_p1,input bit use_p2);
        for(i=0;i<256;i=i+1) distance[i]=999;
        head=0; tail=0;
        if(use_p1) begin distance[p1]=0; q[tail]=p1; tail=tail+1; end
        if(use_p2 && distance[p2]!=0) begin distance[p2]=0; q[tail]=p2; tail=tail+1; end
        while(head<tail) begin
            t=q[head]; head=head+1; x=t%16; y=t/16;
            for(j=-1;j<=1;j=j+1) for(k=-1;k<=1;k=k+1) begin
                nx=x+j; ny=y+k; n=ny*16+nx;
                if((j!=0 || k!=0) && nx>=0 && nx<16 && ny>=0 && ny<16)
                    if(!walls[n] && distance[n]==999 &&
                       (j==0 || k==0 || (!walls[y*16+nx] && !walls[ny*16+x]))) begin
                        distance[n]=distance[t]+1; q[tail]=n; tail=tail+1;
                    end
            end
        end
    endtask
    task spawn_check;
        reference_distances(1,0);
        for(i=0;i<256;i=i+1) p1_distance[i]=distance[i];
        reference_distances(0,1);
        for(i=0;i<256;i=i+1)
            on_preferred_side[i]=(distance[i]<p1_distance[i])==prefer_player2;
        reference_distances(p1_live,p2_live);
        best=0; side_best=0;
        for(i=0;i<256;i=i+1) if(!walls[i] && !occupied[i]) begin
            if(distance[i]>best) best=distance[i];
            if(on_preferred_side[i] && distance[i]!=999 && distance[i]>side_best)
                side_best=distance[i];
        end
        if(p1_live && p2_live && side_best>=2) best=side_best;
        limit=best<8 ? best : 8;
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        waited=0;
        while(!done && waited<7500) begin @(negedge clk); waited=waited+1; end
        if(!done) fail("bounded spawn search stalled");
        if(limit>=2) begin
            if(!found || walls[tile] || occupied[tile] || distance[tile]<limit)
                fail("spawn is too near a living player or invalid");
            if(p1_live && p2_live && side_best>=2 && !on_preferred_side[tile])
                fail("spawn ignored the preferred player despite a safe tile");
        end else if(found) fail("spawn violated absolute two-hop safety floor");
        @(negedge clk);
    endtask

    reg [7:0] byte_data=0;
    reg byte_valid=0,frame_error=0;
    wire good,bad;
    wire [7:0] ptype,plen;
    wire [63:0] payload;
    integer good_count=0,bad_count=0;
    packet_rx #(.MAX_PAYLOAD(8),.USE_CRC16(1),.TIMEOUT_CYCLES(20)) crc_rx(
        .clk(clk),.rst(rst),.rx_data(byte_data),.rx_valid(byte_valid),.rx_frame_error(frame_error),
        .pkt_valid(good),.pkt_error(bad),.pkt_type(ptype),.pkt_len(plen),.pkt_payload(payload));
    always @(posedge clk) begin
        if(good) good_count=good_count+1;
        if(bad) bad_count=bad_count+1;
    end
    task byte_in(input [7:0] value);
        @(negedge clk); byte_data=value; byte_valid=1;
        @(negedge clk); byte_valid=0;
    endtask
    task crc_packet(input bit corrupt);
        byte_in(8'ha5); byte_in(8'h30); byte_in(3);
        // Compensating +1/-1 payload errors fool the old additive checksum.
        byte_in(corrupt ? 8'ha6 : 8'ha5); byte_in(corrupt ? 8'hff : 0); byte_in(8'h12);
        // Golden CRC independently calculated with Python binascii.crc_hqx.
        byte_in(8'he2); byte_in(8'h21);
        repeat(3) @(negedge clk);
    endtask

    initial begin
        repeat(5) @(negedge clk); rst=0;
        repeat(3) @(negedge clk); enabled=1;
        shoot(10); shoot(20); shoot(30); shoot(40);
        if(ready) fail("full event queue did not apply backpressure");
        repeat(30) @(negedge clk);
        check_head(1,10); // dropped ACKs never retire or modify the event
        ack=99; repeat(3) @(negedge clk); check_head(1,10);
        for(integer e=1;e<=4;e=e+1) begin
            check_head(e,e*10); ack=e; repeat(3) @(negedge clk);
        end
        if(valid) fail("acknowledged queue did not empty");
        enabled=0; ack=254; repeat(3) @(negedge clk); enabled=1;
        shoot(50); shoot(60); check_head(255,50);
        ack=255; repeat(3) @(negedge clk); check_head(0,60);
        enabled=0; ack=7; repeat(3) @(negedge clk); enabled=1;
        if(valid) fail("reset/rejoin manufactured a shot");
        shoot(70);
        if(valid) fail("shot head became visible before its RAM write");
        @(negedge clk); check_head(8,70);
        // Retire the sole head and replace it on the same edge.
        ack=8; fx=80; fy=180; fa=280; fire=1;
        @(negedge clk); fire=0;
        if(valid) fail("replacement head exposed unwritten data");
        @(negedge clk); check_head(9,80);

        crc_packet(0);
        if(good_count!=1 || bad_count!=0 || payload!=64'h1200a5) fail("golden CRC rejected");
        crc_packet(1);
        if(good_count!=1 || bad_count!=1) fail("compensating payload corruption escaped CRC");
        byte_in(8'ha5); byte_in(8'h30); repeat(25) @(negedge clk);
        if(bad_count!=2) fail("truncated packet did not time out");
        crc_packet(0);
        if(good_count!=2) fail("CRC receiver did not recover after timeout");

        walls={256{1'b1}};
        for(i=1;i<15;i=i+1) for(j=1;j<15;j=j+1) walls[i*16+j]=0;
        for(integer s=0;s<8;s=s+1) begin
            random_start=s*31; prefer_player2=s[0]; spawn_check();
        end
        // Exclude only living players, including when the leader is down.
        p1_live=0; spawn_check(); p1_live=1;
        walls[8'h12]=1; walls[8'h21]=1; spawn_check();
        // Tiny arena forces bounded relaxation from 8 to 2, never to adjacency.
        walls={256{1'b1}};
        for(i=1;i<=3;i=i+1) for(j=1;j<=3;j=j+1) walls[i*16+j]=0;
        p1=8'h11; p2=8'h33; spawn_check();
        occupied[8'h13]=1; occupied[8'h31]=1; spawn_check();
        $display("PASS: priority_one_tb (event FIFO, reset/wrap, CRC faults, two-player diagonal spawning)");
        $finish;
    end
    initial begin #2000000; fail("test timeout"); end
endmodule
