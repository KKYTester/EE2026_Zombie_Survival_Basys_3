`timescale 1ns / 1ps
// Four-entry stop-and-wait event FIFO. Snapshots survive dropped status packets;
// only the matching leader ACK retires the head. On rejoin, resume after the
// leader's retained ACK, so resetting the follower cannot manufacture a shot.
module shot_event_queue(
    input wire clk, reset, enabled,
    input wire fire,
    input wire [15:0] fire_x, fire_y,
    input wire [9:0] fire_angle,
    input wire [7:0] acknowledged,
    output wire ready, valid,
    output wire [7:0] event_id,
    output wire [15:0] event_x, event_y,
    output wire [9:0] event_angle
);
    reg [49:0] events[0:3];
    reg [1:0] head,tail;
    reg [2:0] count;
    reg [7:0] next_id;
    reg write_pending;
    reg [1:0] write_address;
    reg [49:0] write_event;
    // A just-enqueued head is visible after its registered RAM write.
    wire head_written=count!=0 && !(count==1 && write_pending);
    assign {event_id,event_x,event_y,event_angle}=head_written ? events[head] : 50'd0;
    assign valid=enabled && head_written;
    wire pop=valid && acknowledged==event_id;
    assign ready=enabled && (count<4 || pop);
    wire push=fire && ready;
    always @(posedge clk) begin
        write_pending<=!reset && push;
        write_address<=tail;
        write_event<={next_id,fire_x,fire_y,fire_angle};
        // The pending register alone drives the distributed RAM write enable.
        // A reset or disconnect discards the contents through the pointers.
        if(write_pending) events[write_address]<=write_event;
    end
    always @(posedge clk) begin
        if(reset || !enabled) begin
            head<=0; tail<=0; count<=0; next_id<=acknowledged+8'd1;
        end else begin
            if(push) begin
                tail<=tail+1'b1; next_id<=next_id+8'd1;
            end
            if(pop) head<=head+1'b1;
            case({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: ;
            endcase
        end
    end
endmodule
