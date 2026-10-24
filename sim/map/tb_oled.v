`timescale 1ns / 1ps
// Decodes the real Pmod SPI pins (startup, every pixel incl. the inserted last
// pixel) through: title screen -> btnC -> generating/countdown -> playing
// (SW0 off) -> playing (SW0 on). Every decoded frame is checked.
module tb_oled;
    reg clk=0;
    always #5 clk=~clk;
    reg btnU=1,sw0=0,btnC=0,btnD=0;
    wire [7:0] JB;
    wire [15:0] led;
    wire [6:0] seg; wire dp; wire [3:0] an; wire ps2c,ps2d;
    map_preview_top #(.DEBOUNCE_CYCLES(4),.USE_MOUSE(0),.GEN_SHIFT(21),.COUNT_SHIFT(20),
        .BANNER_SHIFT(22),.TINT_SHIFT(22),.SPAWN_SHIFT(18)) dut(
        .clk(clk),.sw0(sw0),.btnC(btnC),.btnU(btnU),
        .btnL(1'b0),.btnR(1'b0),.btnD(btnD),.PS2Clk(ps2c),.PS2Data(ps2d),
        .led(led),.JB(JB),.seg(seg),.dp(dp),.an(an));
    integer pixels=0,bit_count=0,failures=0,frames=0,max_queue=0;
    integer commands_in=0,commands_out=0;
    integer title_frames=0,menu_frames=0,play_off=0,play_on=0,tinted=0,bannered=0,zframes=0,gunframes=0;
    reg command_bits[0:8191];
    reg [15:0] serial_word=0;
    wire [6:0] ref_x=pixels%96;
    wire [5:0] ref_y=pixels/96;
    wire [15:0] fp_data=ref_y<32 ? 16'h1084 : 16'h3166;
    wire [15:0] play_expected,map_expected,reference_hud,menu_expected;
    wire [3:0] ref_tens,ref_ones;
    wave_digits reference_digits(.value(dut.frame_wave),.tens(ref_tens),.ones(ref_ones));
    wire [15:0] gun_expected;
    weapon_overlay reference_gun(.px(ref_x),.py(ref_y),.show(!dut.frame_mode),.recoil(dut.frame_recoil),
        .flash(dut.frame_flash),.pixel_in(fp_data),.pixel_out(gun_expected));
    hud_reference reference_overlay(.px(ref_x),.py(ref_y),.minimap_mode(dut.frame_mode),
        .health(dut.frame_health),.low_blink(dut.frame_blink),.wave(dut.frame_wave),.zombies(dut.frame_remaining),
        .pixel_in(gun_expected),.expected(reference_hud));
    map_display_mux reference_display(.px(ref_x),.py(ref_y),.minimap_mode(dut.frame_mode),
        .fp_pixel_data(reference_hud),.map_bits(dut.frame_map),.p1_addr(dut.frame_p1),
        .p2_addr(dut.frame_p2),.seed(dut.frame_seed),.map_ready(dut.frame_ready),
        .busy(dut.frame_busy),.bfs_enabled(1'b1),.error_code(dut.frame_error),
        .pixel_data(map_expected));
    wire [15:0] zombie_expected;
    zombie_overlay reference_zombies(.px(ref_x),.py(ref_y),.minimap_mode(dut.frame_mode),
        .zombies(dut.frame_zombies),.pixel_in(map_expected),.pixel_out(zombie_expected));
    play_effects reference_effects(.px(ref_x),.py(ref_y),.pixel_in(zombie_expected),
        .tint(dut.frame_tint),.banner(dut.frame_banner),.clear(dut.frame_clear),.wave_tens(ref_tens),.wave_ones(ref_ones),
        .pixel_out(play_expected));
    menu_screens reference_menu(.px(ref_x),.py(ref_y),.screen(dut.menu_screen),
        .sel(dut.frame_sel),.cursor_x(dut.frame_cx),.cursor_y(dut.frame_cy),.show_cursor(1'b0),
        .count_digit(dut.frame_digit),.progress(dut.frame_progress),.wave_tens(ref_tens),
        .wave_ones(ref_ones),.over_ready(dut.frame_over_ready),.pixel(menu_expected));
    wire [15:0] expected = (dut.frame_screen==3) ? play_expected : menu_expected;
    initial begin
        repeat(40) @(negedge clk); btnU=0;
        wait(title_frames==1);
        btnC=1; repeat(20) @(negedge clk); btnC=0;     // start the game
        wait(dut.flow_state==3); repeat(20) @(negedge clk);
        btnD=1; repeat(20) @(negedge clk); btnD=0;     // take damage: tinted frame
        btnC=1; repeat(20) @(negedge clk); btnC=0;     // fire: recoil + muzzle flash
    end
    // Record original command bits: insertion may delay but never change them.
    always @(posedge dut.oled_clk) if(!dut.oled_reset) begin
        if(!dut.raw_cs && !dut.raw_dcn) begin
            command_bits[commands_in]=dut.raw_sdin;
            commands_in=commands_in+1;
        end
        if(dut.tail_bridge.count>max_queue) max_queue=dut.tail_bridge.count;
        if(dut.tail_bridge.count>=64 || (dut.tail_bridge.marker && !dut.raw_cs)) begin
            $display("FAIL oled: bridge capacity or marker assumption violated");
            $finish;
        end
    end
    // Decode actual Pmod SPI pins, including startup and the inserted last pixel.
    always @(posedge JB[3]) begin
        if(!btnU && JB[0]===1'b0) begin
            if(JB[4]===1'b1) begin
                serial_word={serial_word[14:0],JB[1]};
                bit_count=bit_count+1;
                if(bit_count==16) begin
                    if(pixels>=6144 || serial_word!==expected) begin
                        failures=failures+1;
                        if(failures<5) $display("FAIL oled: frame %0d screen %0d pixel %0d received=%h expected=%h",frames,dut.frame_screen,pixels,serial_word,expected);
                    end
                    bit_count=0; pixels=pixels+1;
                end
            end else begin
                if(commands_out>=commands_in || JB[1]!==command_bits[commands_out]) begin
                    $display("FAIL oled: changed or extra command bit %0d",commands_out);
                    failures=failures+1;
                end
                commands_out=commands_out+1;
            end
        end
    end
    always @(negedge JB[4]) if(pixels!=0) begin
        if(pixels!=6144 || bit_count!=0) begin
            $display("FAIL oled: incomplete frame pixels=%0d bits=%0d",pixels,bit_count);
            failures=failures+1;
        end
        frames=frames+1; pixels=0;
        if(dut.frame_screen==3 && dut.frame_tint) tinted=tinted+1;
        if(dut.frame_screen==3 && dut.frame_banner) bannered=bannered+1;
        if(dut.frame_screen==3 && !dut.frame_mode && dut.frame_flash) gunframes=gunframes+1;
        if(dut.frame_screen==3 && dut.frame_mode && dut.frame_zombies!=0) zframes=zframes+1;
        if(dut.frame_screen==0) title_frames=title_frames+1;
        else if(dut.frame_screen!=3) menu_frames=menu_frames+1;
        else if(!dut.frame_mode) begin play_off=play_off+1; sw0=1; end
        else play_on=play_on+1;
        if(play_on==1) begin
            repeat(100) @(posedge dut.oled_clk);
            if(commands_in!=commands_out) begin
                $display("FAIL oled: missing command bits in=%0d out=%0d",commands_in,commands_out);
                failures=failures+1;
            end
            if(title_frames==0 || play_off==0 || tinted==0 || bannered==0 || zframes==0 || gunframes==0) begin
                $display("FAIL oled: missing title or play frame"); failures=failures+1;
            end
            if(failures==0) $display("PASS oled: %0d complete 6144-pixel frames decoded from the Pmod pins (title, %0d generating/countdown, HUD view, HUD plus 64x64 map; %0d with wave banner, %0d with damage tint, %0d map frames with zombie dots, %0d with muzzle flash), command preservation, max queue=%0d",frames,menu_frames,bannered,tinted,zframes,gunframes,max_queue);
            else $display("FAIL oled total=%0d",failures);
            $finish;
        end
    end
    initial begin
        #900000000;
        $display("FAIL oled: startup/frame timeout after %0d frames",frames);
        $finish;
    end
endmodule
