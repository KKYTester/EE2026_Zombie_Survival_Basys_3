`timescale 1ns / 1ps
module button_debounce #(parameter STABLE_CYCLES=1000000)(
    input wire clk, input wire rst, input wire button,
    output reg pressed);
    (* ASYNC_REG="TRUE" *) reg [1:0] sync_ff;
    reg stable;
    reg [31:0] count;
    always @(posedge clk) begin
        if(rst) begin sync_ff<=0; stable<=0; count<=0; pressed<=0; end
        else begin
            sync_ff<={sync_ff[0],button}; pressed<=0;
            if(sync_ff[1]==stable) count<=0;
            else if(count==STABLE_CYCLES-1) begin
                stable<=sync_ff[1]; count<=0;
                if(sync_ff[1]) pressed<=1;
            end else count<=count+1'b1;
        end
    end
endmodule
