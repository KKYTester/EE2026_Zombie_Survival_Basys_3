`timescale 1ns / 1ps

// A level changes only after STABLE_CYCLES consecutive synchronized samples.
module Button_Debounce #(
    parameter integer STABLE_CYCLES = 1_000_000 // 10 ms at 100 MHz
) (
    input wire clk, reset, button,
    output reg pressed
);
    localparam integer BITS = STABLE_CYCLES > 1 ? $clog2(STABLE_CYCLES) : 1;
    localparam [BITS-1:0] LAST = STABLE_CYCLES - 1;
    (* ASYNC_REG = "TRUE" *) reg button_meta, button_sync;
    reg [BITS-1:0] count;
    always @(posedge clk) begin
        if (reset) begin
            button_meta <= 0;
            button_sync <= 0;
            pressed <= 0;
            count <= 0;
        end else begin
            button_meta <= button;
            button_sync <= button_meta;
            if (button_sync == pressed) count <= 0;
            else if (count == LAST) begin
                pressed <= button_sync;
                count <= 0;
            end else count <= count + 1'b1;
        end
    end
endmodule
