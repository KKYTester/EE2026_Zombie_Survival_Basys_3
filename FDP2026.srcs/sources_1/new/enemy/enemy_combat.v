`timescale 1ns / 1ps
// Continuous ray/circle intersections, then bounded grid DDA for wall occlusion.
// Arithmetic uses Q*.12 map coordinates (x right, y down), including camera rays.
module enemy_combat #(parameter USE_CAMERA_RAY=0, MAX_ENEMIES=8,
    COORD_FRAC_BITS=8, HIT_RADIUS=(1<<COORD_FRAC_BITS)/4)(
    input wire clk, reset, enabled, shot_fired,
    input wire [7:0] player_tile,
    input wire [1:0] aim,
    input wire [255:0] walls, occupied,
    input wire [31:0] camera_x, camera_y,
    input wire [9:0] camera_angle,
    input wire [MAX_ENEMIES-1:0] active,
    input wire [MAX_ENEMIES*(COORD_FRAC_BITS+4)-1:0] position_x, position_y,
    output wire busy,
    output reg hit_valid,
    output reg [7:0] hit_tile
);
    localparam W=COORD_FRAC_BITS+4;
    localparam [31:0] RADIUS_Q12 = COORD_FRAC_BITS<=12 ?
        HIT_RADIUS << (12-COORD_FRAC_BITS) : HIT_RADIUS >> (COORD_FRAC_BITS-12);
    localparam [36:0] RADIUS_SQ = RADIUS_Q12 * RADIUS_Q12;
    localparam [3:0] IDLE=0, SETUP=1, LOAD=2, DOT=3, DISC=4,
                     ROOT=5, PICK=6, NEXT=7, TRACE=8, CALC=9,
                     DDA_PRODUCTS=10, DDA_CHOOSE=11, DDA_LIMITS=12, DDA_TEST=13;
    reg [3:0] state;
    reg [9:0] heading;
    reg signed [17:0] ox, oy, dx, dy;
    reg signed [8:0] sx, sy;
    reg [8:0] ax, ay;
    reg [17:0] norm;
    reg signed [27:0] dot, direction_cross;
    reg [55:0] cross_sq, radius_term, discriminant;
    reg circle_valid;
    reg [27:0] root;
    reg [29:0] remainder;
    reg [5:0] root_count;
    // Restoring radix-4 integer sqrt: one 31-bit subtract per clock, 28 clocks.
    wire [29:0] shifted_remainder={remainder[27:0],discriminant[55:54]};
    wire [29:0] root_trial={root,2'b01};
    wire [30:0] root_difference={1'b0,shifted_remainder}-{1'b0,root_trial};
    wire signed [28:0] entry_signed=$signed(dot)-$signed({1'b0,root});
    wire signed [28:0] exit_signed=$signed(dot)+$signed({1'b0,root});
    wire [28:0] entry=entry_signed<=0 ? 29'd0 : entry_signed;
    reg found;
    reg [28:0] nearest;
    reg [7:0] nearest_tile, tile;
    reg [16:0] boundary_x, boundary_y;
    reg [25:0] cross_x, cross_y;
    reg take_x;
    reg [37:0] hit_boundary;
    reg [34:0] wall_boundary;
    integer slot;
    reg [7:0] zombie_tile;
    wire [31:0] zx = COORD_FRAC_BITS<=12 ?
        position_x[slot*W +: W] << (12-COORD_FRAC_BITS) :
        position_x[slot*W +: W] >> (COORD_FRAC_BITS-12);
    wire [31:0] zy = COORD_FRAC_BITS<=12 ?
        position_y[slot*W +: W] << (12-COORD_FRAC_BITS) :
        position_y[slot*W +: W] >> (COORD_FRAC_BITS-12);
    assign busy = state!=IDLE || hit_valid;
    `include "Ray_Tables.vh"
    always @(posedge clk) begin
        hit_valid<=0;
        if(reset || !enabled) begin
            state<=IDLE; hit_tile<=0; found<=0; slot<=0;
            ox<=0; oy<=0; sx<=0; sy<=0; ax<=0; ay<=0;
            norm<=0; dot<=0; direction_cross<=0; discriminant<=0;
            cross_sq<=0; radius_term<=0; circle_valid<=0;
            root<=0; remainder<=0; root_count<=0;
            cross_x<=0; cross_y<=0; take_x<=0; hit_boundary<=0; wall_boundary<=0; nearest<=0; nearest_tile<=0;
            boundary_x<=0; boundary_y<=0; tile<=0; heading<=0;
            dx<=0; dy<=0; zombie_tile<=0;
        end else case(state)
            IDLE: if(shot_fired) begin
                ox<=USE_CAMERA_RAY ? camera_x[17:0] : {2'd0,player_tile[3:0],12'h800};
                oy<=USE_CAMERA_RAY ? 18'd65536-camera_y[17:0] : {2'd0,player_tile[7:4],12'h800};
                // Cardinal legacy aim: east, south, west, north.
                heading<=USE_CAMERA_RAY ? camera_angle : (10'd256+{aim,8'd0});
                found<=0; slot<=0; state<=SETUP;
            end
            SETUP: begin
                sx<=sine_step(heading); sy<=-sine_step(heading+10'd256);
                state<=LOAD;
            end
            LOAD: begin
                ax<=sx<0 ? -sx : sx; ay<=sy<0 ? -sy : sy;
                norm<=sx*sx+sy*sy;
                dx<=$signed(zx[17:0])-ox; dy<=$signed(zy[17:0])-oy;
                zombie_tile<={position_y[slot*W+COORD_FRAC_BITS +:4],
                              position_x[slot*W+COORD_FRAC_BITS +:4]};
                state<=DOT;
            end
            DOT: begin
                dot<=dx*sx+dy*sy;
                direction_cross<=dx*sy-dy*sx;
                state<=DISC;
            end
            DISC: begin
                // a*r^2 - cross^2 equals dot^2 - a*(distance^2-r^2),
                // avoiding the wide variable a*distance^2 multiplication.
                cross_sq<=direction_cross*direction_cross;
                radius_term<=norm*RADIUS_SQ;
                state<=CALC;
            end
            CALC: begin
                discriminant<=radius_term-cross_sq;
                circle_valid<=radius_term>=cross_sq;
                root<=0; remainder<=0; root_count<=28; state<=ROOT;
            end
            ROOT: if(!active[slot] || !circle_valid) state<=NEXT;
            else begin
                remainder<=root_difference[30] ? shifted_remainder : root_difference[29:0];
                root<={root[26:0],!root_difference[30]};
                discriminant<=discriminant<<2;
                root_count<=root_count-1'b1;
                if(root_count==1) state<=PICK;
            end
            PICK: begin
                if(exit_signed>=0 && (!found || entry<nearest)) begin
                    found<=1; nearest<=entry; nearest_tile<=zombie_tile;
                end
                state<=NEXT;
            end
            NEXT: if(slot==MAX_ENEMIES-1) begin
                tile<={oy[15:12],ox[15:12]};
                boundary_x<=sx<0 ? {5'd0,ox[11:0]} : 17'd4096-{5'd0,ox[11:0]};
                boundary_y<=sy<0 ? {5'd0,oy[11:0]} : 17'd4096-{5'd0,oy[11:0]};
                state<=found && ox>=0 && oy>=0 && ox<65536 && oy<65536 ? TRACE : IDLE;
            end else begin slot<=slot+1; state<=LOAD; end
            TRACE: state<=walls[tile] ? IDLE : DDA_PRODUCTS;
            DDA_PRODUCTS: begin
                cross_x<=boundary_x*ay; cross_y<=boundary_y*ax;
                state<=DDA_CHOOSE;
            end
            DDA_CHOOSE: begin
                take_x<=ax!=0 && (ay==0 || cross_x<=cross_y);
                state<=DDA_LIMITS;
            end
            DDA_LIMITS: begin
                hit_boundary<=nearest*(take_x ? ax : ay);
                wall_boundary<=norm*(take_x ? boundary_x : boundary_y);
                state<=DDA_TEST;
            end
            DDA_TEST: if(hit_boundary<wall_boundary) begin
                hit_valid<=1; hit_tile<=nearest_tile; state<=IDLE;
            end else if(take_x) begin
                if((sx<0 && tile[3:0]==0) || (sx>0 && tile[3:0]==15)) state<=IDLE;
                else begin tile<=sx<0 ? tile-8'd1 : tile+8'd1; boundary_x<=boundary_x+17'd4096; state<=TRACE; end
            end else begin
                if((sy<0 && tile[7:4]==0) || (sy>0 && tile[7:4]==15)) state<=IDLE;
                else begin tile<=sy<0 ? tile-8'd16 : tile+8'd16; boundary_y<=boundary_y+17'd4096; state<=TRACE; end
            end
            default: state<=IDLE;
        endcase
    end
endmodule
