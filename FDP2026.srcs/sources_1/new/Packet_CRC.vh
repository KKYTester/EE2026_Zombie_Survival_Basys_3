// CRC-16/CCITT-FALSE: poly 0x1021, init 0xffff, MSB first, no final XOR.
function [15:0] packet_crc_byte;
    input [15:0] crc;
    input [7:0] value;
    reg [15:0] work;
    integer bit_index;
    begin
        work = crc ^ {value,8'd0};
        for(bit_index=0;bit_index<8;bit_index=bit_index+1)
            work = work[15] ? (work << 1) ^ 16'h1021 : work << 1;
        packet_crc_byte = work;
    end
endfunction
