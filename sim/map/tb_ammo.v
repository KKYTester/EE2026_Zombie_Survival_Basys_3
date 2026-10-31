`timescale 1ns / 1ps
// ammo_overlay against an independent integer oracle (own bullet layout and
// own 3x5 bitmaps for R E L O A D): every pixel for ammo 0..6, reloading on/off,
// shown/hidden, nonconstant input. Also counts loaded/spent bullet pixels.
module tb_ammo;
    reg [6:0] px=0; reg [5:0] py=0;
    reg show=1, reloading=0;
    reg [2:0] ammo=6;
    reg [15:0] pixel_in=0;
    wire [15:0] pixel_out;
    ammo_overlay dut(.px(px),.py(py),.show(show),.ammo(ammo),.reloading(reloading),
        .pixel_in(pixel_in),.pixel_out(pixel_out));
    integer a,r,s,x,y,i,failures=0,checked=0,brass,spent,text,fd;
    reg [15:0] expected;
    reg [14:0] glyph;
    function [14:0] letter;
        input integer n;
        case(n)
            0: letter=15'b110101110101101;   // R
            1: letter=15'b111100110100111;   // E
            2: letter=15'b100100100100111;   // L
            3: letter=15'b111101101101111;   // O
            4: letter=15'b010101111101101;   // A
            default: letter=15'b110101101101110;   // D
        endcase
    endfunction
    task model;
        begin
            expected=pixel_in;
            if(s) begin
                for(i=0;i<6;i=i+1)
                    if(x==83+2*i && y>=56 && y<=60)
                        expected = (i>=a) ? 16'h4208 : (y==56 ? 16'hFF9A : 16'hF645);
                if(r && y>=49 && y<=53 && x>=72 && x<96) begin
                    glyph=letter((x-72)/4);
                    if((x-72)%4<3 && glyph[14-((y-49)*3+(x-72)%4)]) expected=16'hFC62;
                end
            end
        end
    endtask
    initial begin
        for(a=0;a<=6;a=a+1) for(r=0;r<2;r=r+1) for(s=0;s<2;s=s+1) begin
            ammo=a; reloading=r; show=s; brass=0; spent=0; text=0;
            for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
                px=x; py=y; pixel_in={x[6:0],y[5:0],3'b011}; #1;
                model; checked=checked+1;
                if(pixel_out===16'hF645) brass=brass+1;
                if(pixel_out===16'h4208) spent=spent+1;
                if(pixel_out===16'hFC62) text=text+1;
                if(pixel_out!==expected) begin
                    failures=failures+1;
                    if(failures<8) $display("FAIL ammo: a=%0d r=%0d s=%0d (%0d,%0d) got %h expected %h",a,r,s,x,y,pixel_out,expected);
                end
            end
            if(s && (brass!=4*a || spent!=5*(6-a))) begin
                failures=failures+1; $display("FAIL ammo: a=%0d shows %0d brass / %0d spent pixels",a,brass,spent);
            end
            if(s && r && text<40) begin failures=failures+1; $display("FAIL ammo: RELOAD text missing"); end
            if((!s || !r) && text!=0) begin failures=failures+1; $display("FAIL ammo: RELOAD text when not reloading"); end
        end
        // Preview: 4 rounds left while reloading, over the floor colour.
        fd=$fopen("ammo_preview.ppm","w"); $fwrite(fd,"P3\n96 64\n255\n");
        ammo=4; reloading=1; show=1;
        for(y=0;y<64;y=y+1) for(x=0;x<96;x=x+1) begin
            px=x; py=y; pixel_in=(y<32) ? 16'h1084 : 16'h3166; #1;
            $fwrite(fd,"%0d %0d %0d\n",pixel_out[15:11]*255/31,pixel_out[10:5]*255/63,pixel_out[4:0]*255/31);
        end
        $fclose(fd);
        if(failures==0) $display("PASS ammo: %0d pixels, ammo 0-6 with and without RELOAD text, shown and hidden, independent oracle, nonconstant input",checked);
        else $display("FAIL ammo total=%0d",failures);
        $finish;
    end
endmodule
