`timescale 1ns / 1ps
module tb_uart_test_top;
    localparam BIT_NS = 8640;

    reg clk = 0, btnC = 0, btnU = 0, jumper = 1;
    reg [15:0] sw = 0;
    wire [15:0] led;
    wire [6:0] seg;
    wire [3:0] an;
    wire dp, tx;
    always #5 clk = ~clk;

    uart_test_top #(.DEBOUNCE_CYCLES(100)) dut(.clk(clk), .btnC(btnC), .btnU(btnU),
        .sw(sw), .led(led), .seg(seg), .dp(dp), .an(an),
        .uart_tx_pin(tx), .uart_rx_pin(jumper ? tx : 1'b1));

    integer errors = 0;
    task fail(input [8*40-1:0] message);
        begin errors = errors + 1; $display("FAIL: %0s at %0t", message, $time); end
    endtask

    task press;
        begin
            btnC = 1; #(5000); btnC = 0; #(5000);
            #(BIT_NS*80);
        end
    endtask

    task check_display(input [15:0] want);
        begin
            if (dut.display_value != want) begin
                fail("display value");
                $display("  got %h, wanted %h", dut.display_value, want);
            end
        end
    endtask

    initial begin
        #1000;

        sw = 16'h003C;
        btnC = 1; #(BIT_NS*40); btnC = 0; #(BIT_NS*20);
        if (led[7:0] != 8'h3C) fail("raw LEDs");
        check_display(16'h0001);

        sw = 16'h00A5; press;
        if (led[7:0] != 8'hA5) fail("raw A5 LEDs");
        check_display(16'h0002);

        jumper = 0;
        sw = 16'h00FF; press;
        if (led[7:0] != 8'hA5) fail("LEDs changed without jumper");
        if (led[8]) fail("framing error without jumper");
        check_display(16'h0002);
        jumper = 1;
        #(BIT_NS*2);

        wait (an == 4'b1110); #1;
        if (seg != 7'b0100100) fail("7-seg digit");

        sw = 16'h8077; press;
        if (led[7:0] != 8'h77) fail("packet LEDs");
        if (!led[15]) fail("packet mode LED");
        check_display(16'h0100);

        sw = 16'h80A5; press;
        if (led[7:0] != 8'hA5) fail("packet A5 LEDs");
        check_display(16'h0200);

        sw = 16'hC011; press;
        if (led[7:0] != 8'hA5) fail("bad packet changed LEDs");
        check_display(16'h0201);

        sw = 16'h8022; press;
        check_display(16'h0301);
        btnU = 1; #1000; btnU = 0; #1000;
        check_display(16'h0000);
        if (led[7:0] != 8'h00) fail("reset LEDs");

        if (errors == 0) $display("TB_UART_TEST_TOP: ALL PASSED");
        else $display("TB_UART_TEST_TOP: %0d FAILED", errors);
        $finish;
    end

    initial begin
        #100000000;
        $display("TB_UART_TEST_TOP: FAILED, timed out");
        $finish;
    end
endmodule
