`timescale 1ns / 1ps
module seven_seg_hex(input wire clk, input wire rst,
    input wire [15:0] value, output reg [6:0] seg,
    output wire dp, output reg [3:0] an);
    reg [17:0] refresh_counter;
    reg [3:0] nibble;
    // No generated clock: the selector is data from the free-running counter.
    always @(posedge clk) begin
        if(rst) refresh_counter<=0;
        else refresh_counter<=refresh_counter+1'b1;
    end
    assign dp=1'b1;
    always @* begin
        case(refresh_counter[17:16])
            2'd0: begin an=4'b1110; nibble=value[3:0]; end
            2'd1: begin an=4'b1101; nibble=value[7:4]; end
            2'd2: begin an=4'b1011; nibble=value[11:8]; end
            2'd3: begin an=4'b0111; nibble=value[15:12]; end
            default: begin an=4'b1111; nibble=0; end
        endcase
        // seg[0]=CA through seg[6]=CG; literals are ordered {G,F,E,D,C,B,A}.
        case(nibble)
            4'h0: seg=7'b1000000;
            4'h1: seg=7'b1111001;
            4'h2: seg=7'b0100100;
            4'h3: seg=7'b0110000;
            4'h4: seg=7'b0011001;
            4'h5: seg=7'b0010010;
            4'h6: seg=7'b0000010;
            4'h7: seg=7'b1111000;
            4'h8: seg=7'b0000000;
            4'h9: seg=7'b0010000;
            4'hA: seg=7'b0001000;
            4'hB: seg=7'b0000011;
            4'hC: seg=7'b1000110;
            4'hD: seg=7'b0100001;
            4'hE: seg=7'b0000110;
            4'hF: seg=7'b0001110;
            default: seg=7'b1111111;
        endcase
        if(rst) begin an=4'b1111; seg=7'b1111111; end
    end
endmodule
