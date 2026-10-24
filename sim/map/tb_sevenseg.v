`timescale 1ns / 1ps
module tb_sevenseg;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [15:0] value=0;
    wire [6:0] seg;
    wire dp;
    wire [3:0] an;
    seven_seg_hex dut(.clk(clk),.rst(rst),.value(value),.seg(seg),.dp(dp),.an(an));
    integer failures=0,n,d,cycles;
    reg [6:0] lit[0:15];
    reg [3:0] wanted;
    task check;
        input [3:0] nib;
        input [3:0] anode;
        begin
            #1;
            if(an!==anode || seg!==(~lit[nib]) || dp!==1) begin
                $display("FAIL sevenseg: nibble=%h an=%b expected_an=%b seg=%b",nib,an,anode,seg);
                failures=failures+1;
            end
        end
    endtask
    // Independent active-high segment masks, bit zero=A through bit six=G.
    initial begin
        lit[0]=7'h3F; lit[1]=7'h06; lit[2]=7'h5B; lit[3]=7'h4F;
        lit[4]=7'h66; lit[5]=7'h6D; lit[6]=7'h7D; lit[7]=7'h07;
        lit[8]=7'h7F; lit[9]=7'h6F; lit[10]=7'h77; lit[11]=7'h7C;
        lit[12]=7'h39; lit[13]=7'h5E; lit[14]=7'h79; lit[15]=7'h71;
        repeat(3) @(negedge clk);
        if(an!==4'b1111 || seg!==7'b1111111 || dp!==1) begin
            $display("FAIL sevenseg: reset blanking"); failures=failures+1;
        end
        rst=0;
        // Exercise every glyph at every physical digit, using actual scan timing.
        for(d=0;d<4;d=d+1) begin
            for(n=0;n<16;n=n+1) begin
                @(negedge clk); value={4{n[3:0]}};
                check(n[3:0],~(4'b0001<<d));
            end
            if(d<3) begin
                wanted=~(4'b0010<<d); cycles=0;
                while(an!==wanted && cycles<65537) begin
                    @(posedge clk); #1; cycles=cycles+1;
                end
                if(an!==wanted) begin
                    $display("FAIL sevenseg: missing digit transition"); failures=failures+1;
                end
            end
        end
        // Reset the real counter and scan 1ACE: right-to-left E,C,A,1.
        @(negedge clk); rst=1; value=16'h1ACE;
        repeat(2) @(negedge clk); rst=0;
        check(4'hE,4'b1110);
        for(d=1;d<=4;d=d+1) begin
            wanted=an; cycles=0;
            while(an===wanted && cycles<65537) begin
                @(posedge clk); #1; cycles=cycles+1;
            end
            if(cycles!=65536) begin
                $display("FAIL sevenseg: digit period=%0d",cycles); failures=failures+1;
            end
            case(d)
                1: check(4'hC,4'b1101);
                2: check(4'hA,4'b1011);
                3: check(4'h1,4'b0111);
                4: check(4'hE,4'b1110);
            endcase
        end
        if(failures==0) $display("PASS sevenseg: all 16 hex glyphs at all four digits, scan order/dwell/wrap, reset, 1ACE left-to-right, DP off");
        else $display("FAIL sevenseg total=%0d",failures);
        $finish;
    end
    initial begin #10000000; $display("FAIL sevenseg: timeout"); $finish; end
endmodule
