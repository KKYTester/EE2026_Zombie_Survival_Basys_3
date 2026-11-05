`timescale 1ns / 1ps
`include "Game_Config.vh"

// All logic uses the board clock. A tick launches a six-cycle movement update;
// the renderer snapshots the last committed position/angle atomically.
module Player_Controller #(
    parameter [255:0] MAP = `GAME_MAP,
    parameter integer DEBOUNCE_CYCLES = `GAME_BUTTON_DEBOUNCE_CYCLES,
    parameter [31:0] START_X = `GAME_SPAWN_X,
    parameter [31:0] START_Y = `GAME_SPAWN_Y,
    parameter [31:0] START_ANGLE = `GAME_SPAWN_ANGLE
) (
    input wire clk, reset, game_tick,
    input wire btnU, btnL, btnR, btnD,
    // Mouse_Control_Delta outputs share this 100 MHz clock; valid on mouse_event.
    input wire signed [8:0] mouse_x_delta,
    input wire mouse_event,
    output wire [31:0] x_coord, y_coord, theta
);
    wire forward_down, back_down, left_down, right_down;
    Button_Debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) forward_button
        (.clk(clk), .reset(reset), .button(btnU), .pressed(forward_down));
    Button_Debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) back_button
        (.clk(clk), .reset(reset), .button(btnD), .pressed(back_down));
    Button_Debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) left_button
        (.clk(clk), .reset(reset), .button(btnL), .pressed(left_down));
    Button_Debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) right_button
        (.clk(clk), .reset(reset), .button(btnR), .pressed(right_down));

    // One x count = one clockwise angle unit. Accumulate every packet once,
    // including between ticks and during movement; truncation wraps modulo 1024.
    // Sign-extend before addition so negative 9-bit deltas turn left correctly.
    // An event coinciding with a tick is retained for the following update.
    reg [9:0] target_angle;
    wire [9:0] mouse_angle_delta = {mouse_x_delta[8], mouse_x_delta};
    always @(posedge clk) begin
        if (reset) target_angle <= START_ANGLE[9:0];
        else if (mouse_event) target_angle <= target_angle + mouse_angle_delta;
    end

    `include "Ray_Tables.vh"
    wire [9:0] cosine_angle = target_angle + 10'd256;
    wire signed [8:0] sin_direction = sine_step(target_angle);
    wire signed [8:0] cos_direction = sine_step(cosine_angle);
    // sine_step has magnitude 128. Shift by two for 512 Q*.12 units/tick:
    // 1/8 cell at 24 Hz = 3 cells/sec. Opposing directions cancel per axis.
    wire signed [12:0] sin_move = $signed({{4{sin_direction[8]}},sin_direction}) <<< `GAME_MOVE_SHIFT;
    wire signed [12:0] cos_move = $signed({{4{cos_direction[8]}},cos_direction}) <<< `GAME_MOVE_SHIFT;
    // Pipeline direction lookup, vector arithmetic, and position addition.
    reg signed [12:0] saved_sin, saved_cos, step_x, step_y;
    reg saved_forward, saved_back, saved_left, saved_right;
    wire forward_active = saved_forward ^ saved_back;
    wire strafe_active = saved_left ^ saved_right;
    reg signed [12:0] move_x, move_y;
    always @* begin
        move_x = 0;
        move_y = 0;
        if (forward_active) begin
            move_x = saved_forward ? saved_sin : -saved_sin;
            move_y = saved_forward ? saved_cos : -saved_cos;
        end
        if (strafe_active) begin
            move_x = move_x + (saved_right ? saved_cos : -saved_cos);
            move_y = move_y + (saved_right ? -saved_sin : saved_sin);
        end
        // Cheap diagonal scaling: 3/4 (about 6% faster than a single axis).
        if (forward_active && strafe_active) begin
            move_x = (move_x + (move_x <<< 1)) >>> 2;
            move_y = (move_y + (move_y <<< 1)) >>> 2;
        end
    end

    // A square 1/4-cell-wide body. Four corner checks suffice because both
    // body width and maximum per-axis step are less than one map cell.
    // Out-of-map coordinates are solid, before any variable map-bit access.
    function cell_open;
        input signed [17:0] x, y;
        begin
            if (x < 0 || y < 0 || x >= 18'sd65536 || y >= 18'sd65536)
                cell_open = 0;
            else cell_open = !MAP[{y[15:12],x[15:12]}];
        end
    endfunction
    function body_open;
        input signed [17:0] x, y;
        begin
            body_open = cell_open(x - `GAME_PLAYER_RADIUS, y - `GAME_PLAYER_RADIUS) &&
                        cell_open(x + `GAME_PLAYER_RADIUS, y - `GAME_PLAYER_RADIUS) &&
                        cell_open(x - `GAME_PLAYER_RADIUS, y + `GAME_PLAYER_RADIUS) &&
                        cell_open(x + `GAME_PLAYER_RADIUS, y + `GAME_PLAYER_RADIUS);
        end
    endfunction

    localparam [2:0] IDLE=0, VECTOR=1, POSITION=2, CHECK_X=3, CHECK_Y=4, COMMIT=5;
    reg [2:0] state;
    reg signed [17:0] candidate_x, candidate_y, accepted_x;
    reg [31:0] dx, dy;
    reg [9:0] update_angle;
    wire [9:0] angle_delta = update_angle - theta[9:0];
    Player #(.START_X(START_X), .START_Y(START_Y), .START_ANGLE(START_ANGLE)) player (
        .clk(clk), .reset(reset), .game_tick(state == COMMIT),
        .dx(dx), .dy(dy), .omega({22'd0,angle_delta}),
        .x_coord(x_coord), .y_coord(y_coord), .theta(theta)
    );
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            candidate_x <= 0;
            candidate_y <= 0;
            accepted_x <= 0;
            dx <= 0;
            dy <= 0;
            saved_sin <= 0;
            saved_cos <= 0;
            step_x <= 0;
            step_y <= 0;
            saved_forward <= 0;
            saved_back <= 0;
            saved_left <= 0;
            saved_right <= 0;
            update_angle <= START_ANGLE[9:0];
        end else begin
            case (state)
                IDLE: if (game_tick) begin
                    saved_sin <= sin_move;
                    saved_cos <= cos_move;
                    saved_forward <= forward_down;
                    saved_back <= back_down;
                    saved_left <= left_down;
                    saved_right <= right_down;
                    update_angle <= target_angle;
                    state <= VECTOR;
                end
                VECTOR: begin
                    step_x <= move_x;
                    step_y <= move_y;
                    state <= POSITION;
                end
                POSITION: begin
                    candidate_x <= $signed(x_coord[17:0]) + {{5{step_x[12]}},step_x};
                    candidate_y <= $signed(y_coord[17:0]) + {{5{step_y[12]}},step_y};
                    state <= CHECK_X;
                end
                CHECK_X: begin
                    if (body_open(candidate_x, $signed(y_coord[17:0]))) begin
                        accepted_x <= candidate_x;
                        dx <= {{14{candidate_x[17]}},candidate_x} - x_coord;
                    end else begin
                        accepted_x <= x_coord[17:0];
                        dx <= 0;
                    end
                    state <= CHECK_Y;
                end
                CHECK_Y: begin
                    if (body_open(accepted_x, candidate_y))
                        dy <= {{14{candidate_y[17]}},candidate_y} - y_coord;
                    else dy <= 0;
                    state <= COMMIT;
                end
                COMMIT: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
