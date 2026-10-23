`timescale 1ns / 1ps
// Preserve the supplied driver byte-for-byte. It ends D/C after 6143 pixels.
// Queue its active SPI bits and insert pixel 6143 before the next command.
// Idle input clocks let the queue drain; the frame gap is thousands of clocks.
module oled_tail_bridge(input wire clk, input wire rst,
    input wire raw_cs, input wire raw_sdin, input wire raw_dcn,
    input wire [15:0] last_pixel_data,
    output reg cs, output reg sdin, output reg d_cn, output wire sclk);
    // bit17 = insertion marker, bit16 = D/C, bits15:0 = pixel or serial bit.
    reg [17:0] fifo[0:63];
    reg [5:0] head,tail;
    reg [6:0] count;
    reg previous_dcn;
    reg [3:0] tail_bits;
    reg [15:0] tail_shift;
    wire marker=previous_dcn && !raw_dcn;
    wire push=marker || !raw_cs;
    wire pop=(tail_bits==0 && count!=0);
    wire [17:0] front=fifo[head];
    assign sclk=clk | cs;
    // Same negative-edge convention as the course driver: data stable at rise.
    always @(negedge clk) begin
        if(rst) begin
            head<=0; tail<=0; count<=0; previous_dcn<=0;
            tail_bits<=0; tail_shift<=0; cs<=1; sdin<=0; d_cn<=0;
        end else begin
            previous_dcn<=raw_dcn;
            // The supplied driver leaves CS high at each D/C falling edge.
            // Therefore a marker never displaces an active command bit.
            if(push) begin
                fifo[tail]<=marker ? {2'b11,last_pixel_data} : {1'b0,raw_dcn,15'b0,raw_sdin};
                tail<=tail+1'b1;
            end
            case({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: count<=count;
            endcase
            if(tail_bits!=0) begin
                // TAIL state: emit the remaining bits of the inserted pixel.
                cs<=0; d_cn<=1; sdin<=tail_shift[15];
                tail_shift<={tail_shift[14:0],1'b0}; tail_bits<=tail_bits-1'b1;
            end else if(pop) begin
                // FORWARD state: emit queued source bits or begin a tail pixel.
                head<=head+1'b1; cs<=0; d_cn<=front[16];
                if(front[17]) begin
                    sdin<=front[15]; tail_shift<={front[14:0],1'b0}; tail_bits<=15;
                end else sdin<=front[0];
            end else begin
                // IDLE state: deassert chip-select when no serial bits remain.
                cs<=1; sdin<=0; d_cn<=0;
            end
        end
    end
endmodule
