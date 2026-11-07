`timescale 1ns / 1ps
// Crosshair hit flash and WAVE CLEAR banner in pixel_compositor (play view).
//  - crosshair (48,32) white normally, red with hit_flash; hidden on the map.
//  - banner at top=20: yellow letters only in rows 20..29, darkened band
//    rows 18..31, untouched outside; nothing when banner_show=0; partly
//    off-screen tops (-6, 58) draw only the visible rows.
// Writes ui_effects.ppm (banner frame with the red crosshair) for viewing.
module tb_ui_effects;
    reg [6:0] px; reg [5:0] py;
    reg hit=0, show=0, mode=0; reg signed [7:0] top=20;
    wire [15:0] pix;
    localparam [15:0] WORLD=16'h7BEF;   // mid grey: halves to 16'h39E7
    pixel_compositor dut(.px(px),.py(py),.world_pixel(WORLD),.game_state(3'd3),.minimap_mode(mode),
        .map_bits(256'd0),.p1_addr(8'h11),.p2_addr(8'hee),.player_x(8'h18),.player_y(8'h18),.player_angle(10'd0),
        .seed(16'h1ace),.map_ready(1'b1),.map_busy(1'b0),.error_code(3'd0),
        .health(2'd3),.low_blink(1'b0),.wave(7'd3),.remaining(7'd5),.zombie_tiles(256'd0),.tint(1'b0),
        .zombie_active(8'd0),.zombie_x(96'd0),.zombie_y(96'd0),
        .weapon_recoil(1'b0),.weapon_flash(1'b0),.weapon_reloading(1'b0),.ammo(3'd6),.weapon_drop(5'd31),
        .menu_sel(1'b0),.cursor_x(7'd0),.cursor_y(6'd0),.progress(6'd0),.over_ready(1'b0),
        .link_up(1'b0),.two_player(1'b0),.peer_wave(7'd0),.peer_in_run(1'b0),.show_partner(1'b0),
        .hit_flash(hit),.banner_show(show),.banner_top(top),.pixel_out(pix));
    integer failures=0, x, y, text, band, outside, f, full_text;
    task fail(input [8*64-1:0] m); begin failures=failures+1; $display("FAIL ui_effects: %0s", m); end endtask
    task at(input integer xx, input integer yy); begin px=xx; py=yy; #1; end endtask
    task scan_banner(input integer t); begin
        text=0; band=0; outside=0;
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            at(x,y);
            if(pix==16'hFFE0) begin
                text=text+1;
                if(y<t || y>t+9) fail("banner text outside its rows");
            end else if(pix==16'h39E7) begin
                band=band+1;
                if(y<t-2 || y>t+11) fail("darkened band outside its rows");
            end else if(y>=t-2 && y<=t+11 && y>=12 && y<40 && pix==WORLD) outside=outside+1;
        end
    end endtask
    initial begin
        // Crosshair.
        at(48,32); if(pix!==16'hFFFF) fail("crosshair not white");
        hit=1; at(48,32); if(pix!==16'hF800) fail("crosshair not red on hit");
        at(46,32); if(pix!==16'hF800) fail("crosshair arm not red on hit");
        at(48,30); if(pix!==16'hF800) fail("crosshair top not red on hit");
        mode=1; at(48,32); if(pix==16'hF800) fail("red crosshair shown over the map"); mode=0;
        // Banner hidden.
        scan_banner(20); if(text!=0 || band!=0) fail("banner drawn while hidden");
        // Banner at row 20.
        show=1; top=20; scan_banner(20);
        if(text<300) fail("WAVE CLEAR letters missing");
        if(band<500) fail("darkened band missing");
        if(outside!=0) fail("band rows not darkened everywhere");
        at(9,20); if(pix!==16'hFFE0) fail("W top-left pixel");          // W row 0 = 101
        at(41,25); if(pix==16'hFFE0) fail("space between words lit");
        at(48,32); if(pix!==16'hF800) fail("crosshair hidden by the banner band");
        f=$fopen("ui_effects.ppm","w"); $fwrite(f,"P3\n96 64\n255\n");
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            at(x,y); $fwrite(f,"%0d %0d %0d\n",pix[15:11]*255/31,pix[10:5]*255/63,pix[4:0]*255/31);
        end
        $fclose(f);
        // Partly off the top and the bottom.
        full_text=text;
        top=-6; scan_banner(-6); if(text==0 || text>=full_text) fail("top-clipped banner wrong");
        top=58; scan_banner(58); if(text==0 || text>=full_text) fail("bottom-clipped banner wrong");
        top=70; scan_banner(70); if(text!=0 || band!=0) fail("banner below the screen still drawn");
        if(failures==0) $display("TB_UI_EFFECTS: PASS (white/red crosshair, none on map; WAVE CLEAR text rows, darkened band, clipping at top/bottom, hidden when off)");
        else $display("TB_UI_EFFECTS: FAIL total=%0d", failures);
        $finish;
    end
endmodule
