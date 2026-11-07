`timescale 1ns / 1ps
// One tile-centre supercover ray at a time. Exact corner crossings
// check both side cells, matching the navigation rule for diagonals.
module zombie_sight(
    input wire clk, reset, start,
    input wire [255:0] walls,
    input wire [7:0] from_tile, to_tile,
    output reg done, visible
);
    localparam [2:0] IDLE=0, TILE=1, WALK=2, SIDE_X=3, SIDE_Y=4;
    localparam [3:0] RANGE=6;
    reg [2:0] state;
    reg [7:0] current, goal;
    reg x_increases, y_increases;
    reg signed [5:0] error, x_increment, y_increment, diagonal_increment;
    wire [3:0] dx=to_tile[3:0]>=from_tile[3:0] ?
        to_tile[3:0]-from_tile[3:0] : from_tile[3:0]-to_tile[3:0];
    wire [3:0] dy=to_tile[7:4]>=from_tile[7:4] ?
        to_tile[7:4]-from_tile[7:4] : from_tile[7:4]-to_tile[7:4];
    wire signed [5:0] initial_error=$signed({2'b0,dy})-$signed({2'b0,dx});
    wire [3:0] next_x=x_increases ? current[3:0]+4'd1 : current[3:0]-4'd1;
    wire [3:0] next_y=y_increases ? current[7:4]+4'd1 : current[7:4]-4'd1;
    wire [7:0] probe=state==SIDE_X ? {current[7:4],next_x} :
                     state==SIDE_Y ? {next_y,current[3:0]} : current;
    wire blocked=walls[probe];

    always @(posedge clk) begin
        done<=0;
        if(reset) begin
            state<=IDLE;
            visible<=0;
        end else case(state)
            IDLE: if(start) begin
                if(dx>RANGE || dy>RANGE) begin
                    visible<=0;
                    done<=1;
                end else begin
                    current<=from_tile;
                    goal<=to_tile;
                    x_increases<=to_tile[3:0]>from_tile[3:0];
                    y_increases<=to_tile[7:4]>from_tile[7:4];
                    // The sign compares time to the next vertical and
                    // horizontal boundaries, with the denominators removed.
                    error<=initial_error;
                    x_increment<=$signed({1'b0,dy,1'b0});
                    y_increment<=-$signed({1'b0,dx,1'b0});
                    diagonal_increment<=initial_error <<< 1;
                    state<=TILE;
                end
            end
            TILE: if(blocked || current==goal) begin
                visible<=!blocked;
                done<=1;
                state<=IDLE;
            end else state<=WALK;
            WALK: if(current[7:4]==goal[7:4] ||
                        (current[3:0]!=goal[3:0] && error<0)) begin
                current[3:0]<=next_x;
                error<=error+x_increment;
                state<=TILE;
            end else if(current[3:0]==goal[3:0] || error>0) begin
                current[7:4]<=next_y;
                error<=error+y_increment;
                state<=TILE;
            end else state<=SIDE_X;
            SIDE_X: if(blocked) begin
                visible<=0;
                done<=1;
                state<=IDLE;
            end else state<=SIDE_Y;
            SIDE_Y: if(blocked) begin
                visible<=0;
                done<=1;
                state<=IDLE;
            end else begin
                current<={next_y,next_x};
                error<=error+diagonal_increment;
                state<=TILE;
            end
            default: state<=IDLE;
        endcase
    end
endmodule
