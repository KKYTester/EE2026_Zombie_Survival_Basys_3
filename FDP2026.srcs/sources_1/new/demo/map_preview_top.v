`timescale 1ns / 1ps
module map_preview_top #(parameter STAGE=3, parameter DEBOUNCE_CYCLES=1000000)(
    input wire clk, input wire sw0, input wire btnC, input wire btnU,
    input wire [4:1] sw_wave, input wire [15:9] sw_health,
    output wire [15:0] led, output wire [7:0] JB,
    output wire [6:0] seg, output wire dp, output wire [3:0] an);
    // ASSUMPTION: EE2026 Pmod OLEDrgb on JB, as in the supplied lab project.
    // FPGA power-up initialisation; all functional resets below are synchronous.
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync=2'b11;
    (* ASYNC_REG="TRUE" *) reg [1:0] switch_sync=0;
    (* ASYNC_REG="TRUE" *) reg [10:0] hud_sync1=0,hud_sync2=0;
    reg [3:0] clk_div=0;
    wire oled_clk=clk_div[3];
    wire rst=reset_sync[1];
    reg [5:0] oled_reset_hold=63;
    wire oled_reset=oled_reset_hold!=0;
    always @(posedge clk) begin
        reset_sync<={reset_sync[0],btnU};
        switch_sync<={switch_sync[0],sw0};
        hud_sync1<={sw_health,sw_wave}; hud_sync2<=hud_sync1;
        // Never stop/reset the divided clock while resetting its consumers.
        clk_div<=clk_div+1'b1;
        if(rst) oled_reset_hold<=63;
        else if(oled_reset_hold!=0) oled_reset_hold<=oled_reset_hold-1'b1;
    end
    wire button_press;
    reg [15:0] seed_counter,seed_latched;
    reg regenerate;
    button_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) button_filter(
        .clk(clk),.rst(rst),.button(btnC),.pressed(button_press));
    always @(posedge clk) begin
        if(rst) begin seed_counter<=1; seed_latched<=1; regenerate<=0; end
        else begin
            seed_counter<=seed_counter+1'b1;
            regenerate<=button_press;
            if(button_press) seed_latched<=(seed_counter==0) ? 16'h0001 : seed_counter;
        end
    end
    wire [255:0] published_map;
    wire [7:0] p1_addr,p2_addr;
    wire ready,busy;
    wire [2:0] error_code,retry_count;
    wire [15:0] seed;
    map_system #(.STAGE(STAGE)) core(.clk(clk),.rst(rst),.regenerate(regenerate),
        .seed_in(seed_latched),.published_map(published_map),.p1_addr(p1_addr),
        .p2_addr(p2_addr),.map_ready(ready),.busy(busy),.error_code(error_code),
        .active_seed(seed),.retry_count(retry_count));
    assign led={busy,11'b0,error_code,ready};
    seven_seg_hex seed_display(.clk(clk),.rst(rst),.value(seed),
        .seg(seg),.dp(dp),.an(an));

    wire frame_begin,sending_pixels,sample_pixel;
    wire [12:0] pixel_index;
    // The only pixel-index coordinate conversion. Tile lookup below uses slices.
    wire [6:0] px=pixel_index % 96;
    wire [5:0] py=pixel_index / 96;
    reg [255:0] frame_map;
    reg [7:0] frame_p1,frame_p2;
    reg [15:0] frame_seed;
    reg [6:0] frame_health,frame_wave;
    reg frame_ready,frame_busy,frame_mode;
    reg [2:0] frame_error;
    // Related clocks, explicitly constrained in XDC, not asynchronous CDC.
    // The supplied driver updates frame_begin on negedge; capture on posedge
    // so the next negedge samples a coherent frame and its first pixel.
    always @(posedge oled_clk) begin
        if(oled_reset) begin
            frame_map<={256{1'b1}}; frame_p1<=0; frame_p2<=0; frame_seed<=0;
            frame_health<=0; frame_wave<=0;
            frame_ready<=0; frame_busy<=1; frame_mode<=0; frame_error<=0;
        end else if(frame_begin) begin
            frame_map<=published_map; frame_p1<=p1_addr; frame_p2<=p2_addr;
            frame_health<=(hud_sync2[10:4]>99) ? 7'd99 : hud_sync2[10:4];
            frame_wave<={3'b000,hud_sync2[3:0]};
            frame_seed<=seed; frame_ready<=ready; frame_busy<=busy;
            frame_mode<=switch_sync[1]; frame_error<=error_code;
        end
    end
    wire [15:0] fp_pixel_data=(py<32) ? 16'h1084 : 16'h3166;
    wire [15:0] pixel_data,hud_pixel_data,last_hud_pixel_data;
    hud_overlay hud(.px(px),.py(py),.minimap_mode(frame_mode),
        .health(frame_health),.wave(frame_wave),.pixel_in(fp_pixel_data),.pixel_out(hud_pixel_data));
    hud_overlay last_hud(.px(7'd95),.py(6'd63),.minimap_mode(frame_mode),
        .health(frame_health),.wave(frame_wave),.pixel_in(16'h3166),.pixel_out(last_hud_pixel_data));
    map_display_mux display_mux(.px(px),.py(py),.minimap_mode(frame_mode),
        .fp_pixel_data(hud_pixel_data),.map_bits(frame_map),.p1_addr(frame_p1),
        .p2_addr(frame_p2),.seed(frame_seed),.map_ready(frame_ready),
        .busy(frame_busy),.bfs_enabled(STAGE==3),.error_code(frame_error),
        .pixel_data(pixel_data));
    wire raw_cs,raw_sdin,raw_sclk,raw_dcn;
    wire [15:0] last_pixel_data;
    // Pixel (95,63) is FP data with SW0 off, white zoom border with SW0 on.
    // Evaluate through the same mux for a single source of truth.
    map_display_mux last_pixel_mux(.px(7'd95),.py(6'd63),.minimap_mode(frame_mode),
        .fp_pixel_data(last_hud_pixel_data),.map_bits(frame_map),.p1_addr(frame_p1),
        .p2_addr(frame_p2),.seed(frame_seed),.map_ready(frame_ready),
        .busy(frame_busy),.bfs_enabled(STAGE==3),.error_code(frame_error),
        .pixel_data(last_pixel_data));
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
