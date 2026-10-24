`timescale 1ns / 1ps
module tb_hud;
    reg [6:0] px=0,wave=0,zombies=0;
    reg [1:0] health=0;
    reg blink=0;
    reg [5:0] py=0;
    reg mode=0;
    reg [15:0] pixel_in=0;
    wire [15:0] pixel_out,expected;
    hud_overlay dut(.px(px),.py(py),.minimap_mode(mode),.health(health),.low_blink(blink),
        .wave(wave),.zombies(zombies),.pixel_in(pixel_in),.pixel_out(pixel_out));
    hud_reference oracle(.px(px),.py(py),.minimap_mode(mode),.health(health),.low_blink(blink),
        .wave(wave),.zombies(zombies),.pixel_in(pixel_in),.expected(expected));
    integer ws[0:3];
    integer h,b,j,m,x,y,failures=0,checked=0,fd,red;
    initial begin
        ws[0]=0; ws[1]=7; ws[2]=15; ws[3]=127;
        for(h=0;h<4;h=h+1) for(b=0;b<2;b=b+1) for(j=0;j<4;j=j+1) for(m=0;m<2;m=m+1) begin
            health=h; blink=b; wave=ws[j]; zombies=ws[3-j]; mode=m; red=0;
            for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
                px=x; py=y; pixel_in={px,py,3'b101}; #1;
                checked=checked+1;
                if(pixel_out===16'hF800) red=red+1;
                if(pixel_out!==expected) begin
                    failures=failures+1;
                    if(failures<8) $display("FAIL hud: h=%0d blink=%0d w=%0d mode=%0d (%0d,%0d) got=%h expected=%h",h,b,wave,m,x,y,pixel_out,expected);
                end
                if(m==1 && x>=32 && pixel_out!==pixel_in) begin
                    failures=failures+1; $display("FAIL hud: overlaps map footprint");
                end
            end
            // 16 lit pixels per heart.
            if(red != 16*((h==1 && b) ? 0 : h)) begin
                failures=failures+1; $display("FAIL hud: h=%0d blink=%0d shows %0d red pixels",h,b,red);
            end
        end
        health=3; blink=0; wave=3; zombies=5; mode=0;
        fd=$fopen("hud_preview.ppm","w"); $fwrite(fd,"P3\n96 64\n255\n");
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            px=x; py=y; pixel_in=(y<32) ? 16'h1084 : 16'h3166; #1;
            $fwrite(fd,"%0d %0d %0d\n",pixel_out[15:11]*255/31,pixel_out[10:5]*255/63,pixel_out[4:0]*255/31);
        end
        $fclose(fd);
        if(failures==0) $display("PASS hud: %0d pixels, hearts 0-3 with and without low-health blink, waves and zombie counts incl. clamp, both modes, independent oracle, nonconstant input",checked);
        else $display("FAIL hud total=%0d",failures);
        $finish;
    end
endmodule
