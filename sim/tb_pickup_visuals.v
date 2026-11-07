`timescale 1ns / 1ps
// Pickup drawing:
//  - zombie_renderer with SLOTS=11, HAS_ALLY=1, PICKUP_SLOTS=2: a medkit
//    (white with a red cross) and a brass magazine 2 tiles ahead, in the lower
//    part of the view (on the floor), behind a nearer zombie where they overlap.
//  - pixel_compositor: 9 bullets right-aligned (x=77..93) for capacity 9 with
//    7 loaded; 6 bullets (x=83..93) for capacity 6; minimap health plus and
//    magazine bar at their tiles.
// Writes pickup_view.ppm (3D view) and pickup_hud.ppm (play HUD | map).
module tb_pickup_visuals;
    reg clk=0; always #5 clk=~clk;
    reg reset=1, prepare=0, bank=0;
    reg [10:0] active=0; reg [131:0] zx=0, zy=0;
    reg [6:0] px=0; reg [5:0] py=0;
    wire done; wire [15:0] pixel;
    zombie_renderer #(.USE_CAMERA_POSE(1),.FOCAL_X(83),.FOCAL_Y(64),.SLOTS(11),.HAS_ALLY(1),.PICKUP_SLOTS(2)) ren(
        .clk(clk),.reset(reset),.prepare(prepare),.display_bank(bank),.scene_valid(1'b1),
        .camera_x(12'h880),.camera_y(12'h880),.facing(2'd0),.camera_angle(10'd0),
        .active(active),.zombie_x(zx),.zombie_y(zy),
        .hp({22{1'b1}}),.dying(11'd0),.fall(44'd0),.pixel_x(px),.pixel_y(py),
        .wall_depth(13'd4095),.background(16'h0000),.done(done),.pixel(pixel));
    reg [15:0] img [0:95][0:63];
    integer x, y, red=0, white=0, brass=0, low=0, failures=0, f;
    task fail(input [8*64-1:0] m); begin failures=failures+1; $display("FAIL pickup_visuals: %0s", m); end endtask
    // HUD / minimap via the compositor
    reg mode=0; reg [3:0] ammo=7, cap=9;
    wire [15:0] hud;
    pixel_compositor comp(.px(px),.py(py),.world_pixel(16'h18E3),.game_state(3'd3),.minimap_mode(mode),
        .map_bits(256'd0),.p1_addr(8'h11),.p2_addr(8'hee),.player_x(8'h88),.player_y(8'h88),.player_angle(10'd0),
        .seed(16'h1ace),.map_ready(1'b1),.map_busy(1'b0),.error_code(3'd0),
        .health(2'd3),.low_blink(1'b0),.wave(7'd2),.remaining(7'd4),.zombie_tiles(256'd0),.tint(1'b0),
        .zombie_active(8'd0),.zombie_x(96'd0),.zombie_y(96'd0),
        .weapon_recoil(1'b0),.weapon_flash(1'b0),.weapon_reloading(1'b0),
        .ammo(ammo),.ammo_capacity(cap),.pickups({1'b1,1'b1,8'h3C,8'hA4}),.weapon_drop(5'd31),
        .menu_sel(1'b0),.cursor_x(7'd0),.cursor_y(6'd0),.progress(6'd0),.over_ready(1'b0),
        .link_up(1'b0),.two_player(1'b0),.peer_wave(7'd0),.peer_in_run(1'b0),.show_partner(1'b0),
        .hit_flash(1'b0),.banner_show(1'b0),.banner_top(8'sd0),.p1_kills(7'd0),.p2_kills(7'd0),.you_are_p2(1'b0),
        .pixel_out(hud));
    integer brass_cols, spent_cols, first_col;
    task count_bullets; begin
        brass_cols=0; spent_cols=0; first_col=99; py=58;
        for(x=60;x<96;x=x+1) begin px=x; #1;
            if(hud==16'hF645) begin brass_cols=brass_cols+1; if(x<first_col) first_col=x; end
            if(hud==16'h4208) begin spent_cols=spent_cols+1; if(x<first_col) first_col=x; end
        end
    end endtask
    initial begin
        repeat(4) @(negedge clk); reset=0;
        // Camera at (8.5, 8.5) facing north. Health 2 tiles ahead and 0.75 left,
        // magazine 2 tiles ahead and 0.75 right.
        zx[9*12 +: 12]=12'h840; zy[9*12 +: 12]=12'h680;    // health
        zx[10*12 +: 12]=12'h8C0; zy[10*12 +: 12]=12'h680;  // magazine
        active=11'b110_0000_0000;
        @(negedge clk); prepare=1; @(negedge clk); prepare=0; wait(done); @(negedge clk);
        bank=1; repeat(3) @(negedge clk);
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            px=x; py=y; repeat(80) @(negedge clk); img[x][y]=pixel;
            if(pixel==16'hF800) red=red+1;
            if(pixel==16'hFFFF) white=white+1;
            if(pixel==16'hFD20) brass=brass+1;
            if(pixel!=0 && y<32) low=low+1;
        end
        if(red<4 || white<6) fail("medkit not drawn (red cross on white)");
        if(brass<4) fail("magazine not drawn");
        if(low!=0) fail("pickups drawn above the horizon (should sit on the floor)");
        f=$fopen("pickup_view.ppm","w"); $fwrite(f,"P3\n96 64\n255\n");
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1)
            $fwrite(f,"%0d %0d %0d\n",img[x][y][15:11]*255/31,img[x][y][10:5]*255/63,img[x][y][4:0]*255/31);
        $fclose(f);
        // ---- HUD ammo ----
        count_bullets;
        if(brass_cols!=7 || spent_cols!=2 || first_col!=77) fail("9-round magazine HUD (7 loaded)");
        ammo=6; cap=6; count_bullets;
        if(brass_cols!=6 || spent_cols!=0 || first_col!=83) fail("6-round magazine HUD");
        // ---- minimap ----
        mode=1;
        px=7'd32+4*4+2; py=6'd10*4+2; #1; if(hud!==16'hF800) fail("health plus centre on map");   // tile A4
        px=7'd32+4*4+0; py=6'd10*4+2; #1; if(hud===16'hF800) fail("health plus too wide");
        px=7'd32+12*4+1; py=6'd3*4+2; #1; if(hud!==16'hFD20) fail("magazine bar on map");         // tile 3C
        f=$fopen("pickup_hud.ppm","w"); $fwrite(f,"P3\n192 64\n255\n");
        for(y=0;y<64;y=y+1) for(x=0;x<192;x=x+1) begin
            mode = x>=96; cap=9; ammo=7; px=x%96; py=y; #1;
            $fwrite(f,"%0d %0d %0d\n",hud[15:11]*255/31,hud[10:5]*255/63,hud[4:0]*255/31);
        end
        $fclose(f);
        if(failures==0) $display("TB_PICKUP_VISUALS: PASS (medkit and magazine on the floor in 3D, 9/6-round ammo HUD, minimap markers)");
        else $display("TB_PICKUP_VISUALS: FAIL total=%0d", failures);
        $finish;
    end
endmodule
