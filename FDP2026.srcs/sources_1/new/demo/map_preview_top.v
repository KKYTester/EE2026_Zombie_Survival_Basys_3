`timescale 1ns / 1ps
// Single-player demo: title -> generating -> countdown -> playing -> game over -> title.
// Playing shows the first-person placeholder with the HUD (wave, 3 hearts,
// crosshair, zombies left); SW0 overlays the map with zombies as red dots.
// wave_controller spawns waves of zombies. A pistol is held at the bottom of the
// view; left-click or btnC fires (recoil + muzzle flash, shot_fired for combat).
// Test controls during play (stand-ins until combat exists): btnD = lose a heart,
// btnR = defeat the oldest zombie.
module map_preview_top #(parameter STAGE=3, parameter DEBOUNCE_CYCLES=1000000,
    parameter USE_MOUSE=1, parameter ENABLE_2P=0,
    parameter GEN_SHIFT=26, parameter COUNT_SHIFT=26, parameter OVER_SHIFT=27,
    parameter TINT_SHIFT=25, parameter BANNER_SHIFT=27, parameter BLINK_SHIFT=24,
    parameter SPAWN_SHIFT=26, parameter CLEAR_SHIFT=27,
    parameter FLASH_SHIFT=22, parameter RECOIL_SHIFT=23)(
    input wire clk, input wire sw0, input wire btnC, input wire btnU,
    input wire btnL, input wire btnR, input wire btnD,
    inout wire PS2Clk, inout wire PS2Data,
    output wire [15:0] led, output wire [7:0] JB,
    output wire [6:0] seg, output wire dp, output wire [3:0] an);
    // ASSUMPTION: EE2026 Pmod OLEDrgb on JB, as in the supplied lab project.
    // FPGA power-up initialisation; all functional resets below are synchronous.
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync=2'b11;
    (* ASYNC_REG="TRUE" *) reg [1:0] switch_sync=0;
    reg [3:0] clk_div=0;
    wire oled_clk=clk_div[3];
    wire rst=reset_sync[1];
    reg [5:0] oled_reset_hold=63;
    wire oled_reset=oled_reset_hold!=0;
    always @(posedge clk) begin
        reset_sync<={reset_sync[0],btnU};
        switch_sync<={switch_sync[0],sw0};
        // Never stop/reset the divided clock while resetting its consumers.
        clk_div<=clk_div+1'b1;
        if(rst) oled_reset_hold<=63;
        else if(oled_reset_hold!=0) oled_reset_hold<=oled_reset_hold-1'b1;
    end

    // ---------------- Buttons ----------------
    wire press_c,press_l,press_r,press_d;
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_filter(
        .clk(clk),.rst(rst),.button(btnC),.pressed(press_c));
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_left(
        .clk(clk),.rst(rst),.button(btnL),.pressed(press_l));
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_right(
        .clk(clk),.rst(rst),.button(btnR),.pressed(press_r));
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_down(
        .clk(clk),.rst(rst),.button(btnD),.pressed(press_d));

    // ---------------- Mouse ----------------
    // Simulation hook: with USE_MOUSE=0 a testbench drives these registers.
    reg [6:0] sim_mouse_x=48; reg [5:0] sim_mouse_y=40;
    reg sim_mouse_left=0, sim_mouse_event=0;
    wire [6:0] mouse_x; wire [5:0] mouse_y;
    wire mouse_left, mouse_event;
    generate if(USE_MOUSE) begin : g_mouse
        wire [11:0] xpos,ypos;
        wire [3:0] zpos;
        wire left_btn,middle_btn,right_btn,new_event;
        reg [11:0] value=0;
        reg setx=0,sety=0,setmax_x=0,setmax_y=0;
        reg [2:0] init_step=0;
        // After reset, limit the pointer to the 96x64 screen and centre it.
        always @(posedge clk) begin
            setx<=0; sety<=0; setmax_x<=0; setmax_y<=0;
            if(rst) init_step<=0;
            else if(init_step!=5) begin
                init_step<=init_step+1'b1;
                case(init_step)
                    1: begin value<=12'd95; setmax_x<=1; end
                    2: begin value<=12'd63; setmax_y<=1; end
                    3: begin value<=12'd48; setx<=1; end
                    4: begin value<=12'd40; sety<=1; end
                    default: ;
                endcase
            end
        end
        MouseCtl mouse(.clk(clk),.rst(rst),.xpos(xpos),.ypos(ypos),.zpos(zpos),
            .left(left_btn),.middle(middle_btn),.right(right_btn),.new_event(new_event),
            .value(value),.setx(setx),.sety(sety),.setmax_x(setmax_x),.setmax_y(setmax_y),
            .ps2_clk(PS2Clk),.ps2_data(PS2Data));
        assign mouse_x = (xpos>12'd95) ? 7'd95 : xpos[6:0];
        assign mouse_y = (ypos>12'd63) ? 6'd63 : ypos[5:0];
        assign mouse_left = left_btn;
        assign mouse_event = new_event;
    end else begin : g_no_mouse
        assign mouse_x = sim_mouse_x; assign mouse_y = sim_mouse_y;
        assign mouse_left = sim_mouse_left; assign mouse_event = sim_mouse_event;
    end endgenerate

    // ---------------- Game flow, map and play state ----------------
    wire [255:0] published_map;
    wire [7:0] p1_addr,p2_addr;
    wire ready,busy;
    wire [2:0] error_code,retry_count;
    wire [15:0] seed;
    wire [2:0] flow_state;
    wire [1:0] count_digit;
    wire menu_sel,regenerate,play_start,over_ready;
    wire [5:0] progress;
    wire [1:0] health;
    wire [6:0] wave;
    wire damage,tint,banner,low_blink;
    wire spawn_req,spawn_ack,enemy_defeated,wave_clear;
    wire [7:0] spawn_tile;
    wire [5:0] alive;
    wire [6:0] remaining;
    wire [255:0] zombies;
    wire playing_now = flow_state==3'd3;
    // Fire: a new left-click or btnC during play. The menu never sees play clicks.
    reg mouse_left_prev;
    always @(posedge clk) mouse_left_prev <= rst ? 1'b0 : mouse_left;
    wire fire_request = playing_now && (press_c || (mouse_left && !mouse_left_prev));
    wire weapon_flash, weapon_recoil, shot_fired;
    // Free-running seed source: the time spent on the title screen picks the map.
    reg [15:0] seed_counter;
    always @(posedge clk) if(rst) seed_counter<=1; else seed_counter<=seed_counter+1'b1;
    game_flow #(.ENABLE_2P(ENABLE_2P),.GEN_SHIFT(GEN_SHIFT),.COUNT_SHIFT(COUNT_SHIFT),
        .OVER_SHIFT(OVER_SHIFT)) flow(
        .clk(clk),.rst(rst),.btn_c(press_c),.btn_l(press_l),.btn_r(press_r),
        .mouse_x(mouse_x),.mouse_y(mouse_y),.mouse_left(mouse_left),.mouse_event(mouse_event),
        .map_ready(ready),.map_busy(busy),.health_zero(health==2'd0),
        .state(flow_state),.sel(menu_sel),.regenerate(regenerate),.play_start(play_start),
        .count_digit(count_digit),.progress(progress),.over_ready(over_ready));
    play_test_inputs test_inputs(.clk(clk),.rst(rst),.play_start(play_start),
        .playing(playing_now),.btn_d(press_d),.health(health),.damage(damage));
    // Waves and spawning. The player tile is the P1 spawn until movement exists.
    wave_controller #(.SPAWN_SHIFT(SPAWN_SHIFT),.CLEAR_SHIFT(CLEAR_SHIFT)) waves(
        .clk(clk),.rst(rst),.play_start(play_start),.playing(playing_now),
        .map_bits(published_map),.occupied(zombies),.player_tile(p1_addr),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.wave(wave),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.alive(alive),
        .remaining(remaining),.wave_clear(wave_clear));
    zombie_stub enemies(.clk(clk),.rst(rst),.clear(play_start || !playing_now),
        .spawn_req(spawn_req),.spawn_tile(spawn_tile),.defeat(press_r && playing_now),
        .spawn_ack(spawn_ack),.enemy_defeated(enemy_defeated),.occupied(zombies));
    hud_effects_ctrl #(.TINT_SHIFT(TINT_SHIFT),.BANNER_SHIFT(BANNER_SHIFT),
        .BLINK_SHIFT(BLINK_SHIFT)) effects_ctrl(
        .clk(clk),.rst(rst),.playing(playing_now),.play_start(play_start),.damage(damage),
        .wave(wave),.health(health),.tint(tint),.banner(banner),.low_blink(low_blink));
    weapon_ctrl #(.FLASH_SHIFT(FLASH_SHIFT),.RECOIL_SHIFT(RECOIL_SHIFT)) weapon(
        .clk(clk),.rst(rst),.playing(playing_now),.fire(fire_request),
        .flash(weapon_flash),.recoil(weapon_recoil),.shot_fired(shot_fired));
    map_system #(.STAGE(STAGE)) core(.clk(clk),.rst(rst),.regenerate(regenerate),
        .seed_in(seed_counter),.published_map(published_map),.p1_addr(p1_addr),
        .p2_addr(p2_addr),.map_ready(ready),.busy(busy),.error_code(error_code),
        .active_seed(seed),.retry_count(retry_count));
    assign led={busy,11'b0,error_code,ready};
    seven_seg_hex seed_display(.clk(clk),.rst(rst),.value(seed),
        .seg(seg),.dp(dp),.an(an));

    // ---------------- Display ----------------
    wire frame_begin,sending_pixels,sample_pixel;
    wire [12:0] pixel_index;
    // The only pixel-index coordinate conversion. Tile lookup below uses slices.
    wire [6:0] px=pixel_index % 96;
    wire [5:0] py=pixel_index / 96;
    reg [255:0] frame_map;
    reg [7:0] frame_p1,frame_p2;
    reg [15:0] frame_seed;
    reg [1:0] frame_health;
    reg [6:0] frame_wave,frame_remaining;
    reg [255:0] frame_zombies;
    reg frame_clear,frame_flash,frame_recoil;
    reg frame_ready,frame_busy,frame_mode;
    reg [2:0] frame_error;
    reg [2:0] frame_screen;
    reg [1:0] frame_digit;
    reg frame_sel,frame_tint,frame_banner,frame_blink,frame_over_ready;
    reg [6:0] frame_cx; reg [5:0] frame_cy;
    reg [5:0] frame_progress;
    // Related clocks, explicitly constrained in XDC, not asynchronous CDC.
    // The supplied driver updates frame_begin on negedge; capture on posedge
    // so the next negedge samples a coherent frame and its first pixel.
    always @(posedge oled_clk) begin
        if(oled_reset) begin
            frame_map<={256{1'b1}}; frame_p1<=0; frame_p2<=0; frame_seed<=0;
            frame_health<=3; frame_wave<=1; frame_remaining<=0; frame_zombies<=0; frame_clear<=0;
            frame_flash<=0; frame_recoil<=0;
            frame_ready<=0; frame_busy<=1; frame_mode<=0; frame_error<=0;
            frame_screen<=0; frame_digit<=3; frame_sel<=0;
            frame_cx<=48; frame_cy<=40; frame_progress<=0;
            frame_tint<=0; frame_banner<=0; frame_blink<=0; frame_over_ready<=0;
        end else if(frame_begin) begin
            frame_map<=published_map; frame_p1<=p1_addr; frame_p2<=p2_addr;
            frame_health<=health; frame_wave<=wave;
            frame_remaining<=remaining; frame_zombies<=zombies; frame_clear<=wave_clear;
            frame_flash<=weapon_flash; frame_recoil<=weapon_recoil;
            frame_seed<=seed; frame_ready<=ready; frame_busy<=busy;
            frame_mode<=switch_sync[1]; frame_error<=error_code;
            frame_screen<=flow_state; frame_digit<=count_digit; frame_sel<=menu_sel;
            frame_cx<=mouse_x; frame_cy<=mouse_y; frame_progress<=progress;
            frame_tint<=tint; frame_banner<=banner; frame_blink<=low_blink;
            frame_over_ready<=over_ready;
        end
    end
    wire playing = frame_screen==3'd3;
    wire [1:0] menu_screen = (frame_screen==3'd4) ? 2'd3 : frame_screen[1:0];
    wire [3:0] wave_tens,wave_ones;
    wave_digits frame_wave_digits(.value(frame_wave),.tens(wave_tens),.ones(wave_ones));
    wire [15:0] fp_pixel_data=(py<32) ? 16'h1084 : 16'h3166;
    wire [15:0] gun_pixel_data,hud_pixel_data,map_pixel_data,zombie_pixel_data,play_pixel_data,menu_pixel_data;
    weapon_overlay gun(.px(px),.py(py),.show(!frame_mode),.recoil(frame_recoil),.flash(frame_flash),
        .pixel_in(fp_pixel_data),.pixel_out(gun_pixel_data));
    hud_overlay hud(.px(px),.py(py),.minimap_mode(frame_mode),.health(frame_health),
        .low_blink(frame_blink),.wave(frame_wave),.zombies(frame_remaining),
        .pixel_in(gun_pixel_data),.pixel_out(hud_pixel_data));
    map_display_mux display_mux(.px(px),.py(py),.minimap_mode(frame_mode),
        .fp_pixel_data(hud_pixel_data),.map_bits(frame_map),.p1_addr(frame_p1),
        .p2_addr(frame_p2),.seed(frame_seed),.map_ready(frame_ready),
        .busy(frame_busy),.bfs_enabled(STAGE==3),.error_code(frame_error),
        .pixel_data(map_pixel_data));
    zombie_overlay zombie_dots(.px(px),.py(py),.minimap_mode(frame_mode),.zombies(frame_zombies),
        .pixel_in(map_pixel_data),.pixel_out(zombie_pixel_data));
    play_effects effects(.px(px),.py(py),.pixel_in(zombie_pixel_data),.tint(frame_tint),
        .banner(frame_banner),.clear(frame_clear),.wave_tens(wave_tens),.wave_ones(wave_ones),
        .pixel_out(play_pixel_data));
    menu_screens #(.ENABLE_2P(ENABLE_2P)) menu(.px(px),.py(py),.screen(menu_screen),
        .sel(frame_sel),.cursor_x(frame_cx),.cursor_y(frame_cy),.show_cursor(USE_MOUSE!=0),
        .count_digit(frame_digit),.progress(frame_progress),.wave_tens(wave_tens),
        .wave_ones(wave_ones),.over_ready(frame_over_ready),.pixel(menu_pixel_data));
    wire [15:0] pixel_data = playing ? play_pixel_data : menu_pixel_data;
    wire raw_cs,raw_sdin,raw_sclk,raw_dcn;
    wire [15:0] last_gun_pixel_data,last_hud_pixel_data,last_map_pixel_data,last_zombie_pixel_data,last_play_pixel_data,last_menu_pixel_data;
    // Pixel (95,63) is sent separately by oled_tail_bridge: evaluate it through
    // the same HUD, map, effects and menu logic for a single source of truth.
    hud_overlay last_hud(.px(7'd95),.py(6'd63),.minimap_mode(frame_mode),.health(frame_health),
        .low_blink(frame_blink),.wave(frame_wave),.zombies(frame_remaining),
        .pixel_in(last_gun_pixel_data),.pixel_out(last_hud_pixel_data));
    weapon_overlay last_gun(.px(7'd95),.py(6'd63),.show(!frame_mode),.recoil(frame_recoil),
        .flash(frame_flash),.pixel_in(16'h3166),.pixel_out(last_gun_pixel_data));
    map_display_mux last_pixel_mux(.px(7'd95),.py(6'd63),.minimap_mode(frame_mode),
        .fp_pixel_data(last_hud_pixel_data),.map_bits(frame_map),.p1_addr(frame_p1),
        .p2_addr(frame_p2),.seed(frame_seed),.map_ready(frame_ready),
        .busy(frame_busy),.bfs_enabled(STAGE==3),.error_code(frame_error),
        .pixel_data(last_map_pixel_data));
    zombie_overlay last_zombie_dots(.px(7'd95),.py(6'd63),.minimap_mode(frame_mode),
        .zombies(frame_zombies),.pixel_in(last_map_pixel_data),.pixel_out(last_zombie_pixel_data));
    play_effects last_effects(.px(7'd95),.py(6'd63),.pixel_in(last_zombie_pixel_data),
        .tint(frame_tint),.banner(frame_banner),.clear(frame_clear),.wave_tens(wave_tens),.wave_ones(wave_ones),
        .pixel_out(last_play_pixel_data));
    menu_screens #(.ENABLE_2P(ENABLE_2P)) last_menu(.px(7'd95),.py(6'd63),.screen(menu_screen),
        .sel(frame_sel),.cursor_x(frame_cx),.cursor_y(frame_cy),.show_cursor(USE_MOUSE!=0),
        .count_digit(frame_digit),.progress(frame_progress),.wave_tens(wave_tens),
        .wave_ones(wave_ones),.over_ready(frame_over_ready),.pixel(last_menu_pixel_data));
    wire [15:0] last_pixel_data = playing ? last_play_pixel_data : last_menu_pixel_data;
    Oled_Display oled(.clk(oled_clk),.reset(oled_reset),.frame_begin(frame_begin),
        .sending_pixels(sending_pixels),.sample_pixel(sample_pixel),
        .pixel_index(pixel_index),.pixel_data(pixel_data),
        .cs(raw_cs),.sdin(raw_sdin),.sclk(raw_sclk),.d_cn(raw_dcn),
        .resn(JB[5]),.vccen(JB[6]),.pmoden(JB[7]));
    oled_tail_bridge tail_bridge(.clk(oled_clk),.rst(oled_reset),
        .raw_cs(raw_cs),.raw_sdin(raw_sdin),.raw_dcn(raw_dcn),
        .last_pixel_data(last_pixel_data),.cs(JB[0]),.sdin(JB[1]),
        .d_cn(JB[4]),.sclk(JB[3]));
    assign JB[2]=1'b0;
endmodule
