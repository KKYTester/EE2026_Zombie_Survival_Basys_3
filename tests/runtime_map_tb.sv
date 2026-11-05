`timescale 1ns / 1ps
module runtime_map_tb;
    reg clk=0, reset=1, tick=0, forward=0, event_in=0;
    always #5 clk=~clk;
    reg [255:0] map_bits=0;
    reg [31:0] spawn_x=32'd14336, spawn_y=32'd14336; // (3.5,3.5)
    reg signed [8:0] mouse_x_delta=0;
    wire [31:0] x,y,theta;
    Player_Controller #(.USE_RUNTIME_MAP(1),.DEBOUNCE_CYCLES(2),.START_ANGLE(0)) player (
        .clk(clk),.reset(reset),.game_tick(tick),.map_bits(map_bits),.spawn_x(spawn_x),.spawn_y(spawn_y),
        .btnU(forward),.btnD(1'b0),.btnL(1'b0),.btnR(1'b0),
        .mouse_x_delta(mouse_x_delta),.mouse_event(event_in),.x_coord(x),.y_coord(y),.theta(theta));
    reg swap=0;
    reg [12:0] pixel_index=32*96+48;
    wire [15:0] pixel_data;
    wire [9:0] column_depth;
    Map_Renderer #(.USE_RUNTIME_MAP(1)) renderer (
        .clk(clk),.reset(reset),.map_bits(map_bits),.x_coord(x),.y_coord(y),.theta(theta),
        .game_tick(),.display_clk(clk),.frame_begin(swap),.pixel_index(pixel_index),
        .pixel_data(pixel_data),.column_depth(column_depth));
    task update_player;
        @(negedge clk); tick=1;
        @(negedge clk); tick=0;
        repeat(6) @(negedge clk);
    endtask
    integer row,col;
    initial begin
        for(row=0;row<16;row++) for(col=0;col<16;col++)
            if(row==0 || row==15 || col==0 || col==15 || row==5) map_bits[row*16+col]=1;
        repeat(4) @(negedge clk); reset=0;
        wait(renderer.state==renderer.WAIT_RAY);
        // Mutate the external map while scanning. The complete first scan
        // must still use its snapshot of the wall at y=5.
        @(negedge clk); map_bits[5*16 +:16]=16'h8001;
        wait(renderer.state==renderer.WAIT_SWAP);
        if(renderer.depths[144]<47 || renderer.depths[144]>49)
            $fatal(1,"Renderer mixed maps within one scan");
        swap=1; repeat(6) @(negedge clk); swap=0;
        if(column_depth<47 || column_depth>49 || pixel_data!==16'hbdf7)
            $fatal(1,"Runtime map not rendered");
        // Render again after the wall was removed; new depth must be larger.
        wait(renderer.state==renderer.IDLE);
        @(negedge clk); force renderer.game_tick=1;
        @(negedge clk); force renderer.game_tick=0;
        wait(renderer.state==renderer.WAIT_SWAP);
        swap=1; repeat(6) @(negedge clk); swap=0;
        if(column_depth<360 || column_depth>370) $fatal(1,"New map not snapshotted");
        // Restore runtime wall and walk into it, then remove it without a reset.
        map_bits[5*16 +:16]=16'hffff;
        forward=1; repeat(10) @(negedge clk);
        repeat(30) update_player;
        if(y>19968 || y<19456 || x!==spawn_x) $fatal(1,"Runtime collision failed y=%0d",y);
        map_bits[5*16 +:16]=16'h8001;
        repeat(12) update_player;
        if(y<=24576) $fatal(1,"Runtime collision kept old map");
        // Dynamic reset spawn and out-of-map boundary checks.
        reset=1; spawn_x=6144; spawn_y=59392;
        repeat(4) @(negedge clk); reset=0;
        if(x!==6144 || y!==59392 || theta!==0) $fatal(1,"Dynamic spawn reset");
        repeat(20) update_player;
        if(y>60928) $fatal(1,"Boundary wall escaped");
        $display("PASS: runtime map snapshots, new-map publication, dynamic spawn, collision and boundaries");
        $finish;
    end
    initial begin #3000000; $fatal(1,"Runtime map timeout"); end
endmodule
