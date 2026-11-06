`timescale 1ns / 1ps
// Symmetric Basys-to-Basys link: no host and no client. Each board sends its
// STATUS_BYTES status word every PERIOD_CYCLES and receives the other board's.
// link_up stays high while valid packets keep arriving (TIMEOUT_CYCLES).
//
// Packet: A5, type 30 (STATUS), length 1+STATUS_BYTES, sequence byte, status
// bytes, checksum (packet_tx/packet_rx framing). Meaning of the status word
// belongs to the top level.
module peer_link #(
    parameter integer CLK_FREQ = 100_000_000,
    parameter integer PERIOD_CYCLES = 2_000_000,   // 20 ms
    parameter integer TIMEOUT_CYCLES = 50_000_000, // 500 ms
    parameter integer STATUS_BYTES = 8             // 1..15
)(
    input wire clk, input wire rst,
    input wire uart_rx_pin, output wire uart_tx_pin,
    input wire [8*STATUS_BYTES-1:0] local_status,
    output reg [8*STATUS_BYTES-1:0] peer_status,
    output reg peer_status_valid,                  // one clock per received packet
    output reg link_up,
    output wire packet_error, output wire frame_error
);
    localparam [7:0] PKT_STATUS = 8'h30;
    localparam integer MAX_PAYLOAD = 16;
    localparam [7:0] PKT_LEN = STATUS_BYTES + 1;

    wire tick_16x, rx_valid, rx_frame_error, pkt_busy, pkt_tx_start, tx_busy;
    wire pkt_valid, pkt_error;
    wire [7:0] rx_data, pkt_tx_data, pkt_type, pkt_len;
    wire [8*MAX_PAYLOAD-1:0] pkt_payload;

    baud_gen #(.CLK_FREQ(CLK_FREQ)) baud(.clk(clk), .rst(rst), .tick_16x(tick_16x));
    uart_tx transmitter(.clk(clk), .rst(rst), .tick_16x(tick_16x),
        .data(pkt_tx_data), .start(pkt_tx_start), .tx(uart_tx_pin), .busy(tx_busy));
    uart_rx receiver(.clk(clk), .rst(rst), .tick_16x(tick_16x), .rx(uart_rx_pin),
        .data(rx_data), .valid(rx_valid), .frame_error(rx_frame_error));
    packet_rx #(.MAX_PAYLOAD(MAX_PAYLOAD)) packet_receiver(
        .clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_frame_error(rx_frame_error), .pkt_valid(pkt_valid), .pkt_error(pkt_error),
        .pkt_type(pkt_type), .pkt_len(pkt_len), .pkt_payload(pkt_payload));

    reg [7:0] tx_sequence;
    reg [31:0] period_timer, timeout_timer;
    reg send_due;
    reg [8*MAX_PAYLOAD-1:0] tx_payload;
    always @* begin
        tx_payload = 0;
        tx_payload[7:0] = tx_sequence;
        tx_payload[8*STATUS_BYTES+7:8] = local_status;
    end
    wire tx_start_packet = send_due && !pkt_busy;
    packet_tx #(.MAX_PAYLOAD(MAX_PAYLOAD)) packet_sender(
        .clk(clk), .rst(rst), .send(tx_start_packet),
        .pkt_type(PKT_STATUS), .pkt_len(PKT_LEN), .pkt_payload(tx_payload),
        .corrupt_checksum(1'b0), .busy(pkt_busy),
        .tx_start(pkt_tx_start), .tx_data(pkt_tx_data), .tx_busy(tx_busy));
    assign packet_error = pkt_error;
    assign frame_error = rx_frame_error;

    always @(posedge clk) begin
        peer_status_valid <= 1'b0;
        if (rst) begin
            tx_sequence <= 0; period_timer <= 0; timeout_timer <= 0;
            send_due <= 0; link_up <= 0; peer_status <= 0;
        end else begin
            if (tx_start_packet) begin
                send_due <= 0;
                tx_sequence <= tx_sequence + 1'b1;
            end
            if (period_timer == PERIOD_CYCLES-1) begin
                period_timer <= 0;
                send_due <= 1;
            end else period_timer <= period_timer + 1'b1;

            if (pkt_valid && pkt_type == PKT_STATUS && pkt_len == PKT_LEN) begin
                peer_status <= pkt_payload[8*STATUS_BYTES+7:8];
                peer_status_valid <= 1;
                link_up <= 1;
                timeout_timer <= 0;
            end else if (link_up) begin
                if (timeout_timer == TIMEOUT_CYCLES-1) begin
                    timeout_timer <= 0;
                    link_up <= 0;
                end else timeout_timer <= timeout_timer + 1'b1;
            end else timeout_timer <= 0;
        end
    end
endmodule
