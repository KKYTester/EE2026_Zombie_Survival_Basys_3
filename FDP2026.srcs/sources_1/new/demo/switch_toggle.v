`timescale 1ns / 1ps
// Debounced switch whose every flip (off->on or on->off) gives one
// one-clock pulse. Used for the demo's temporary test actions, so a test
// event needs one flick instead of a push button.
module switch_toggle #(parameter STABLE_CYCLES=1000000)(
    input wire clk, input wire rst, input wire switch_in,
    output reg flipped);
    (* ASYNC_REG="TRUE" *) reg [1:0] sync_ff;
    reg stable, primed;
    reg [31:0] count;
    always @(posedge clk) begin
        if(rst) begin sync_ff<=0; stable<=0; primed<=0; count<=0; flipped<=0; end
        else begin
            sync_ff<={sync_ff[0],switch_in}; flipped<=0;
            if(!primed) begin
                // Adopt the switch position after reset without an event.
                stable<=sync_ff[1]; count<=count+1'b1;
                if(count==3) begin primed<=1; count<=0; end
            end else if(sync_ff[1]==stable) count<=0;
            else if(count==STABLE_CYCLES-1) begin
                stable<=sync_ff[1]; count<=0; flipped<=1;
            end else count<=count+1'b1;
        end
    end
endmodule
