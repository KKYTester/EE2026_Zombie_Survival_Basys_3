`timescale 1ns / 1ps
// 0..99 -> two decimal digits (values above 99 show 99). Compare/subtract, no divider.
module wave_digits(input wire [6:0] value, output reg [3:0] tens, output reg [3:0] ones);
    reg [6:0] v, rest;
    always @* begin
        v = (value>99) ? 7'd99 : value;
        if(v>=90) begin tens=9; rest=v-90; end
        else if(v>=80) begin tens=8; rest=v-80; end
        else if(v>=70) begin tens=7; rest=v-70; end
        else if(v>=60) begin tens=6; rest=v-60; end
        else if(v>=50) begin tens=5; rest=v-50; end
        else if(v>=40) begin tens=4; rest=v-40; end
        else if(v>=30) begin tens=3; rest=v-30; end
        else if(v>=20) begin tens=2; rest=v-20; end
        else if(v>=10) begin tens=1; rest=v-10; end
        else begin tens=0; rest=v; end
        ones=rest[3:0];
    end
endmodule
