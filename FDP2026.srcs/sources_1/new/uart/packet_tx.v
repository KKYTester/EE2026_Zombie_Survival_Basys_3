`timescale 1ns / 1ps
// packet: A5, type, len, payload, checksum (sum of type, len, payload)
module packet_tx #(parameter MAX_PAYLOAD=16, parameter [7:0] START_BYTE=8'hA5)(
    input wire clk, input wire rst, input wire send,
    input wire [7:0] pkt_type, input wire [7:0] pkt_len,
    input wire [8*MAX_PAYLOAD-1:0] pkt_payload, input wire corrupt_checksum,
    output wire busy,
    output reg tx_start, output reg [7:0] tx_data, input wire tx_busy);

    localparam S_IDLE=3'd0, S_START=3'd1, S_TYPE=3'd2, S_LEN=3'd3, S_PAYLOAD=3'd4, S_CHECK=3'd5;

    reg [2:0] state;
    reg [7:0] type_reg, len_reg, bytes_left, checksum;
    reg [8*MAX_PAYLOAD-1:0] payload_reg;
    reg corrupt_reg;

    wire uart_ready = !tx_busy && !tx_start;
    assign busy = state != S_IDLE || tx_start || tx_busy;

    always @(posedge clk) begin
        tx_start <= 1'b0;
        if (rst) begin
            state <= S_IDLE;
            tx_data <= 0;
            type_reg <= 0; len_reg <= 0; bytes_left <= 0; checksum <= 0;
            payload_reg <= 0;
            corrupt_reg <= 1'b0;
        end else if (state == S_IDLE) begin
            if (send && !busy) begin
                type_reg <= pkt_type;
                len_reg <= pkt_len;
                bytes_left <= pkt_len;
                payload_reg <= pkt_payload;
                corrupt_reg <= corrupt_checksum;
                checksum <= 0;
                state <= S_START;
            end
        end else if (uart_ready) begin
            tx_start <= 1'b1;
            case (state)
                S_START: begin
                    tx_data <= START_BYTE;
                    state <= S_TYPE;
                end
                S_TYPE: begin
                    tx_data <= type_reg;
                    checksum <= checksum + type_reg;
                    state <= S_LEN;
                end
                S_LEN: begin
                    tx_data <= len_reg;
                    checksum <= checksum + len_reg;
                    state <= (len_reg == 0) ? S_CHECK : S_PAYLOAD;
                end
                S_PAYLOAD: begin
                    tx_data <= payload_reg[7:0];
                    checksum <= checksum + payload_reg[7:0];
                    payload_reg <= payload_reg >> 8;
                    bytes_left <= bytes_left - 1'b1;
                    if (bytes_left == 8'd1) state <= S_CHECK;
                end
                S_CHECK: begin
                    tx_data <= corrupt_reg ? ~checksum : checksum;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
