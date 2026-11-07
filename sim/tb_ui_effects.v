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
    reg [2:0] state=3'd3; reg two=0, you_p2=0;
    reg [1:0] health=2'd3;
    reg partner_dead=0;
    wire [15:0] pix;
    localparam [15:0] WORLD=16'h7BEF;   // mid grey: halves to 16'h39E7
    pixel_compositor dut(.px(px),.py(py),.world_pixel(WORLD),.game_state(state),.minimap_mode(mode),
        .map_bits(256'd0),.p1_addr(8'h11),.p2_addr(8'hee),.player_x(8'h18),.player_y(8'h18),.player_angle(10'd0),
        .seed(16'h1ace),.map_ready(1'b1),.map_busy(1'b0),.error_code(3'd0),
        .health(health),.low_blink(1'b0),.wave(7'd3),.remaining(7'd5),.zombie_tiles(256'd0),.tint(1'b0),
        .zombie_active(8'd0),.zombie_x(96'd0),.zombie_y(96'd0),
        .weapon_recoil(1'b0),.weapon_flash(1'b0),.weapon_reloading(1'b0),.ammo(4'd6),.ammo_capacity(4'd6),.pickups(18'd0),.weapon_drop(5'd31),
        .menu_sel(1'b0),.cursor_x(7'd0),.cursor_y(6'd0),.progress(6'd0),.over_ready(1'b0),
        .link_up(two),.two_player(two),.peer_wave(7'd3),.peer_in_run(two),.show_partner(two),
        .partner_dead(partner_dead),
        .p1_kills(7'd12),.p2_kills(7'd7),.you_are_p2(you_p2),
        .hit_flash(hit),.banner_show(show),.banner_top(top),.pixel_out(pix));
    integer failures=0, x, y, text, band, outside, f, full_text;
    reg [15:0] unbannered [0:95][0:63];
    task fail(input [8*64-1:0] m); begin failures=failures+1; $display("FAIL ui_effects: %0s", m); end endtask
    task at(input integer xx, input integer yy); begin px=xx; py=yy; #1; end endtask
    integer yel, wht;
    task count_rows(input integer y0, input integer y1, input [15:0] c); begin
        yel=0; wht=0;
        for(y=y0;y<=y1;y=y+1) for(x=0;x<96;x=x+1) begin
            at(x,y); if(pix==c) begin if(c==16'hF645) yel=yel+1; else wht=wht+1; end
        end
    end endtask
    task scan_banner(input integer t); begin
        text=0; band=0; outside=0;
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            at(x,y);
            if(pix==16'hFFE0 && unbannered[x][y]!=16'hFFE0) begin
                text=text+1;
                if(y<t || y>t+9) fail("banner text outside its rows");
            end else if(pix==16'h39E7) begin
                band=band+1;
                if(y<t-2 || y>t+11) fail("darkened band outside its rows");
            end else if(y>=t-2 && y<=t+11 && y>=12 && y<40 && pix==WORLD) outside=outside+1;
        end
    end endtask
    initial begin
        at(2,2); if(pix!==16'hFFE0) fail("WAVE label not yellow");
        at(50,2); if(pix!==16'h87F0) fail("KILLS label not green");
        at(74,2); if(pix!==16'h0842) fail("leader HUD did not show its own kill count");
        you_p2=1; at(74,2); if(pix!==16'h87F0) fail("follower HUD did not show its own kill count");
        you_p2=0; two=1; health=0;
        at(24,23); if(pix!==16'hF800) fail("downed notice missing from first-person HUD");
        at(22,30); if(pix!==16'hFFE0) fail("living partner subtitle missing");
        partner_dead=1; at(22,30); if(pix!==16'h4000) fail("dead partner marked alive");
        mode=1; at(2,19); if(pix!==16'hF800) fail("downed notice missing from minimap HUD");
        at(89,57); if(pix!==16'hA145) fail("downed teammate map marker missing");
        at(38,6); if(pix!==16'hA145) fail("downed local map marker missing");
        at(38,4); if(pix!==16'h0841) fail("downed local map pointer still visible");
        partner_dead=0; health=3;
        at(89,57); if(pix!==16'hFFE0) fail("living teammate map marker missing");
        at(38,4); if(pix!==16'hFFFF) fail("living local map pointer missing");
        mode=0; two=0;
        // Crosshair.
        at(48,32); if(pix!==16'hFFFF) fail("crosshair not white");
        hit=1; at(48,32); if(pix!==16'hF800) fail("crosshair not red on hit");
        at(46,32); if(pix!==16'hF800) fail("crosshair arm not red on hit");
        at(48,30); if(pix!==16'hF800) fail("crosshair top not red on hit");
        mode=1; at(48,32); if(pix==16'hF800) fail("red crosshair shown over the map"); mode=0;
        // Banner hidden.
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            at(x,y); unbannered[x][y]=pix;
        end
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
        // 2-player end screens: P1 and P2 kill lines, own line yellow.
        show=0; hit=0;
        for(f=4; f<=5; f=f+1) begin
            state=f; two=0; count_rows(38,42,16'hF645); if(yel!=0 || wht!=0) fail("kill lines shown in 1 PLAYER");
            two=1; you_p2=0;
            count_rows(38,42,16'hF645); if(yel<25) fail("P1 KILLS line not yellow for the leader");
            count_rows(45,49,16'hEF7D); if(wht<25) fail("P2 KILLS line not white for the leader");
            you_p2=1;
            count_rows(45,49,16'hF645); if(yel<25) fail("P2 KILLS line not yellow for the follower");
            count_rows(38,42,16'hEF7D); if(wht<25) fail("P1 KILLS line not white for the follower");
            // Digits: "P1 KILLS 12" starts at x=26, so '1' and '2' sit at x=62 and x=66.
            at(63,38); if(pix==16'h0842) fail("P1 kill tens digit missing");
            at(67,42); if(pix==16'h0842) fail("P1 kill ones digit missing");
            two=0;
        end
        f=$fopen("ui_endscreen.ppm","w"); $fwrite(f,"P3\n96 64\n255\n");
        state=4; two=1; you_p2=0;
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            at(x,y); $fwrite(f,"%0d %0d %0d\n",pix[15:11]*255/31,pix[10:5]*255/63,pix[4:0]*255/31);
        end
        $fclose(f);
        if(failures==0) $display("TB_UI_EFFECTS: PASS (white/red crosshair, none on map; WAVE CLEAR text rows, darkened band, clipping at top/bottom, hidden when off; 2P kill lines on game over and victory, own line yellow, none in 1P)");
        else $display("TB_UI_EFFECTS: FAIL total=%0d", failures);
        $finish;
    end
endmodule
