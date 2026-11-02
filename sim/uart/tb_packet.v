`timescale 1ns / 1ps
module tb_packet;
    localparam MAX = 8;
    localparam BIT_NS = 8640;
    localparam TIMEOUT = 20000;

    reg clk = 0, rst = 1;
    reg send = 0, corrupt = 0, raw_start = 0, hold_low = 0;
    reg [7:0] send_type = 0, send_len = 0, raw_data = 0;
    reg [8*MAX-1:0] send_payload = 0;
    wire tick_16x, tx, tx_busy, pkt_busy, pkt_start, rx_valid, rx_frame;
    wire pkt_valid, pkt_error;
    wire [7:0] pkt_data, rx_data, got_type, got_len;
    wire [8*MAX-1:0] got_payload;
    wire line = tx && !hold_low;
    always #5 clk = ~clk;

    baud_gen baud(.clk(clk), .rst(rst), .tick_16x(tick_16x));
    uart_tx u_tx(.clk(clk), .rst(rst), .tick_16x(tick_16x),
        .data(raw_start ? raw_data : pkt_data), .start(raw_start || pkt_start),
        .tx(tx), .busy(tx_busy));
    uart_rx u_rx(.clk(clk), .rst(rst), .tick_16x(tick_16x), .rx(line),
        .data(rx_data), .valid(rx_valid), .frame_error(rx_frame));
    packet_tx #(.MAX_PAYLOAD(MAX)) p_tx(.clk(clk), .rst(rst), .send(send),
        .pkt_type(send_type), .pkt_len(send_len), .pkt_payload(send_payload),
        .corrupt_checksum(corrupt), .busy(pkt_busy),
        .tx_start(pkt_start), .tx_data(pkt_data), .tx_busy(tx_busy));
    packet_rx #(.MAX_PAYLOAD(MAX), .TIMEOUT_CYCLES(TIMEOUT)) p_rx(.clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_error(rx_frame),
        .pkt_valid(pkt_valid), .pkt_error(pkt_error), .pkt_type(got_type),
        .pkt_len(got_len), .pkt_payload(got_payload));

    integer errors = 0, good = 0, bad = 0;
    always @(posedge clk) begin
        if (pkt_valid) good = good + 1;
        if (pkt_error) bad = bad + 1;
    end

    task fail(input [8*40-1:0] message);
        begin errors = errors + 1; $display("FAIL: %0s at %0t", message, $time); end
    endtask

    task packet(input [7:0] p_type, input [7:0] len, input [8*MAX-1:0] payload, input bad_sum);
        begin
            while (pkt_busy) @(negedge clk);
            @(negedge clk) begin
                send_type = p_type; send_len = len; send_payload = payload;
                corrupt = bad_sum; send = 1;
            end
            @(negedge clk) send = 0;
            @(negedge clk);
            while (pkt_busy) @(negedge clk);
        end
    endtask

    task raw(input [7:0] value);
        begin
            while (tx_busy) @(negedge clk);
            @(negedge clk) begin raw_data = value; raw_start = 1; end
            @(negedge clk) raw_start = 0;
            @(negedge clk);
            while (tx_busy) @(negedge clk);
        end
    endtask

    task check(input integer want_good, input integer want_bad);
        begin
            #(BIT_NS);
            if (good != want_good) fail("good count");
            if (bad != want_bad) fail("bad count");
        end
    endtask

    task check_data(input [7:0] p_type, input [7:0] len, input [8*MAX-1:0] payload);
        begin
            if (got_type != p_type) fail("type");
            if (got_len != len) fail("length");
            if (got_payload != payload) fail("payload");
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (5) @(negedge clk);

        packet(8'h01, 8'd4, 64'h3C5AA512, 0); check(1, 0);
        check_data(8'h01, 8'd4, 64'h3C5AA512);
        packet(8'h02, 8'd0, 64'h0, 0); check(2, 0);
        check_data(8'h02, 8'd0, 64'h0);
        packet(8'hA5, 8'd8, 64'h8877665544332211, 0); check(3, 0);
        check_data(8'hA5, 8'd8, 64'h8877665544332211);

        packet(8'h03, 8'd1, 64'hFFFFFFFFFFFFFF7E, 0); check(4, 0);
        check_data(8'h03, 8'd1, 64'h7E);

        packet(8'h04, 8'd2, 64'hBEEF, 1); check(4, 1);
        check_data(8'h03, 8'd1, 64'h7E);

        raw(8'hA5); raw(8'h04); raw(8'h01); raw(8'h12); raw(8'h16); check(4, 2);
        check_data(8'h03, 8'd1, 64'h7E);

        raw(8'h00); raw(8'hFF); raw(8'h12);
        packet(8'h05, 8'd1, 64'h99, 0); check(5, 2);
        check_data(8'h05, 8'd1, 64'h99);

        raw(8'hA5); raw(8'h06); raw(8'h04); raw(8'h11);
        #(TIMEOUT*10 + BIT_NS); check(5, 3);
        packet(8'h07, 8'd1, 64'h42, 0); check(6, 3);
        check_data(8'h07, 8'd1, 64'h42);

        raw(8'hA5); raw(8'h08); raw(8'd9); check(6, 4);
        packet(8'h09, 8'd1, 64'h43, 0); check(7, 4);

        raw(8'hA5); raw(8'h0A);
        hold_low = 1; #(BIT_NS*12); hold_low = 0; #(BIT_NS); check(7, 5);
        packet(8'h0B, 8'd1, 64'h44, 0); check(8, 5);
        check_data(8'h0B, 8'd1, 64'h44);

        packet(8'h0C, 8'd3, 64'h030201, 0);
        packet(8'h0D, 8'd3, 64'h060504, 0); check(10, 5);
        check_data(8'h0D, 8'd3, 64'h060504);

        if (errors == 0) $display("TB_PACKET: ALL PASSED");
        else $display("TB_PACKET: %0d FAILED", errors);
        $finish;
    end

    initial begin
        #100000000;
        $display("TB_PACKET: FAILED, timed out");
        $finish;
    end
endmodule
