`timescale 1ns / 1ps
module mouse_top_tb;
    reg clk=0;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    wire [15:0] led;
    My_Top_Module board (.clk(clk), .JB(), .btnU(1'b0), .btnL(1'b0),
        .btnR(1'b0), .btnD(1'b0), .ps2_clk(ps2_clk), .ps2_data(ps2_data), .led(led));
    // Exercise integration at the synchronous MouseCtl output boundary.
    // The real VHDL driver is compiled/elaborated; this is not a PS/2 device model.
    initial begin
        wait(!board.reset);
        @(negedge clk);
        force board.mouse_left=1; force board.mouse_middle=0; force board.mouse_right=0;
        #1; if(led!==16'h8000) $fatal(1,"Left click LED");
        force board.mouse_left=0; force board.mouse_middle=1;
        #1; if(led!==16'h4000) $fatal(1,"Middle click LED");
        force board.mouse_middle=0; force board.mouse_right=1;
        #1; if(led!==16'h2000) $fatal(1,"Right click LED");
        force board.mouse_left=1; force board.mouse_middle=1;
        #1; if(led!==16'he000) $fatal(1,"Simultaneous clicks");
        force board.mouse_x=12'd256; force board.mouse_event=1;
        @(negedge clk); force board.mouse_event=0;
        // Accelerate only the update pulse; input/output wiring remains real.
        force board.game_tick=1;
        @(negedge clk); force board.game_tick=0;
        repeat(6) @(negedge clk);
        if(board.player_angle!==384 || board.player_x!==34816 || board.player_y!==34816)
            $fatal(1,"Mouse-to-player wiring");
        wait(board.u_Map_Renderer.state==board.u_Map_Renderer.WAIT_SWAP);
        force board.frame_begin=1;
        wait(board.u_Map_Renderer.state==board.u_Map_Renderer.IDLE);
        @(negedge clk);
        force board.game_tick=1;
        @(negedge clk); force board.game_tick=0;
        wait(board.u_Map_Renderer.state==board.u_Map_Renderer.WAIT_RAY);
        if(board.u_Map_Renderer.frame_angle!==384)
            $fatal(1,"Renderer did not snapshot controlled angle");
        $display("PASS: mixed-language top; mouse click LEDs; mouse-to-player orientation; renderer viewpoint wiring");
        $finish;
    end
    initial begin #2000000; $fatal(1,"Mouse top timeout"); end
endmodule
