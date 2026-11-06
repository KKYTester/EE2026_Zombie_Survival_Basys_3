`timescale 1ns / 1ps
// jumper JC1 to JC2
// btnU reset, btnC send, sw15 packet mode, sw14 bad checksum, sw[7:0] data
module uart_test_top #(parameter DEBOUNCE_CYCLES=1000000)(
    input wire clk, input wire btnC, input wire btnU,
    input wire [15:0] sw,
    output reg [15:0] led,
    output reg [6:0] seg, output wire dp, output reg [3:0] an,
    output wire uart_tx_pin, input wire uart_rx_pin);

    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync = 2'b00;
    reg [3:0] power_on = 4'd0;
    wire power_on_done = &power_on;
    wire rst = reset_sync[1] || !power_on_done;
    always @(posedge clk) begin
        reset_sync <= {reset_sync[0], btnU};
        if (!power_on_done) power_on <= power_on + 1'b1;
    end

    (* ASYNC_REG="TRUE" *) reg [1:0] button_sync = 2'b00;
    reg button_stable = 1'b0;
    reg [31:0] button_count = 0;
    reg send_pulse = 1'b0;
    always @(posedge clk) begin
        button_sync <= {button_sync[0], btnC};
        send_pulse <= 1'b0;
        if (button_sync[1] == button_stable) begin
            button_count <= 0;
        end else if (button_count == DEBOUNCE_CYCLES-1) begin
            button_count <= 0;
            button_stable <= button_sync[1];
            send_pulse <= button_sync[1];
        end else begin
            button_count <= button_count + 1'b1;
        end
    end

    localparam MAX_PAYLOAD = 4;
    wire packet_mode = sw[15];
    wire tick_16x, tx_busy, rx_valid, rx_frame_error;
    wire pkt_tx_start, pkt_tx_busy, pkt_valid, pkt_error;
    wire [7:0] rx_data, pkt_tx_data, pkt_type, pkt_len;
    wire [8*MAX_PAYLOAD-1:0] rx_payload;
    wire [8*MAX_PAYLOAD-1:0] tx_payload = {8'h3C, ~sw[7:0], 8'hA5, sw[7:0]};

    wire uart_start = packet_mode ? pkt_tx_start : (send_pulse && !tx_busy);
    wire [7:0] uart_data = packet_mode ? pkt_tx_data : sw[7:0];

    baud_gen baud(.clk(clk), .rst(rst), .tick_16x(tick_16x));
    uart_tx transmitter(.clk(clk), .rst(rst), .tick_16x(tick_16x), .data(uart_data),
        .start(uart_start), .tx(uart_tx_pin), .busy(tx_busy));
    uart_rx receiver(.clk(clk), .rst(rst), .tick_16x(tick_16x), .rx(uart_rx_pin),
        .data(rx_data), .valid(rx_valid), .frame_error(rx_frame_error));
    packet_tx #(.MAX_PAYLOAD(MAX_PAYLOAD)) packet_sender(.clk(clk), .rst(rst),
        .send(send_pulse && packet_mode), .pkt_type(8'h01), .pkt_len(8'd4),
        .pkt_payload(tx_payload), .corrupt_checksum(sw[14]), .busy(pkt_tx_busy),
        .tx_start(pkt_tx_start), .tx_data(pkt_tx_data), .tx_busy(tx_busy));
    packet_rx #(.MAX_PAYLOAD(MAX_PAYLOAD)) packet_receiver(.clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid && packet_mode),
        .rx_frame_error(rx_frame_error && packet_mode),
        .pkt_valid(pkt_valid), .pkt_error(pkt_error), .pkt_type(pkt_type),
        .pkt_len(pkt_len), .pkt_payload(rx_payload));

    reg [15:0] byte_count;
    reg [7:0] good_count, bad_count, last_byte, last_payload_byte;
    reg framing_seen;
    always @(posedge clk) begin
        if (rst) begin
            byte_count <= 0;
            good_count <= 0;
            bad_count <= 0;
            last_byte <= 0;
            last_payload_byte <= 0;
            framing_seen <= 1'b0;
        end else begin
            if (rx_valid) begin
                byte_count <= byte_count + 1'b1;
                last_byte <= rx_data;
            end
            if (pkt_valid) begin
                good_count <= good_count + 1'b1;
                last_payload_byte <= rx_payload[7:0];
            end
            if (pkt_error) bad_count <= bad_count + 1'b1;
            if (rx_frame_error) framing_seen <= 1'b1;
        end
    end

    always @* begin
        led = 16'b0;
        led[7:0] = packet_mode ? last_payload_byte : last_byte;
        led[8] = framing_seen;
        led[14] = pkt_tx_busy || tx_busy;
        led[15] = packet_mode;
    end

    wire [15:0] display_value = packet_mode ? {good_count, bad_count} : byte_count;
    reg [17:0] refresh = 0;
    reg [3:0] digit;
    assign dp = 1'b1;
    always @(posedge clk) refresh <= refresh + 1'b1;

    always @* begin
        case (refresh[17:16])
            2'd0: begin an = 4'b1110; digit = display_value[3:0]; end
            2'd1: begin an = 4'b1101; digit = display_value[7:4]; end
            2'd2: begin an = 4'b1011; digit = display_value[11:8]; end
            default: begin an = 4'b0111; digit = display_value[15:12]; end
        endcase
        case (digit)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            default: seg = 7'b0001110;
        endcase
    end
endmodule
