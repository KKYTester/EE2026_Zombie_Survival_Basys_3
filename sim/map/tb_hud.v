`timescale 1ns / 1ps
module tb_hud;
    reg [6:0] px=0,health=0,wave=0;
    reg [5:0] py=0;
    reg mode=0;
    reg [15:0] pixel_in=0;
    wire [15:0] pixel_out,expected;
    hud_overlay dut(.px(px),.py(py),.minimap_mode(mode),.health(health),.wave(wave),
        .pixel_in(pixel_in),.pixel_out(pixel_out));
    hud_reference oracle(.px(px),.py(py),.minimap_mode(mode),.health(health),.wave(wave),
        .pixel_in(pixel_in),.expected(expected));
    integer hs[0:4],ws[0:3];
    integer i,j,m,x,y,failures=0,checked=0,fd;
    initial begin
        hs[0]=0; hs[1]=24; hs[2]=25; hs[3]=99; hs[4]=127;
        ws[0]=0; ws[1]=7; ws[2]=15; ws[3]=127;
        for(i=0;i<5;i=i+1) for(j=0;j<4;j=j+1) for(m=0;m<2;m=m+1) begin
            health=hs[i]; wave=ws[j]; mode=m;
            for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
                px=x; py=y; pixel_in={px,py,3'b101}; #1;
                checked=checked+1;
                if(pixel_out!==expected) begin
                    failures=failures+1;
                    if(failures<8) $display("FAIL hud: h=%0d w=%0d mode=%0d (%0d,%0d) got=%h expected=%h",health,wave,m,x,y,pixel_out,expected);
                end
                if(m==1 && x>=32 && pixel_out!==pixel_in) begin
                    failures=failures+1; $display("FAIL hud: overlaps map footprint");
                end
            end
        end
        health=99; wave=15; mode=0;
        fd=$fopen("hud_preview.ppm","w"); $fwrite(fd,"P3\n96 64\n255\n");
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            px=x; py=y; pixel_in=(y<32) ? 16'h1084 : 16'h3166; #1;
            $fwrite(fd,"%0d %0d %0d\n",pixel_out[15:11]*255/31,pixel_out[10:5]*255/63,pixel_out[4:0]*255/31);
        end
        $fclose(fd);
        if(failures==0) $display("PASS hud: %0d pixels, all requested health/wave cases plus wave clamp, both modes, independent oracle, nonconstant input",checked);
        else $display("FAIL hud total=%0d",failures);
        $finish;
    end
endmodule
