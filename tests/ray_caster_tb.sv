`timescale 1ns / 1ps
`include "Game_Config.vh"
module ray_caster_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, start=0;
    reg signed [17:0] x, y;
    reg [9:0] angle;
    wire busy, done, hit;
    wire [6:0] height;
    wire [9:0] distance_steps;
    Ray_Caster dut (.clk(clk), .reset(reset), .start(start), .player_x(x), .player_y(y),
        .angle(angle), .busy(busy), .done(done), .hit(hit), .height(height), .distance_steps(distance_steps));
    wire obstacle_done, obstacle_hit, short_done;
    wire [9:0] obstacle_distance, short_distance;
    wire [6:0] obstacle_height, short_height;
    // Extra wall at (8,9) blocks a northward ray before the map's north block.
    Ray_Caster #(.MAP(`GAME_MAP | (256'b1 << 152))) obstacle (
        .clk(clk), .reset(reset), .start(start), .player_x(x), .player_y(y), .angle(angle),
        .busy(), .done(obstacle_done), .hit(obstacle_hit),
        .height(obstacle_height), .distance_steps(obstacle_distance));
    Ray_Caster #(.MAP(256'd0), .MAX_STEPS(10'd4)) short_ray (
        .clk(clk), .reset(reset), .start(start), .player_x(x), .player_y(y), .angle(angle),
        .busy(), .done(short_done), .hit(), .height(short_height), .distance_steps(short_distance));
    integer fd, count=0, parsed, cycles;
    reg [9:0] expected_distance;
    reg [6:0] expected_height;
    task tick;
        begin @(posedge clk); #1; end
    endtask
    initial begin
        x=34816; y=34816; angle=0;
        repeat (3) tick;
        @(negedge clk); reset=0; start=1;
        tick;
        @(negedge clk); start=0;
        // MAX_STEPS termination independent of boundary walls.
        wait(short_done); #1;
        if (short_distance !== 1023 || short_height !== 0) $fatal(1,"Step cap failed");
        wait(obstacle_done); #1;
        if (!obstacle_hit || obstacle_distance !== 16 || obstacle_height !== 64)
            $fatal(1,"Interior wall did not occlude outer wall");
        wait(done); tick;
        // Reset must abort an in-flight ray, irrespective of start.
        @(negedge clk); start=1;
        tick;
        @(negedge clk); reset=1;
        tick;
        if (busy || done || hit || height !== 0 || distance_steps !== 1023)
            $fatal(1,"Mid-ray reset failed");
        @(negedge clk); reset=0; start=0;

        fd=$fopen("ray_vectors.txt","r");
        if (!fd) $fatal(1,"Generate ray_vectors.txt first");
        while (!$feof(fd)) begin
            @(negedge clk);
            parsed=$fscanf(fd,"%h %h %h %h %h\n",x,y,angle,expected_distance,expected_height);
            if (parsed != 5) $fatal(1,"Malformed vector");
            start=1;
            tick;
            if (!busy) $fatal(1,"Start not accepted");
            @(negedge clk); start=0;
            // Inputs changing after start must not change the captured ray.
            x=0; y=0; angle=0;
            cycles=0;
            while (!done && cycles<780) begin tick; cycles=cycles+1; end
            if (!done || busy) $fatal(1,"Ray failed to terminate, vector %0d",count);
            if (distance_steps !== expected_distance || height !== expected_height ||
                hit !== (expected_distance != 1023))
                $fatal(1,"Vector %0d: distance %0d/%0d height %0d/%0d",count,
                    distance_steps,expected_distance,height,expected_height);
            tick;
            if (done) $fatal(1,"done was not a single-cycle pulse");
            count=count+1;
        end
        $fclose(fd);
        $display("PASS: %0d rays; full angle wrap; edges; zero distance/components; snapshot; obstacle; cap; reset",count);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Ray simulation timeout"); end
endmodule
