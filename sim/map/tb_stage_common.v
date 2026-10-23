`timescale 1ns / 1ps
module tb_stage_common #(parameter STAGE=3);
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1,regenerate=0;
    reg [15:0] seed_in=16'h1234;
    wire [255:0] map_bits;
    wire [7:0] p1,p2;
    wire ready,busy;
    wire [2:0] error_code,retries;
    wire [15:0] active_seed;
    integer failures=0;
    integer deepest=0,two_doors=0,max_stack=0;
    always @(posedge clk) if(!rst && STAGE!=1) begin
        if(dut.generator.sp>max_stack) max_stack=dut.generator.sp;
        if(dut.generator.sp>8) fail("region stack overflow");
        if(dut.generator.state==8) begin
            if(dut.generator.depth>deepest) deepest=dut.generator.depth;
            if(dut.generator.second_found) begin
                two_doors=two_doors+1;
                if(dut.generator.second_door==dut.generator.door_pos ||
                   !dut.generator.second_door[0] ||
                   dut.generator.second_door<dut.generator.door_lo ||
                   dut.generator.second_door>dut.generator.door_hi)
                    fail("second doorway is invalid");
            end
        end
    end
    integer k,cycles,max_cycles,write_count,draw_count;
    reg [255:0] first_map,base_map,last_published;
    reg [15:0] random_seed;
    map_system #(.STAGE(STAGE)) dut(.clk(clk),.rst(rst),.regenerate(regenerate),
        .seed_in(seed_in),.published_map(map_bits),.p1_addr(p1),.p2_addr(p2),
        .map_ready(ready),.busy(busy),.error_code(error_code),
        .active_seed(active_seed),.retry_count(retries));
    reg val_start=0;
    reg [255:0] injected_map;
    wire val_busy,val_done,val_pass;
    wire [2:0] val_error;
    wire [7:0] vp1,vp2;
    wire [8:0] floors,reached;
    map_validator validator(.clk(clk),.rst(rst),.start(val_start),
        .map_bits(injected_map),.busy(val_busy),.done(val_done),.passed(val_pass),
        .error_code(val_error),.p1_addr(vp1),.p2_addr(vp2),
        .floor_count(floors),.reachable_count(reached));
    wire timeout_done,timeout_pass;
    wire [2:0] timeout_error;
    map_validator #(.MAX_CYCLES(8)) timeout_validator(.clk(clk),.rst(rst),
        .start(val_start),.map_bits(injected_map),.busy(),.done(timeout_done),
        .passed(timeout_pass),.error_code(timeout_error),.p1_addr(),.p2_addr(),
        .floor_count(),.reachable_count());
    wire retry_busy,retry_ready;
    wire [2:0] retry_error,retry_total;
    map_system #(.STAGE(3),.VALIDATE_LIMIT(8)) retry_dut(.clk(clk),.rst(rst),
        .regenerate(1'b0),.seed_in(16'h1234),.published_map(),.p1_addr(),.p2_addr(),
        .map_ready(retry_ready),.busy(retry_busy),.error_code(retry_error),
        .active_seed(),.retry_count(retry_total));

    task fail;
        input [511:0] message;
        begin failures=failures+1; $display("FAIL stage %0d: %0s",STAGE,message); end
    endtask
    task wait_map;
        begin
            cycles=0; write_count=0; draw_count=0;
            while(busy && cycles<41000) begin
                @(posedge clk);
                if(dut.wr_en) write_count=write_count+1;
                if(dut.generator.state==8) draw_count=draw_count+1;
                #1; cycles=cycles+1;
                if(!ready && map_bits!==last_published) fail("unvalidated map was published");
            end
            if(cycles>max_cycles) max_cycles=cycles;
            if(busy || !ready || error_code!=0) fail("map did not pass within 41000 cycles");
            if(retries!=0) fail("valid recursive division unexpectedly needed a retry");
            last_published=map_bits;
        end
    endtask
    // Independent software-style flood fill: does not reuse the RTL validator.
    task reference_check;
        input [255:0] bits;
        integer x,y,a,n,rd,wr,total,i,min_total,max_total,expect_p1,expect_p2;
        integer q[0:255];
        reg [255:0] seen;
        begin
            total=0; min_total=100; max_total=-1; expect_p1=0; expect_p2=0;
            for(y=0;y<16;y=y+1) for(x=0;x<16;x=x+1) begin
                a=y*16+x;
                if((x==0 || x==15 || y==0 || y==15) && bits[a]!==1'b1)
                    fail("open boundary in generated map");
                if(bits[a]===1'b0) begin
                    total=total+1;
                    if(x+y<min_total) begin min_total=x+y; expect_p1=a; end
                    if(x+y>max_total) begin max_total=x+y; expect_p2=a; end
                end else if(bits[a]!==1'b1) fail("unknown map tile");
            end
            if(p1!==expect_p1[7:0] || p2!==expect_p2[7:0] || p1==p2)
                fail("incorrect extreme-sum spawns");
            seen=0; seen[expect_p1]=1; q[0]=expect_p1; rd=0; wr=1;
            while(rd<wr) begin
                a=q[rd]; rd=rd+1;
                for(i=0;i<4;i=i+1) begin
                    n=-1;
                    case(i)
                        0: if(a%16>0) n=a-1;
                        1: if(a%16<15) n=a+1;
                        2: if(a/16>0) n=a-16;
                        3: if(a/16<15) n=a+16;
                    endcase
                    if(n>=0 && n<256) if(!bits[n] && !seen[n]) begin
                        seen[n]=1; q[wr]=n; wr=wr+1;
                    end
                end
            end
            if(wr!=total) fail("reference flood fill found disconnected floor");
        end
    endtask
    task generate_seed;
        input [15:0] s;
        begin
            @(negedge clk); seed_in=s; regenerate=1;
            @(negedge clk); regenerate=0;
            wait_map;
            reference_check(map_bits);
        end
    endtask
    task validate_injected;
        input [2:0] expected_error;
        integer count;
        reg timeout_seen;
        begin
            @(negedge clk); val_start=1;
            @(negedge clk); val_start=0;
            count=0; timeout_seen=0;
            while(!val_done && count<4098) begin
                @(posedge clk); #1; count=count+1;
                if(timeout_done) begin
                    timeout_seen=1;
                    if(timeout_error!=4 || timeout_pass) fail("watchdog did not report TIMEOUT");
                end
            end
            if(!timeout_seen) fail("short watchdog completion missing");
            if(!val_done || val_error!==expected_error || val_pass!==(expected_error==0))
                fail("injected-map validator returned wrong result");
        end
    endtask
    integer x,y;
    initial begin
        max_cycles=0; last_published={256{1'b1}}; injected_map={256{1'b1}};
        repeat(5) @(negedge clk); rst=0;
        wait_map; reference_check(map_bits);
        generate_seed(16'h1234); first_map=map_bits;
        generate_seed(16'h1234);
        if(map_bits!==first_map) fail("same seed did not reproduce map");
        // Fixed deterministic pseudorandom stimulus: repeatable regression.
        random_seed=16'hACE1;
        for(k=0;k<50;k=k+1) begin
            random_seed=(random_seed>>1) ^ (random_seed[0] ? 16'hB400 : 16'h0000);
            generate_seed(random_seed);
            if(STAGE==1 && map_bits!==first_map) fail("fixed map changed with seed");
        end
        generate_seed(0);
        if(active_seed!=1) fail("zero seed was not sanitised");
        // Reset during the tile-writing phase, then check boot replay.
        @(negedge clk); regenerate=1; seed_in=16'hCAFE;
        @(negedge clk); regenerate=0;
        repeat(80) @(negedge clk);
        rst=1; repeat(4) @(negedge clk); rst=0;
        last_published={256{1'b1}};
        wait_map; reference_check(map_bits);
        base_map=map_bits;
        generate_seed(16'h1ACE);
        if(map_bits!==base_map) fail("reset did not restart the boot seed cleanly");
        // All interior floor is an independently constructed valid case.
        injected_map={256{1'b1}};
        for(y=1;y<15;y=y+1) for(x=1;x<15;x=x+1) injected_map[y*16+x]=0;
        base_map=injected_map;
        validate_injected(0);
        if(floors!=196 || reached!=196) fail("BFS counters wrong on open interior");
        // Isolate floor (3,3) without changing boundary or extreme-sum starts.
        injected_map[3*16+2]=1; injected_map[3*16+4]=1;
        injected_map[2*16+3]=1; injected_map[4*16+3]=1;
        validate_injected(2);
        injected_map=base_map; injected_map[0*16+7]=0;
        validate_injected(1);
        injected_map={256{1'b1}}; validate_injected(3);
        // Only one floor tile is also an invalid pair of spawns.
        injected_map[17]=0; validate_injected(3);
        cycles=0;
        while(retry_busy && cycles<41000) begin @(posedge clk); #1; cycles=cycles+1; end
        if(retry_busy || retry_ready || retry_error!=4 || retry_total!=4)
            fail("retry exhaustion did not hold terminal TIMEOUT after four retries");
        if(STAGE!=1 && (deepest<3 || two_doors==0)) fail("missing depth-three split or second doorway coverage");
        if(STAGE!=1) $display("PASS coverage stage %0d: split depth=%0d, two-door draw clocks=%0d, max stack=%0d",STAGE,deepest,two_doors,max_stack);
        if(failures==0) $display("PASS stage %0d: replay, 50 seeds, independent BFS, faults, reset, retries; max cycles=%0d",STAGE,max_cycles);
        else $display("FAIL stage %0d total=%0d",STAGE,failures);
        $finish;
    end
    initial begin #100000000; fail("global simulation timeout"); $finish; end
endmodule
