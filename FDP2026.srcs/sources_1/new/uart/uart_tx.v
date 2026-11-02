`timescale 1ns / 1ps
module uart_tx(
    input wire clk, input wire rst, input wire tick_16x,
    input wire [7:0] data, input wire start,
    output reg tx, output reg busy);

    reg [9:0] frame;
    reg [3:0] bits_left;
    reg [3:0] tick_count;

    always @(posedge clk) begin
        if (rst) begin
            tx <= 1'b1;
            busy <= 1'b0;
            frame <= 10'h3FF;
            bits_left <= 0;
            tick_count <= 0;
        end else if (!busy) begin
            if (start) begin
                frame <= {1'b1, data, 1'b0};
                bits_left <= 4'd10;
                tick_count <= 4'd15;
                busy <= 1'b1;
            end
        end else if (tick_16x) begin
            if (tick_count == 4'd15) begin
                tick_count <= 0;
                if (bits_left == 0) begin
                    busy <= 1'b0;
                end else begin
                    tx <= frame[0];
                    frame <= {1'b1, frame[9:1]};
                    bits_left <= bits_left - 1'b1;
                end
            end else begin
                tick_count <= tick_count + 1'b1;
            end
        end
    end
endmodule
