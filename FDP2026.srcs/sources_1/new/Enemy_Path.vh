// Shared map-space directions: W,E,N,S,NW,SE,NE,SW. Opposites XOR 1.
// No include guard: these pure functions belong to each including module.
function [7:0] neighbor_tile(input [7:0] from_tile, input [2:0] dir);
    case(dir)
        0: neighbor_tile=from_tile-8'd1;
        1: neighbor_tile=from_tile+8'd1;
        2: neighbor_tile=from_tile-8'd16;
        3: neighbor_tile=from_tile+8'd16;
        4: neighbor_tile=from_tile-8'd17;
        5: neighbor_tile=from_tile+8'd17;
        6: neighbor_tile=from_tile-8'd15;
        7: neighbor_tile=from_tile+8'd15;
    endcase
endfunction
function signed [2:0] direction_x(input [2:0] dir);
    case(dir)
        0,4,7: direction_x=-3'sd1;
        1,5,6: direction_x=3'sd1;
        default: direction_x=0;
    endcase
endfunction
function signed [2:0] direction_y(input [2:0] dir);
    case(dir)
        2,4,6: direction_y=-3'sd1;
        3,5,7: direction_y=3'sd1;
        default: direction_y=0;
    endcase
endfunction
function neighbor_valid(input [7:0] from_tile, input [2:0] dir);
    begin
        neighbor_valid=!(direction_x(dir)<0 && from_tile[3:0]==0) &&
            !(direction_x(dir)>0 && from_tile[3:0]==15) &&
            !(direction_y(dir)<0 && from_tile[7:4]==0) &&
            !(direction_y(dir)>0 && from_tile[7:4]==15);
    end
endfunction
// A diagonal owns the whole 2x2 swept square, including both side cells.
// Using the same footprint for planning, steering and reservations prevents
// corner cutting, head-on swaps and intersecting diagonal trips.
function [255:0] segment_mask(input [7:0] a, b);
    begin
        segment_mask=0;
        segment_mask[a]=1; segment_mask[b]=1;
        if(a[3:0]!=b[3:0] && a[7:4]!=b[7:4]) begin
            segment_mask[{a[7:4],b[3:0]}]=1;
            segment_mask[{b[7:4],a[3:0]}]=1;
        end
    end
endfunction
// Probe a footprint directly when only a few queried cells are needed.
function segment_has(input [7:0] a, b, probe);
    begin
        segment_has=probe==a || probe==b ||
            (a[3:0]!=b[3:0] && a[7:4]!=b[7:4] &&
             (probe=={a[7:4],b[3:0]} || probe=={b[7:4],a[3:0]}));
    end
endfunction
