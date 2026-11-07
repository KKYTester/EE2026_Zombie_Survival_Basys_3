`timescale 1ns / 1ps
// Prepare SLOTS billboards in the back bank, then composite pixels serially.
// With HAS_ALLY=1 the last non-pickup slot is drawn as the other player.
// Damage and death (display only):
//  - hp (0..3 per slot): a 3-segment health bar above a damaged zombie
//    (hp 1 or 2); full-health zombies show no bar.
//  - dying + fall (0..15): a killed zombie is drawn tinted red and rotated
//    about its feet by fall*6 degrees, so it tips over sideways onto the floor.
// PICKUP_SLOTS (0 or 2): the last two slots are pickups, drawn as small icons
// floating just above the floor: a white medkit with a red cross (slot
// SLOTS-2) and a brass magazine (slot SLOTS-1). The ally, if any, is then the
// slot just before them.
module zombie_renderer #(
    parameter USE_CAMERA_POSE=0,
    parameter integer FOCAL_X=64,
    parameter integer FOCAL_Y=64,
    parameter integer SLOTS=8,             // 2..16 billboards
    parameter HAS_ALLY=0,
    parameter integer PICKUP_SLOTS=0       // 0 or 2
)(
    input wire clk, reset, prepare, display_bank, scene_valid,
    input wire [11:0] camera_x, camera_y,
    input wire [1:0] facing,
    input wire [9:0] camera_angle,
    input wire [SLOTS-1:0] active,
    input wire [12*SLOTS-1:0] zombie_x, zombie_y, // Packed Q8 tile coordinates, x right, y down.
    input wire [2*SLOTS-1:0] hp,          // hit points per slot (3 = full, no bar)
    input wire [SLOTS-1:0] dying,         // slot shows a falling corpse
    input wire [SLOTS-1:0] winding_up,    // amber warning on the live zombie
    input wire [4*SLOTS-1:0] fall,        // fall step, 0 upright .. 15 flat
    input wire [6:0] pixel_x,
    input wire [5:0] pixel_y,
    input wire [12:0] wall_depth,         // Forward Q8 depth; 4096 means no wall.
    input wire [15:0] background,
    output reg done,
    output reg [15:0] pixel
);
    localparam [2:0] P_IDLE=0, P_READ=1, P_ROTATE=2, P_SCALE=3,
                     P_PROJECT=4, P_STORE=5, P_DOT=6;
    localparam integer SB = (SLOTS>8) ? 4 : (SLOTS>4) ? 3 : (SLOTS>2) ? 2 : 1;
    localparam integer ENTRIES = 2 << SB;   // two banks
    reg [2:0] project_state;
    reg [SB-1:0] slot;
    reg write_bank;
    reg [11:0] origin_x, origin_y;
    reg [1:0] direction;
    reg [SLOTS-1:0] snapshot_active;
    reg [12*SLOTS-1:0] snapshot_x, snapshot_y;
    reg [2*SLOTS-1:0] snapshot_hp;
    reg [SLOTS-1:0] snapshot_dying;
    reg [4*SLOTS-1:0] snapshot_fall;
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
    reg [ENTRIES-1:0] valid;
    reg [12:0] depths [0:ENTRIES-1];
    reg signed [15:0] centers [0:ENTRIES-1];
    reg [7:0] heights [0:ENTRIES-1];
    reg [1:0] hps [0:ENTRIES-1];
    reg [ENTRIES-1:0] dyings;
    reg [ENTRIES-1:0] windups;
    reg [SLOTS-1:0] snapshot_windup;
    reg [3:0] falls [0:ENTRIES-1];
    wire [SB:0] write_slot = {write_bank,slot};

    always @(posedge clk) begin
        if(reset) begin project_state<=P_IDLE; done<=0; valid<=0; end
        else case(project_state)
            P_IDLE: if(prepare) begin
                snapshot_active<=active; snapshot_x<=zombie_x; snapshot_y<=zombie_y;
                snapshot_hp<=hp; snapshot_dying<=dying; snapshot_fall<=fall;
                snapshot_windup<=winding_up;
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
                hps[write_slot]<=snapshot_hp[2*slot +: 2];
                dyings[write_slot]<=snapshot_dying[slot];
                windups[write_slot]<=snapshot_windup[slot];
                falls[write_slot]<=snapshot_fall[4*slot +: 4];
                if(slot==SLOTS-1) begin done<=1; project_state<=P_IDLE; end
                else begin slot<=slot+1'b1; project_state<=P_READ; end
            end
            default: project_state<=P_IDLE;
        endcase
    end

    localparam [2:0] PIX_IDLE=0, PIX_READ=1, PIX_OFFSET=2, PIX_ROT=5, PIX_SUM=6, PIX_SHAPE=3, PIX_DRAW=4;
    // sin(step*6 degrees) * 128 for the fall rotation (step 15 = 90 degrees).
    function signed [8:0] fall_sin;
        input [3:0] step;
        case(step)
            4'd0: fall_sin=0;    4'd1: fall_sin=13;   4'd2: fall_sin=27;   4'd3: fall_sin=40;
            4'd4: fall_sin=52;   4'd5: fall_sin=64;   4'd6: fall_sin=75;   4'd7: fall_sin=86;
            4'd8: fall_sin=95;   4'd9: fall_sin=104;  4'd10: fall_sin=111; 4'd11: fall_sin=117;
            4'd12: fall_sin=122; 4'd13: fall_sin=125; 4'd14: fall_sin=127; default: fall_sin=128;
        endcase
    endfunction
    reg [2:0] pixel_state;
    reg [6:0] req_x;
    reg [5:0] req_y;
    reg req_bank, req_scene, req_valid;
    reg [SB-1:0] scan;
    reg candidate_valid;
    reg [12:0] candidate_depth, best_depth;
    reg signed [15:0] candidate_center;
    reg [7:0] candidate_height;
    reg [15:0] best_color;
    wire [SB:0] read_slot = {req_bank,scan};
    reg candidate_ally, candidate_dying, candidate_windup, candidate_health, candidate_mag;
    reg [1:0] candidate_hp;
    reg [3:0] candidate_fall;
    reg signed [16:0] local_x;
    // Unrotated position inside the sprite (row 0 = top of the head).
    wire signed [9:0] local_y = $signed({4'd0,req_y})-10'sd32+
                               $signed({3'd0,candidate_height[7:1]});
    // Death fall: rotate the screen offset back into the upright sprite,
    // pivoting on the feet (up = height above the feet row).
    reg signed [8:0] f_sin, f_cos;
    // As it tips over, lift the body by half its thickness so it lands on
    // the floor instead of half below it.
    reg [7:0] lift;
    // Pipelined for timing: OFFSET registers the height above the feet
    // (up_base), ROT registers the four products, SUM adds them.
    reg signed [10:0] up_base;
    wire signed [10:0] up = up_base - $signed({3'd0,lift});
    wire signed [12:0] lx_c = local_x[12:0];
    reg signed [21:0] p_xc, p_us, p_xs, p_uc;   // lx*cos, up*sin, lx*sin, up*cos
    wire signed [22:0] rot_x_full = p_xc - p_us;
    wire signed [22:0] rot_up_full = p_xs + p_uc;
    reg signed [16:0] shape_x;   // sprite-space column offset (rotated when dying)
    reg signed [9:0] shape_y;    // sprite-space row (rotated when dying)
    wire [16:0] abs_x = shape_x<0 ? -shape_x : shape_x;
    wire [7:0] half_width = candidate_height>>2;
    wire [7:0] head_height = candidate_height>>2;
    wire [7:0] legs_start = candidate_height-(candidate_height>>2);
    wire [7:0] head_width = half_width-(half_width>>2);
    reg opaque;
    reg [15:0] sprite_color;
    // Health bar: 9 pixels wide (3 per hit point), 2 rows, one row above the head.
    wire show_bar = !candidate_ally && !candidate_health && !candidate_mag &&
                    !candidate_dying && candidate_hp!=2'd0 && candidate_hp!=2'd3;
    // Pickup icon: half-size h, centred 2h above the feet row.
    wire [7:0] icon_h = (candidate_height>>3) + 8'd1;
    wire signed [9:0] icon_dy_raw = shape_y - ($signed({2'd0,candidate_height}) - 10'sd1
                                               - $signed({1'b0,icon_h,1'b0}));
    wire [9:0] icon_dy = icon_dy_raw<0 ? -icon_dy_raw : icon_dy_raw;
    wire [7:0] icon_third = icon_h/3;
    wire in_icon_box = abs_x<={9'd0,icon_h} && icon_dy<={2'd0,icon_h};
    wire in_cross = abs_x<={9'd0,icon_third} || icon_dy<={2'd0,icon_third};
    wire in_mag = abs_x<={9'd0,icon_h>>1} && icon_dy<={2'd0,icon_h};
    wire bar_row = shape_y==-10'sd3 || shape_y==-10'sd2;
    wire bar_col = shape_x>=-17'sd4 && shape_x<=17'sd4;
    wire [1:0] bar_segment = shape_x<-17'sd1 ? 2'd1 : shape_x<=17'sd1 ? 2'd2 : 2'd3;
    reg [15:0] body_color;
    always @* begin
        opaque=0; body_color=0;
        if(shape_y>=0 && shape_y<$signed({2'd0,candidate_height}) && abs_x<half_width) begin
            if(shape_y<$signed({2'd0,head_height})) begin
                opaque=abs_x<head_width;
                // Zombie: green head, yellow eyes. Player: skin head, dark eyes.
                body_color=(shape_y== $signed({3'd0,head_height[7:1]}) && abs_x!=0)
                             ? (candidate_ally ? 16'h2104 : 16'hffe0)
                             : (candidate_ally ? 16'hEDB0 : 16'h57c5);
            end else if(shape_y<$signed({2'd0,legs_start})) begin
                opaque=1; body_color=candidate_ally ? 16'h1A9F : 16'h8816;  // blue / purple
            end else begin
                opaque=abs_x>=(half_width>>2); body_color=candidate_ally ? 16'h4208 : 16'h294a;
            end
        end
        sprite_color=body_color;
        if(candidate_windup && !candidate_ally) sprite_color=16'hFD20;
        // Dying: Minecraft-style red tint (full red, green and blue darkened).
        if(candidate_dying) sprite_color={5'h1F, 1'b0, body_color[10:6], 1'b0, body_color[4:1]};
        if(candidate_health) begin
            opaque=in_icon_box;
            sprite_color=in_cross ? 16'hF800 : 16'hFFFF;            // red cross on white
        end else if(candidate_mag) begin
            opaque=in_mag;
            sprite_color=(icon_dy==10'd0) ? 16'h4208 : 16'hFD20;    // brass, dark seam
        end
        if(show_bar && bar_row && bar_col) begin
            opaque=1;
            sprite_color=(bar_segment<=candidate_hp) ? 16'h07E0 : 16'h8000;  // green / dark red
        end
    end
    wire covers_pixel = candidate_valid && opaque && candidate_depth<best_depth;
    reg draw_candidate;
    reg [15:0] draw_color;

    // The OLED holds each request long enough to scan all slots (6 clocks each;
    // 11 slots = 66 clocks, well inside one OLED pixel of 256 clocks).
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
                candidate_ally<=HAS_ALLY && scan==SLOTS-1-PICKUP_SLOTS;
                candidate_health<=PICKUP_SLOTS!=0 && scan==SLOTS-2;
                candidate_mag<=PICKUP_SLOTS!=0 && scan==SLOTS-1;
                candidate_hp<=hps[read_slot]; candidate_dying<=dyings[read_slot];
                candidate_windup<=windups[read_slot];
                candidate_fall<=falls[read_slot];
                pixel_state<=PIX_OFFSET;
            end
            PIX_OFFSET: begin
                local_x<=$signed({10'd0,req_x})-candidate_center;
                f_sin<=fall_sin(candidate_fall);
                f_cos<=fall_sin(4'd15-candidate_fall);
                lift<=(candidate_height[7:2]*fall_sin(candidate_fall))>>7;  // half_width*sin
                up_base<=$signed({3'd0,candidate_height}) - 11'sd1 - $signed({local_y[9],local_y});
                pixel_state<=PIX_ROT;
            end
            PIX_ROT: begin
                p_xc<=lx_c*f_cos; p_us<=up*f_sin;
                p_xs<=lx_c*f_sin; p_uc<=up*f_cos;
                pixel_state<=PIX_SUM;
            end
            PIX_SUM: begin
                if(candidate_dying) begin
                    shape_x<=rot_x_full>>>7;
                    shape_y<=$signed({1'b0,candidate_height}) - 10'sd1 - (rot_up_full>>>7);
                end else begin
                    shape_x<=local_x; shape_y<=local_y;
                end
                pixel_state<=PIX_SHAPE;
            end
            PIX_SHAPE: begin
                draw_candidate<=covers_pixel; draw_color<=sprite_color;
                pixel_state<=PIX_DRAW;
            end
            PIX_DRAW: begin
                if(draw_candidate) begin best_depth<=candidate_depth; best_color<=draw_color; end
                if(scan==SLOTS-1) begin
                    pixel<=draw_candidate ? draw_color : best_color;
                    pixel_state<=PIX_IDLE;
                end else begin scan<=scan+1'b1; pixel_state<=PIX_READ; end
            end
            default: pixel_state<=PIX_IDLE;
        endcase
    end
endmodule
