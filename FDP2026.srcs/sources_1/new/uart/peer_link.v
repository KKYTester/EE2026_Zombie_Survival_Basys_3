`timescale 1ns / 1ps
// Symmetric Basys-to-Basys link: no fixed host and no client. Each board sends
// its STATUS_BYTES status word every PERIOD_CYCLES and receives the other
// board's. While send_extra is high, a second packet carrying EXTRA_BYTES
// (the zombie list of the board running a shared game) follows each status.
// link_up stays high while new STATUS packets arrive (TIMEOUT_CYCLES).
//
// Packets (packet_tx/packet_rx framing: A5, type, length, payload, CRC16):
//   30 STATUS: sequence byte, STATUS_BYTES status bytes
//   31 EXTRA:  matching STATUS sequence byte, EXTRA_BYTES bytes
// The meaning of both words belongs to the top level.
module peer_link #(
    parameter integer CLK_FREQ = 100_000_000,
    parameter integer PERIOD_CYCLES = 2_000_000,   // 20 ms
    parameter integer TIMEOUT_CYCLES = 50_000_000, // 500 ms
    parameter integer STATUS_BYTES = 8,            // 1..31
    parameter integer EXTRA_BYTES = 1              // 1..31
)(
    input wire clk, input wire rst,
    input wire uart_rx_pin, output wire uart_tx_pin,
    input wire [8*STATUS_BYTES-1:0] local_status,
    input wire send_extra,
    input wire [8*EXTRA_BYTES-1:0] local_extra,
    output reg [8*STATUS_BYTES-1:0] peer_status,
    output reg peer_status_valid,                  // one clock per received status
    output reg [8*EXTRA_BYTES-1:0] peer_extra,
    output reg peer_extra_valid,                   // one clock per received extra word
    output reg link_up,
    output wire packet_error, output wire frame_error,
    output reg [7:0] packet_error_count, output reg [7:0] sequence_gap_count
);
    localparam [7:0] PKT_STATUS = 8'h30;
    localparam [7:0] PKT_EXTRA = 8'h31;
    localparam integer MAX_PAYLOAD = (STATUS_BYTES>EXTRA_BYTES ? STATUS_BYTES : EXTRA_BYTES)+1;
    localparam [7:0] STATUS_LEN = STATUS_BYTES + 1;
    localparam [7:0] EXTRA_LEN = EXTRA_BYTES + 1;

    wire tick_16x, rx_valid, rx_frame_error, pkt_busy, pkt_tx_start, tx_busy;
    wire pkt_valid, pkt_error;
    wire [7:0] rx_data, pkt_tx_data, pkt_type, pkt_len;
    wire [8*MAX_PAYLOAD-1:0] pkt_payload;

    baud_gen #(.CLK_FREQ(CLK_FREQ)) baud(.clk(clk), .rst(rst), .tick_16x(tick_16x));
    uart_tx transmitter(.clk(clk), .rst(rst), .tick_16x(tick_16x),
        .data(pkt_tx_data), .start(pkt_tx_start), .tx(uart_tx_pin), .busy(tx_busy));
    uart_rx receiver(.clk(clk), .rst(rst), .tick_16x(tick_16x), .rx(uart_rx_pin),
        .data(rx_data), .valid(rx_valid), .frame_error(rx_frame_error));
    packet_rx #(.MAX_PAYLOAD(MAX_PAYLOAD),.USE_CRC16(1)) packet_receiver(
        .clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_frame_error(rx_frame_error), .pkt_valid(pkt_valid), .pkt_error(pkt_error),
        .pkt_type(pkt_type), .pkt_len(pkt_len), .pkt_payload(pkt_payload));

    reg [7:0] tx_sequence;
    reg [7:0] extra_sequence, received_sequence;
    reg received_status, received_extra;
    reg [8*EXTRA_BYTES-1:0] extra_snapshot;
    reg [31:0] period_timer, timeout_timer;
    reg status_due, extra_due;
    // Status first; the extra word goes out once the status packet has started.
    wire send_status = status_due;
    wire send_extra_now = !status_due && extra_due;
    reg [8*MAX_PAYLOAD-1:0] tx_payload;
    always @* begin
        tx_payload = 0;
        tx_payload[7:0] = send_status ? tx_sequence : extra_sequence;
        if (send_status) tx_payload[8*STATUS_BYTES+7:8] = local_status;
        else tx_payload[8*EXTRA_BYTES+7:8] = extra_snapshot;
    end
    wire tx_start_packet = (send_status || send_extra_now) && !pkt_busy;
    packet_tx #(.MAX_PAYLOAD(MAX_PAYLOAD),.USE_CRC16(1)) packet_sender(
        .clk(clk), .rst(rst), .send(tx_start_packet),
        .pkt_type(send_status ? PKT_STATUS : PKT_EXTRA),
        .pkt_len(send_status ? STATUS_LEN : EXTRA_LEN), .pkt_payload(tx_payload),
        .corrupt_checksum(1'b0), .busy(pkt_busy),
        .tx_start(pkt_tx_start), .tx_data(pkt_tx_data), .tx_busy(tx_busy));
    assign packet_error = pkt_error;
    assign frame_error = rx_frame_error;

    wire got_status = pkt_valid && pkt_type == PKT_STATUS && pkt_len == STATUS_LEN;
    wire got_extra = pkt_valid && pkt_type == PKT_EXTRA && pkt_len == EXTRA_LEN;
    wire new_status = got_status && (!received_status || pkt_payload[7:0]!=received_sequence);
    // EXTRA belongs to the immediately preceding STATUS snapshot. Never publish
    // an orphan, duplicate or mismatched bank (including across a peer reset).
    wire new_extra = got_extra && received_status && !received_extra &&
                     pkt_payload[7:0]==received_sequence;
    always @(posedge clk) begin
        peer_status_valid <= 1'b0;
        peer_extra_valid <= 1'b0;
        if (rst) begin
            tx_sequence <= 0; period_timer <= 0; timeout_timer <= 0;
            status_due <= 0; extra_due <= 0; link_up <= 0;
            peer_status <= 0; peer_extra <= 0;
            extra_sequence<=0; extra_snapshot<=0; received_sequence<=0;
            received_status<=0; received_extra<=0;
            packet_error_count<=0; sequence_gap_count<=0;
        end else begin
            if((pkt_error || rx_frame_error) && packet_error_count!=8'hff)
                packet_error_count<=packet_error_count+1'b1;
            if (tx_start_packet) begin
                if (send_status) begin
                    tx_sequence<=tx_sequence+1'b1;
                    extra_sequence<=tx_sequence; extra_snapshot<=local_extra;
                    status_due<=0; extra_due<=send_extra;
                end else extra_due <= 0;
            end
            if (period_timer == PERIOD_CYCLES-1) begin
                period_timer <= 0;
                status_due <= 1;
            end else period_timer <= period_timer + 1'b1;

            if (new_status) begin
                peer_status <= pkt_payload[8*STATUS_BYTES+7:8];
                peer_status_valid <= 1;
                received_sequence<=pkt_payload[7:0]; received_status<=1; received_extra<=0;
                if(received_status && pkt_payload[7:0]!=received_sequence+8'd1 && sequence_gap_count!=8'hff)
                    sequence_gap_count<=sequence_gap_count+1'b1;
            end
            if (new_extra) begin
                peer_extra <= pkt_payload[8*EXTRA_BYTES+7:8];
                peer_extra_valid <= 1;
                received_extra<=1;
            end
            if (new_status) begin
                link_up <= 1;
                timeout_timer <= 0;
            end else if (link_up) begin
                if (timeout_timer == TIMEOUT_CYCLES-1) begin
                    timeout_timer <= 0;
                    link_up <= 0;
                    received_status<=0; received_extra<=0; peer_extra<=0;
                end else timeout_timer <= timeout_timer + 1'b1;
            end else timeout_timer <= 0;
        end
    end
endmodule
