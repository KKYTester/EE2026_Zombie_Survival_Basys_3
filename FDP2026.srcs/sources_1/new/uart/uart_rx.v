`timescale 1ns / 1ps
module uart_rx(
    input wire clk, input wire rst, input wire tick_16x, input wire rx,
    output reg [7:0] data, output reg valid, output reg frame_error);

    localparam S_IDLE=3'd0, S_START=3'd1, S_DATA=3'd2, S_STOP=3'd3, S_WAIT_HIGH=3'd4;

    (* ASYNC_REG="TRUE" *) reg [1:0] rx_sync;
    wire line = rx_sync[1];
    reg [2:0] state;
    reg [3:0] tick_count;
    reg [2:0] bit_index;
    reg [7:0] shift;

    always @(posedge clk) begin
        valid <= 1'b0;
        frame_error <= 1'b0;
        if (rst) begin
            rx_sync <= 2'b11;
            state <= S_IDLE;
            tick_count <= 0;
            bit_index <= 0;
            shift <= 0;
            data <= 0;
        end else begin
            rx_sync <= {rx_sync[0], rx};
            case (state)
                S_IDLE: if (!line) begin
                    state <= S_START;
                    tick_count <= 0;
                end
                S_START: if (tick_16x) begin
                    if (tick_count == 4'd7) begin
                        tick_count <= 0;
                        bit_index <= 0;
                        state <= line ? S_IDLE : S_DATA;
                    end else begin
                        tick_count <= tick_count + 1'b1;
                    end
                end
                S_DATA: if (tick_16x) begin
                    if (tick_count == 4'd15) begin
                        tick_count <= 0;
                        shift <= {line, shift[7:1]};
                        bit_index <= bit_index + 1'b1;
                        if (bit_index == 3'd7) state <= S_STOP;
                    end else begin
                        tick_count <= tick_count + 1'b1;
                    end
                end
                S_STOP: if (tick_16x) begin
                    if (tick_count == 4'd15) begin
                        tick_count <= 0;
                        if (line) begin
                            data <= shift;
                            valid <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            frame_error <= 1'b1;
                            state <= S_WAIT_HIGH;
                        end
                    end else begin
                        tick_count <= tick_count + 1'b1;
                    end
                end
                S_WAIT_HIGH: if (line) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
