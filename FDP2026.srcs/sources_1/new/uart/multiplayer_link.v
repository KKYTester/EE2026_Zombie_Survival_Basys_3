`timescale 1ns / 1ps
// Basys-to-Basys game link. The client periodically sends INPUT_BYTES of
// player data to the host; the host periodically returns a 15-byte game
// snapshot and a 9-byte zombie list. Game-specific meaning of every payload
// is assigned by the top-level wrapper.
//
// Packet types: 03 = HELLO, 04 = HELLO_ACK, 10 = INPUT(seq, controls),
// 20 = STATE(seq, snapshot[119:0]), 21 = ZOMBIES(seq, zombies[71:0]).
// All packets use packet_tx/rx's A5 framing.
module multiplayer_link #(
    parameter integer CLK_FREQ = 100_000_000,
    parameter integer INPUT_PERIOD_CYCLES = 2_000_000,  // 20 ms
    parameter integer STATE_PERIOD_CYCLES = 5_000_000,  // 50 ms
    parameter integer HELLO_PERIOD_CYCLES = 25_000_000, // 250 ms
    parameter integer TIMEOUT_CYCLES = 50_000_000,      // 500 ms
    parameter integer INPUT_BYTES = 1                   // client payload, 1..15
)(
    input wire clk,
    input wire rst,
    input wire host_mode,
    input wire uart_rx_pin,
    output wire uart_tx_pin,
    input wire [8*INPUT_BYTES-1:0] local_controls,
    input wire [119:0] host_snapshot,
    input wire [71:0] host_zombies,
    output reg [8*INPUT_BYTES-1:0] remote_controls,
    output reg remote_controls_valid,
    output reg [119:0] client_snapshot,
    output reg client_snapshot_valid,
    output reg [71:0] client_zombies,
    output reg client_zombies_valid,
    output reg link_up,
    output wire packet_error,
    output wire frame_error
);
    localparam [7:0] PKT_HELLO = 8'h03;
    localparam [7:0] PKT_HELLO_ACK = 8'h04;
    localparam [7:0] PKT_INPUT = 8'h10;
    localparam [7:0] PKT_STATE = 8'h20;
    localparam [7:0] PKT_ZOMBIES = 8'h21;
    localparam integer MAX_PAYLOAD = 16;

    wire tick_16x;
    wire [7:0] rx_data;
    wire rx_valid, rx_frame_error;
    wire pkt_busy, pkt_tx_start, tx_busy;
    wire [7:0] pkt_tx_data;
    wire pkt_valid, pkt_error;
    wire [7:0] pkt_type, pkt_len;
    wire [8*MAX_PAYLOAD-1:0] pkt_payload;

    baud_gen #(.CLK_FREQ(CLK_FREQ)) baud(
        .clk(clk), .rst(rst), .tick_16x(tick_16x));
    uart_tx transmitter(
        .clk(clk), .rst(rst), .tick_16x(tick_16x),
        .data(pkt_tx_data), .start(pkt_tx_start),
        .tx(uart_tx_pin), .busy(tx_busy));
    uart_rx receiver(
        .clk(clk), .rst(rst), .tick_16x(tick_16x), .rx(uart_rx_pin),
        .data(rx_data), .valid(rx_valid), .frame_error(rx_frame_error));
    packet_rx #(.MAX_PAYLOAD(MAX_PAYLOAD)) packet_receiver(
        .clk(clk), .rst(rst), .rx_data(rx_data),
        .rx_valid(rx_valid), .rx_frame_error(rx_frame_error),
        .pkt_valid(pkt_valid), .pkt_error(pkt_error),
        .pkt_type(pkt_type), .pkt_len(pkt_len), .pkt_payload(pkt_payload));

    reg [7:0] tx_sequence;
    reg [31:0] input_timer, state_timer, hello_timer, timeout_timer;
    reg input_due, state_due, zombies_due, hello_due, ack_due;

    wire send_ack = host_mode && ack_due;
    wire send_state = host_mode && !ack_due && state_due;
    wire send_zombies = host_mode && !ack_due && !state_due && zombies_due;
    wire send_hello = !host_mode && !link_up && hello_due;
    wire send_input = !host_mode && link_up && input_due;
    wire [7:0] tx_type = send_ack ? PKT_HELLO_ACK :
                         send_state ? PKT_STATE :
                         send_zombies ? PKT_ZOMBIES :
                         send_hello ? PKT_HELLO : PKT_INPUT;
    wire [7:0] tx_len = send_state ? 8'd16 :
                        send_zombies ? 8'd10 :
                        send_input ? INPUT_BYTES+1 : 8'd1;
    reg [8*MAX_PAYLOAD-1:0] tx_payload;
    always @* begin
        tx_payload = 0;
        if (send_state) begin
            tx_payload[7:0] = tx_sequence;
            tx_payload[127:8] = host_snapshot;
        end else if (send_zombies) begin
            tx_payload[7:0] = tx_sequence;
            tx_payload[79:8] = host_zombies;
        end else if (send_input) begin
            tx_payload[7:0] = tx_sequence;
            tx_payload[8*INPUT_BYTES+7:8] = local_controls;
        end else begin
            tx_payload[7:0] = 8'h01; // protocol version
        end
    end
    wire tx_request = send_ack || send_state || send_zombies || send_hello || send_input;
    wire tx_start_packet = tx_request && !pkt_busy;

    packet_tx #(.MAX_PAYLOAD(MAX_PAYLOAD)) packet_sender(
        .clk(clk), .rst(rst), .send(tx_start_packet),
        .pkt_type(tx_type), .pkt_len(tx_len), .pkt_payload(tx_payload),
        .corrupt_checksum(1'b0), .busy(pkt_busy),
        .tx_start(pkt_tx_start), .tx_data(pkt_tx_data), .tx_busy(tx_busy));

    assign packet_error = pkt_error;
    assign frame_error = rx_frame_error;

    always @(posedge clk) begin
        remote_controls_valid <= 1'b0;
        client_snapshot_valid <= 1'b0;
        client_zombies_valid <= 1'b0;
        if (rst) begin
            tx_sequence <= 0;
            input_timer <= 0; state_timer <= 0; hello_timer <= 0;
            timeout_timer <= 0;
            input_due <= 0; state_due <= 0; zombies_due <= 0;
            hello_due <= 1; ack_due <= 0;
            link_up <= 0;
            remote_controls <= 0; client_snapshot <= 0; client_zombies <= 0;
        end else begin
            if (tx_start_packet) begin
                tx_sequence <= tx_sequence + 1'b1;
                if (send_ack) ack_due <= 0;
                if (send_state) state_due <= 0;
                if (send_zombies) zombies_due <= 0;
                if (send_hello) hello_due <= 0;
                if (send_input) input_due <= 0;
            end

            if (host_mode) begin
                if (state_timer == STATE_PERIOD_CYCLES-1) begin
                    state_timer <= 0;
                    state_due <= 1;
                    zombies_due <= 1;
                end else state_timer <= state_timer + 1'b1;
            end else if (link_up) begin
                hello_timer <= 0;
                if (input_timer == INPUT_PERIOD_CYCLES-1) begin
                    input_timer <= 0;
                    input_due <= 1;
                end else input_timer <= input_timer + 1'b1;
            end else begin
                input_timer <= 0;
                if (hello_timer == HELLO_PERIOD_CYCLES-1) begin
                    hello_timer <= 0;
                    hello_due <= 1;
                end else hello_timer <= hello_timer + 1'b1;
            end

            if (pkt_valid) begin
                timeout_timer <= 0;
                if (host_mode) begin
                    if (pkt_type == PKT_HELLO && pkt_len == 1 &&
                        pkt_payload[7:0] == 8'h01) begin
                        link_up <= 1;
                        ack_due <= 1;
                    end else if (pkt_type == PKT_INPUT && link_up && pkt_len == INPUT_BYTES+1) begin
                        remote_controls <= pkt_payload[8*INPUT_BYTES+7:8];
                        remote_controls_valid <= 1;
                    end
                end else begin
                    if (pkt_type == PKT_HELLO_ACK && pkt_len == 1 &&
                        pkt_payload[7:0] == 8'h01) link_up <= 1;
                    else if (pkt_type == PKT_STATE && link_up && pkt_len == 16) begin
                        client_snapshot <= pkt_payload[127:8];
                        client_snapshot_valid <= 1;
                    end else if (pkt_type == PKT_ZOMBIES && link_up && pkt_len == 10) begin
                        client_zombies <= pkt_payload[79:8];
                        client_zombies_valid <= 1;
                    end
                end
            end else if (link_up) begin
                if (timeout_timer == TIMEOUT_CYCLES-1) begin
                    timeout_timer <= 0;
                    link_up <= 0;
                    hello_due <= !host_mode;
                    state_due <= 0;
                    zombies_due <= 0;
                    input_due <= 0;
                end else timeout_timer <= timeout_timer + 1'b1;
            end else timeout_timer <= 0;
        end
    end
endmodule
