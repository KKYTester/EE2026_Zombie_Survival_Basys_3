`timescale 1ns / 1ps
module tb_uart;
    localparam BIT_NS = 8640;

    reg clk = 0, rst = 1, start = 0;
    reg [7:0] tx_data = 0;
    reg manual = 0, manual_line = 1;
    wire tick_16x, tx, busy, valid, frame_error;
    wire [7:0] rx_data;
    wire line = manual ? manual_line : tx;
    always #5 clk = ~clk;

    baud_gen baud(.clk(clk), .rst(rst), .tick_16x(tick_16x));
    uart_tx dut_tx(.clk(clk), .rst(rst), .tick_16x(tick_16x), .data(tx_data),
        .start(start), .tx(tx), .busy(busy));
    uart_rx dut_rx(.clk(clk), .rst(rst), .tick_16x(tick_16x), .rx(line),
        .data(rx_data), .valid(valid), .frame_error(frame_error));

    integer errors = 0, valid_count = 0, frame_count = 0, i;
    time last_edge;
    reg [7:0] last_rx = 0;
    always @(posedge clk) begin
        if (valid) begin valid_count = valid_count + 1; last_rx = rx_data; end
        if (frame_error) frame_count = frame_count + 1;
    end

    task fail(input [8*40-1:0] message);
        begin errors = errors + 1; $display("FAIL: %0s at %0t", message, $time); end
    endtask

    task send(input [7:0] value);
        begin
            while (busy) @(negedge clk);
            @(negedge clk) begin tx_data = value; start = 1; end
            @(negedge clk) start = 0;
        end
    endtask

    task drive(input [7:0] value, input integer bit_ns);
        integer b;
        begin
            manual_line = 0; #(bit_ns);
            for (b = 0; b < 8; b = b + 1) begin manual_line = value[b]; #(bit_ns); end
            manual_line = 1; #(bit_ns);
        end
    endtask

    task check_counts(input integer want_valid, input integer want_frame);
        begin
            if (valid_count != want_valid) fail("valid count");
            if (frame_count != want_frame) fail("frame error count");
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (5) @(negedge clk);
        if (tx !== 1'b1) fail("line must idle high");

        send(8'h55);
        @(negedge tx) last_edge = $time;
        for (i = 0; i < 9; i = i + 1) begin
            if (i % 2 == 0) @(posedge tx); else @(negedge tx);
            if ($time - last_edge != BIT_NS) fail("bit length");
            last_edge = $time;
        end
        wait (!busy);
        if (valid_count != 1 || last_rx != 8'h55) fail("0x55 round trip");

        for (i = 0; i < 256; i = i + 1) begin
            send(i[7:0]);
            wait (valid_count == i + 2);
            if (last_rx != i[7:0]) fail("byte round trip");
        end
        check_counts(257, 0);
        wait (!busy);

        manual = 1;
        manual_line = 0; #(BIT_NS/4); manual_line = 1; #(BIT_NS*12);
        check_counts(257, 0);

        manual_line = 0; #(BIT_NS*30); manual_line = 1; #(BIT_NS*2);
        check_counts(257, 1);

        drive(8'hC3, BIT_NS); #(BIT_NS);
        if (last_rx != 8'hC3) fail("byte after framing error");
        check_counts(258, 1);

        drive(8'hA6, BIT_NS*103/100); #(BIT_NS);
        if (last_rx != 8'hA6) fail("3% slow sender");
        drive(8'h59, BIT_NS*97/100); #(BIT_NS);
        if (last_rx != 8'h59) fail("3% fast sender");
        check_counts(260, 1);

        if (errors == 0) $display("TB_UART: ALL PASSED");
        else $display("TB_UART: %0d FAILED", errors);
        $finish;
    end

    initial begin
        #100000000;
        $display("TB_UART: FAILED, timed out");
        $finish;
    end
endmodule
