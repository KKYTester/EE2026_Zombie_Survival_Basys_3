`timescale 1ns / 1ps
// Prepare eight billboards in the back bank, then composite pixels serially.
module zombie_renderer #(
    parameter USE_CAMERA_POSE=0,
    parameter integer FOCAL_X=64,
    parameter integer FOCAL_Y=64
)(
    input wire clk, reset, prepare, display_bank, scene_valid,
    input wire [11:0] camera_x, camera_y,
    input wire [1:0] facing,
    input wire [9:0] camera_angle,
    input wire [7:0] active,
    input wire [95:0] zombie_x, zombie_y, // Eight packed Q8 tile coordinates.
    input wire [6:0] pixel_x,
    input wire [5:0] pixel_y,
    input wire [12:0] wall_depth,         // Forward Q8 depth; 4096 means no wall.
    input wire [15:0] background,
    output reg done,
    output reg [15:0] pixel
);
    localparam [2:0] P_IDLE=0, P_READ=1, P_ROTATE=2, P_SCALE=3,
                     P_PROJECT=4, P_STORE=5, P_DOT=6;
    reg [2:0] project_state, slot;
    reg write_bank;
    reg [11:0] origin_x, origin_y;
    reg [1:0] direction;
    reg [7:0] snapshot_active;
    reg [95:0] snapshot_x, snapshot_y;
    reg signed [12:0] dx, dy;
    reg signed [13:0] forward, side;
    reg signed [15:0] scale, vertical_scale;
    reg signed [29:0] offset;
    reg signed [8:0] sine, cosine;
    reg signed [21:0] dx_sin, dy_cos, dx_cos, dy_sin;
    reg [14:0] scale_rom [0:255], height_rom [0:255];
    `include "Ray_Tables.vh"
    integer i;
    initial begin
        scale_rom[0]=0;
        height_rom[0]=0;
        for(i=1;i<256;i=i+1) begin
            scale_rom[i]=(FOCAL_X*(USE_CAMERA_POSE ? 128 : 256))/i;
            height_rom[i]=(FOCAL_Y*(USE_CAMERA_POSE ? 128 : 256))/i;
        end
    end
    // Focal length 64 pixels. ROM entries are Q4 pixels per tile.
    wire [7:0] depth_index = USE_CAMERA_POSE ? forward[12:5] : forward[11:4];
    wire [11:0] raw_height = vertical_scale[15:4];
    wire [7:0] height = raw_height>128 ? 8'd128 : raw_height[7:0];
    wire signed [15:0] center = 16'sd48 + (offset >>> 12);
    reg [15:0] valid;
    reg [12:0] depths [0:15];
    reg signed [15:0] centers [0:15];
    reg [7:0] heights [0:15];
    wire [3:0] write_slot = {write_bank,slot};

    always @(posedge clk) begin
        if(reset) begin project_state<=P_IDLE; done<=0; valid<=0; end
        else case(project_state)
            P_IDLE: if(prepare) begin
                snapshot_active<=active; snapshot_x<=zombie_x; snapshot_y<=zombie_y;
                origin_x<=camera_x; origin_y<=camera_y; direction<=facing;
                sine<=sine_step(camera_angle);
                cosine<=sine_step(camera_angle+10'd256);
                write_bank<=!display_bank; slot<=0; done<=0; project_state<=P_READ;
            end
            P_READ: begin
                dx<=$signed({1'b0,snapshot_x[12*slot +: 12]})-$signed({1'b0,origin_x});
                dy<=$signed({1'b0,snapshot_y[12*slot +: 12]})-$signed({1'b0,origin_y});
                project_state<=P_ROTATE;
            end
            P_ROTATE: begin
                if(USE_CAMERA_POSE) begin
                    dx_sin<=dx*sine; dy_cos<=dy*cosine;
                    dx_cos<=dx*cosine; dy_sin<=dy*sine;
                end else case(direction)
                    2'd0: begin forward<=dx;  side<=dy; end
                    2'd1: begin forward<=dy;  side<=-dx; end
                    2'd2: begin forward<=-dx; side<=-dy; end
                    2'd3: begin forward<=-dy; side<=dx; end
                endcase
                project_state<=USE_CAMERA_POSE ? P_DOT : P_SCALE;
            end
            P_DOT: begin
                // Input positions use y down, while camera angle zero is north.
                forward<=($signed({dx_sin[21],dx_sin})-$signed({dy_cos[21],dy_cos})) >>> 7;
                side<=($signed({dx_cos[21],dx_cos})+$signed({dy_sin[21],dy_sin})) >>> 7;
                project_state<=P_SCALE;
            end
            P_SCALE: begin
                scale<={1'b0,scale_rom[depth_index]};
                vertical_scale<={1'b0,height_rom[depth_index]};
                project_state<=P_PROJECT;
            end
            P_PROJECT: begin offset<=side*scale; project_state<=P_STORE; end
            P_STORE: begin
                valid[write_slot]<=snapshot_active[slot] && forward>=(USE_CAMERA_POSE ? 32 : 16);
                centers[write_slot]<=center;
                heights[write_slot]<=height;
                depths[write_slot]<=forward;
                if(slot==7) begin done<=1; project_state<=P_IDLE; end
                else begin slot<=slot+1'b1; project_state<=P_READ; end
            end
            default: project_state<=P_IDLE;
        endcase
    end

    localparam [2:0] PIX_IDLE=0, PIX_READ=1, PIX_OFFSET=2, PIX_SHAPE=3, PIX_DRAW=4;
    reg [2:0] pixel_state;
    reg [6:0] req_x;
    reg [5:0] req_y;
    reg req_bank, req_scene, req_valid;
    reg [2:0] scan;
    reg candidate_valid;
    reg [12:0] candidate_depth, best_depth;
    reg signed [15:0] candidate_center;
    reg [7:0] candidate_height;
    reg [15:0] best_color;
    wire [3:0] read_slot = {req_bank,scan};
    reg signed [16:0] local_x;
    wire [16:0] abs_x = local_x<0 ? -local_x : local_x;
    wire signed [9:0] local_y = $signed({4'd0,req_y})-10'sd32+
                               $signed({3'd0,candidate_height[7:1]});
    wire [7:0] half_width = candidate_height>>2;
    wire [7:0] head_height = candidate_height>>2;
    wire [7:0] legs_start = candidate_height-(candidate_height>>2);
    wire [7:0] head_width = half_width-(half_width>>2);
    reg opaque;
    reg [15:0] sprite_color;
    always @* begin
        opaque=0; sprite_color=0;
        if(local_y>=0 && local_y<$signed({2'd0,candidate_height}) && abs_x<half_width) begin
            if(local_y<$signed({2'd0,head_height})) begin
                opaque=abs_x<head_width;
                sprite_color=(local_y== $signed({3'd0,head_height[7:1]}) && abs_x!=0)
                             ? 16'hffe0 : 16'h57c5;
            end else if(local_y<$signed({2'd0,legs_start})) begin
                opaque=1; sprite_color=16'h8816;
            end else begin
                opaque=abs_x>=(half_width>>2); sprite_color=16'h294a;
            end
        end
    end
    wire covers_pixel = candidate_valid && opaque && candidate_depth<best_depth;
    reg draw_candidate;
    reg [15:0] draw_color;

    // The OLED holds each request long enough to scan all eight slots.
    always @(posedge clk) begin
        if(reset) begin pixel_state<=PIX_IDLE; req_valid<=0; pixel<=0; end
        else if(!req_valid || req_x!=pixel_x || req_y!=pixel_y ||
                req_bank!=display_bank || req_scene!=scene_valid) begin
            req_x<=pixel_x; req_y<=pixel_y; req_bank<=display_bank;
            req_scene<=scene_valid; req_valid<=1;
            best_depth<=wall_depth; best_color<=background;
            scan<=0; pixel_state<=scene_valid ? PIX_READ : PIX_IDLE;
            if(!scene_valid) pixel<=background;
        end else case(pixel_state)
            PIX_READ: begin
                candidate_valid<=valid[read_slot]; candidate_depth<=depths[read_slot];
                candidate_center<=centers[read_slot]; candidate_height<=heights[read_slot];
                pixel_state<=PIX_OFFSET;
            end
            PIX_OFFSET: begin
                local_x<=$signed({10'd0,req_x})-candidate_center;
                pixel_state<=PIX_SHAPE;
            end
            PIX_SHAPE: begin
                draw_candidate<=covers_pixel; draw_color<=sprite_color;
                pixel_state<=PIX_DRAW;
            end
            PIX_DRAW: begin
                if(draw_candidate) begin best_depth<=candidate_depth; best_color<=draw_color; end
                if(scan==7) begin
                    pixel<=draw_candidate ? draw_color : best_color;
                    pixel_state<=PIX_IDLE;
                end else begin scan<=scan+1'b1; pixel_state<=PIX_READ; end
            end
            default: pixel_state<=PIX_IDLE;
        endcase
    end
endmodule
