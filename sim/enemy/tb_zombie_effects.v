`timescale 1ns / 1ps
// Zombie damage and death visuals:
//  zombie_death_fx - a slot that goes inactive during play becomes a corpse
//    at its last position, falls 0..15 over 16 steps, lies down, then
//    disappears; a new spawn or leaving play ends it at once; hp passes
//    through for live zombies only.
//  zombie_renderer - a zombie with hp 2 shows a 3-segment bar above its head
//    (two green, one dark red); hp 3 shows no bar; a dying zombie is drawn in
//    red and, when flat (fall 15), is wider than tall on screen.
// Writes zombie_effects.ppm (upright with bar | falling | flat) for viewing.
module tb_zombie_effects;
    reg clk=0, rst=1; always #5 clk=~clk;
    integer failures=0;
    task fail(input [8*72-1:0] m); begin failures=failures+1; $display("FAIL zombie_effects: %0s", m); end endtask

    // ---------------- zombie_death_fx ----------------
    localparam STEP=2, TOTAL=20;
    reg playing=0; reg [7:0] act=0; reg [95:0] zx=0, zy=0; reg [15:0] zhp={8{2'd3}};
    wire [7:0] da, dd; wire [95:0] dx, dy; wire [15:0] dhp; wire [31:0] df;
    zombie_death_fx #(.STEP_SHIFT(STEP),.TOTAL_STEPS(TOTAL)) fx(.clk(clk),.rst(rst),.playing(playing),
        .active(act),.in_x(zx),.in_y(zy),.in_hp(zhp),.draw_active(da),.draw_x(dx),.draw_y(dy),
        .draw_hp(dhp),.dying(dd),.fall(df));
    integer k, last_fall, max_fall, frames;

    // ---------------- zombie_renderer ----------------
    reg prepare=0, bank=0; reg [6:0] px=0; reg [5:0] py=0;
    reg [7:0] r_act=0; reg [95:0] rx=0, ry=0; reg [15:0] r_hp={8{2'd3}}; reg [7:0] r_dying=0; reg [31:0] r_fall=0;
    wire done; wire [15:0] pixel;
    zombie_renderer #(.USE_CAMERA_POSE(1),.FOCAL_X(83),.FOCAL_Y(64)) ren(
        .clk(clk),.reset(rst),.prepare(prepare),.display_bank(bank),.scene_valid(1'b1),
        .camera_x(12'd640),.camera_y(12'd2176),.camera_angle(10'd0),.facing(2'd0),
        .active(r_act),.zombie_x(rx),.zombie_y(ry),.hp(r_hp),.dying(r_dying),.fall(r_fall),
        .pixel_x(px),.pixel_y(py),.wall_depth(13'd4095),.background(16'h0000),
        .done(done),.pixel(pixel));
    reg [15:0] img [0:95][0:63];
    integer x, y, green_bar, red_bar, red_body, other_body, minx, maxx, miny, maxy, f;
    task render; begin
        // Prepare into the back bank, then show it.
        @(negedge clk); bank=0; prepare=1; @(negedge clk); prepare=0;
        wait(done); @(negedge clk); bank=1; repeat(4) @(negedge clk);
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            px=x; py=y; repeat(60) @(negedge clk); img[x][y]=pixel;
        end
    end endtask
    task measure; begin
        green_bar=0; red_bar=0; red_body=0; other_body=0; minx=99; maxx=-1; miny=99; maxy=-1;
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) if(img[x][y]!=0) begin
            if(img[x][y]==16'h07E0) green_bar=green_bar+1;
            else if(img[x][y]==16'h8000) red_bar=red_bar+1;
            else begin
                // Red tint = full red, green and blue top bits cleared.
                if(img[x][y][15:11]==5'h1F && !img[x][y][10] && !img[x][y][4]) red_body=red_body+1; else other_body=other_body+1;
                if(x<minx) minx=x; if(x>maxx) maxx=x; if(y<miny) miny=y; if(y>maxy) maxy=y;
            end
        end
        $display("  measure: bar green=%0d red=%0d, body red=%0d other=%0d, box %0dx%0d", green_bar, red_bar, red_body, other_body, maxx-minx+1, maxy-miny+1);
    end endtask
    integer ppm, pass;
    reg [15:0] strip [0:287][0:63];
    task keep(input integer slot); begin
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) strip[slot*96+x][y]=img[x][y];
    end endtask

    initial begin
        repeat(3) @(negedge clk); rst=0;
        // ---- death_fx ----
        playing=1; zx[11:0]=12'd900; zy[11:0]=12'd700; zhp[1:0]=2'd2; act[0]=1;
        repeat(3) @(negedge clk);
        if(!da[0] || dd[0] || dhp[1:0]!=2 || dx[11:0]!=900) fail("live zombie not passed through");
        // Kill: manager clears the slot and its position on the same clock.
        act[0]=0; zx[11:0]=0; zy[11:0]=0; @(negedge clk); @(negedge clk);
        if(!da[0] || !dd[0]) fail("killed zombie did not become a corpse");
        if(dx[11:0]!=900 || dy[11:0]!=700) fail("corpse not at the last position");
        if(dhp[1:0]!=0) fail("corpse shows a health bar");
        last_fall=0; max_fall=0; frames=0;
        while(dd[0] && frames<5000) begin
            @(negedge clk); frames=frames+1;
            if(df[3:0]<last_fall) fail("fall went backwards");
            if(df[3:0]>last_fall+1) fail("fall skipped a step");
            last_fall=df[3:0]; if(df[3:0]>max_fall) max_fall=df[3:0];
        end
        if(dd[0]) fail("corpse never disappeared");
        if(max_fall!=15) fail("corpse never lay flat");
        if(frames<(TOTAL-1)*4 || frames>(TOTAL+1)*4) fail("corpse lasted the wrong time");
        if(da[0]) fail("slot still drawn after the corpse ended");
        // A new spawn ends a corpse at once.
        act[1]=1; zx[23:12]=12'd400; @(negedge clk); @(negedge clk); act[1]=0; @(negedge clk); @(negedge clk);
        if(!dd[1]) fail("second slot did not start dying");
        act[1]=1; zx[23:12]=12'd1500; @(negedge clk);
        if(dd[1] || dx[23:12]!=1500) fail("respawn did not replace the corpse");
        // Leaving play: no corpses.
        act[1]=0; playing=0; @(negedge clk); @(negedge clk);
        if(da[1] || dd[1]) fail("corpse appeared outside play");
        playing=1;

        // ---- renderer: one zombie 3 tiles ahead of the camera ----
        r_act=8'd1; rx[11:0]=12'd640; ry[11:0]=12'd1408;
        r_hp[1:0]=2'd3; render; measure; keep(0);
        if(green_bar!=0 || red_bar!=0) fail("full-health zombie shows a bar");
        if(other_body<20 || red_body!=0) fail("upright zombie not drawn normally");
        r_hp[1:0]=2'd2; render; measure; keep(0);
        if(green_bar<10 || red_bar<5) fail("hp 2 bar missing (2 green, 1 red segment)");
        if(green_bar!=2*red_bar) fail("bar segments not 2 green : 1 red");
        if(!(maxy-miny > maxx-minx)) fail("upright zombie is not taller than wide");
        r_dying=8'd1; r_fall[3:0]=4'd7; render; measure; keep(1);
        if(green_bar!=0 || red_bar!=0) fail("dying zombie shows a bar");
        if(red_body<20 || other_body!=0) fail("falling zombie not tinted red");
        r_fall[3:0]=4'd15; render; measure; keep(2);
        if(red_body<20) fail("flat zombie not drawn");
        if(!(maxx-minx > maxy-miny)) fail("flat zombie is not wider than tall");
        ppm=$fopen("zombie_effects.ppm","w");
        $fwrite(ppm,"P3\n288 64\n255\n");
        for(y=0;y<64;y=y+1) for(x=0;x<288;x=x+1)
            $fwrite(ppm,"%0d %0d %0d\n",strip[x][y][15:11]*255/31,strip[x][y][10:5]*255/63,strip[x][y][4:0]*255/31);
        $fclose(ppm);
        if(failures==0) $display("TB_ZOMBIE_EFFECTS: PASS (corpse at last position, 16-step fall, lies flat then vanishes, respawn/leave-play end it; bar 2:1 at hp 2, none at hp 3 or dying; red tint; flat corpse wider than tall)");
        else $display("TB_ZOMBIE_EFFECTS: FAIL total=%0d", failures);
        $finish;
    end
endmodule
