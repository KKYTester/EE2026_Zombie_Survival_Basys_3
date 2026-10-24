`timescale 1ns / 1ps
module tb_display;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1;
    wire [255:0] bits;
    wire [7:0] p1,p2;
    wire ready,busy;
    wire [15:0] seed;
    wire [2:0] err;
    map_system core(.clk(clk),.rst(rst),.regenerate(1'b0),.seed_in(16'h0001),
        .published_map(bits),.p1_addr(p1),.p2_addr(p2),.map_ready(ready),
        .busy(busy),.error_code(err),.active_seed(seed),.retry_count());
    reg [6:0] px;
    reg [5:0] py;
    reg mode=0;
    reg [15:0] fp;
    reg force_error=0;
    wire [15:0] pixel,hud_pixel,reference_hud;
    hud_overlay hud(.px(px),.py(py),.minimap_mode(mode),.health(2'd3),.low_blink(1'b0),.wave(7'd15),.zombies(7'd0),
        .pixel_in(fp),.pixel_out(hud_pixel));
    hud_reference hud_oracle(.px(px),.py(py),.minimap_mode(mode),.health(2'd3),.low_blink(1'b0),.wave(7'd15),.zombies(7'd0),
        .pixel_in(fp),.expected(reference_hud));
    map_display_mux display(.px(px),.py(py),.minimap_mode(mode),.fp_pixel_data(hud_pixel),
        .map_bits(bits),.p1_addr(p1),.p2_addr(p2),.seed(seed),.map_ready(ready),
        .busy(busy),.bfs_enabled(1'b1),.error_code(force_error ? 3'd2 : err),
        .pixel_data(pixel));
    integer failures=0,x,y,a,fd,m,cycles,expected,r,g,b;
    initial begin
        px=0; py=0; fp=0;
        repeat(4) @(negedge clk); rst=0;
        cycles=0;
        while(!ready && cycles<41000) begin @(posedge clk); #1; cycles=cycles+1; end
        if(!ready) begin $display("FAIL display: no map"); $finish; end
        for(m=0;m<2;m=m+1) begin
            mode=m;
            if(m==0) fd=$fopen("full_map.ppm","w");
            else fd=$fopen("minimap.ppm","w");
            $fwrite(fd,"P3\n96 64\n255\n");
            for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
                px=x; py=y; fp={px,py,3'b101}; #1;
                expected=reference_hud;
                if(m==1 && x>=32 && x<=95) begin
                    if(x==32 || x==95 || y==0 || y==63) expected=16'hFFFF;
                    else begin
                        a=(y/4)*16+(x-32)/4;
                        expected=bits[a] ? 16'h4AD1 : 16'h0841;
                        if(a==p1) expected=16'h07E0;
                        else if(a==p2) expected=16'hFFE0;
                    end
                end
                if(expected>=0 && pixel!==expected[15:0]) begin
                    failures=failures+1;
                    if(failures<5) $display("FAIL display: mode=%0d pixel=(%0d,%0d)",m,x,y);
                end
                r=pixel[15:11]*255/31; g=pixel[10:5]*255/63; b=pixel[4:0]*255/31;
                $fwrite(fd,"%0d %0d %0d\n",r,g,b);
            end
            $fclose(fd);
        end
        mode=1; px=20; py=20; fp=16'hCAFE; #1;
        if(pixel!==16'hCAFE) begin failures=failures+1; $display("FAIL display: FP port passthrough"); end
        if(failures==0) $display("PASS display: all 6144 pixels in both modes, nonconstant FP pattern, HUD then 64x64 zoom, map occlusion and inset border");
        else $display("FAIL display total=%0d",failures);
        $finish;
    end
endmodule
