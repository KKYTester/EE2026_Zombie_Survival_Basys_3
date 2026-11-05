`timescale 1ns / 1ps
module mouse_pointer_tb;
    reg clk=0, reset=1, mouse_event=0;
    always #5 clk=~clk;
    reg signed [8:0] x_delta=0, y_delta=0;
    wire [6:0] x;
    wire [5:0] y;
    Mouse_Pointer dut(.*);
    task packet(input integer dx, dy);
        @(negedge clk); x_delta=dx; y_delta=dy; mouse_event=1;
        @(negedge clk); mouse_event=0;
    endtask
    initial begin
        repeat(3) @(negedge clk); reset=0;
        if(x!==48 || y!==40) $fatal(1,"Pointer reset");
        packet(0,10);
        if(x!==48 || y!==30) $fatal(1,"Menu option pointer");
        packet(-256,255);
        if(x!==0 || y!==0) $fatal(1,"Pointer lower clamp");
        packet(255,-256);
        if(x!==95 || y!==63) $fatal(1,"Pointer upper clamp");
        packet(-1,1);
        repeat(10) @(negedge clk);
        if(x!==94 || y!==62) $fatal(1,"Held delta replayed");
        reset=1; @(negedge clk);
        if(x!==48 || y!==40) $fatal(1,"Pointer restart");
        $display("PASS: signed menu pointer, both clamps, packet gating, reset");
        $finish;
    end
endmodule
