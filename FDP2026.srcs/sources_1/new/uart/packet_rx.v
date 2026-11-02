`timescale 1ns / 1ps
module packet_rx #(parameter MAX_PAYLOAD=16, parameter [7:0] START_BYTE=8'hA5,
    parameter TIMEOUT_CYCLES=100000)(
    input wire clk, input wire rst,
    input wire [7:0] rx_data, input wire rx_valid, input wire rx_frame_error,
    output reg pkt_valid, output reg pkt_error,
    output reg [7:0] pkt_type, output reg [7:0] pkt_len,
    output reg [8*MAX_PAYLOAD-1:0] pkt_payload);

    localparam S_WAIT=3'd0, S_TYPE=3'd1, S_LEN=3'd2, S_PAYLOAD=3'd3, S_CHECK=3'd4;

    reg [2:0] state;
    reg [7:0] type_reg, len_reg, index, checksum;
    reg [8*MAX_PAYLOAD-1:0] payload_reg;
    reg [31:0] gap_count;

    always @(posedge clk) begin
        pkt_valid <= 1'b0;
        pkt_error <= 1'b0;
        if (rst) begin
            state <= S_WAIT;
            type_reg <= 0; len_reg <= 0; index <= 0; checksum <= 0;
            payload_reg <= 0;
            gap_count <= 0;
            pkt_type <= 0; pkt_len <= 0; pkt_payload <= 0;
        end else if (state != S_WAIT && (rx_frame_error || gap_count == TIMEOUT_CYCLES-1)) begin
            pkt_error <= 1'b1;
            state <= S_WAIT;
        end else if (rx_valid) begin
            gap_count <= 0;
            case (state)
                S_WAIT: if (rx_data == START_BYTE) state <= S_TYPE;
                S_TYPE: begin
                    type_reg <= rx_data;
                    checksum <= rx_data;
                    payload_reg <= 0;
                    state <= S_LEN;
                end
                S_LEN: begin
                    if (rx_data > MAX_PAYLOAD) begin
                        pkt_error <= 1'b1;
                        state <= S_WAIT;
                    end else begin
                        len_reg <= rx_data;
                        checksum <= checksum + rx_data;
                        index <= 0;
                        state <= (rx_data == 0) ? S_CHECK : S_PAYLOAD;
                    end
                end
                S_PAYLOAD: begin
                    payload_reg[{index, 3'b000} +: 8] <= rx_data;
                    checksum <= checksum + rx_data;
                    index <= index + 1'b1;
                    if (index + 1'b1 == len_reg) state <= S_CHECK;
                end
                S_CHECK: begin
                    if (rx_data == checksum) begin
                        pkt_valid <= 1'b1;
                        pkt_type <= type_reg;
                        pkt_len <= len_reg;
                        pkt_payload <= payload_reg;
                    end else begin
                        pkt_error <= 1'b1;
                    end
                    state <= S_WAIT;
                end
                default: state <= S_WAIT;
            endcase
        end else if (state != S_WAIT) begin
            gap_count <= gap_count + 1'b1;
        end else begin
            gap_count <= 0;
        end
    end
endmodule
