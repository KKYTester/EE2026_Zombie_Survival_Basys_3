`timescale 1ns / 1ps
// PS/2 Y is positive upward; OLED coordinates increase downward.
// Consume each packet once. Clamp after signed addition, including -256.
module Mouse_Pointer (
    input wire clk, reset, mouse_event,
    input wire signed [8:0] x_delta, y_delta,
    output reg [6:0] x,
    output reg [5:0] y
);
    wire signed [10:0] next_x = $signed({4'b0,x}) + {{2{x_delta[8]}},x_delta};
    wire signed [10:0] next_y = $signed({5'b0,y}) - {{2{y_delta[8]}},y_delta};
    always @(posedge clk) begin
        if (reset) begin x <= 48; y <= 40; end
        else if (mouse_event) begin
            x <= next_x < 0 ? 7'd0 : next_x > 95 ? 7'd95 : next_x[6:0];
            y <= next_y < 0 ? 6'd0 : next_y > 63 ? 6'd63 : next_y[5:0];
        end
    end
endmodule
