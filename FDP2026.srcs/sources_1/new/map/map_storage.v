`timescale 1ns / 1ps
module map_storage(input wire clk, input wire rst,
    input wire write_en, input wire [7:0] write_addr,
    input wire write_wall, output wire [255:0] map_bits);
    // Deliberately flip-flops: arbitrary simultaneous combinational consumers.
    (* ram_style = "registers" *) reg [15:0] map_row [0:15];
    integer r;
    always @(posedge clk) begin
        if (rst) begin
            for (r = 0; r < 16; r = r + 1) map_row[r] <= 16'hFFFF;
        end else if (write_en) begin
            map_row[write_addr[7:4]][write_addr[3:0]] <= write_wall;
        end
    end
    genvar y;
    generate for (y = 0; y < 16; y = y + 1) begin : flatten
        assign map_bits[y*16 +: 16] = map_row[y];
    end endgenerate
endmodule
