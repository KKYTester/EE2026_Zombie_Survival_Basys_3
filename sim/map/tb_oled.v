`timescale 1ns / 1ps
module tb_oled;
    reg clk=0;
    always #5 clk=~clk;
    reg btnU=1,sw0=0;
    wire [7:0] JB;
    wire [15:0] led;
    map_preview_top dut(.clk(clk),.sw0(sw0),.sw_wave(4'd15),.sw_health(7'd127),.btnC(1'b0),.btnU(btnU),.led(led),.JB(JB));
    integer pixels=0,bit_count=0,failures=0,frames=0,max_queue=0;
    integer commands_in=0,commands_out=0;
    reg command_bits[0:8191];
    reg [15:0] serial_word=0;
    wire [6:0] ref_x=pixels%96;
    wire [5:0] ref_y=pixels/96;
    wire [15:0] fp_data=ref_y<32 ? 16'h1084 : 16'h3166;
    wire [15:0] expected,reference_hud;
    hud_reference reference_overlay(.px(ref_x),.py(ref_y),.minimap_mode(frames!=0),
        .health(7'd99),.wave(7'd15),.pixel_in(fp_data),.expected(reference_hud));
    map_display_mux reference_display(.px(ref_x),.py(ref_y),.minimap_mode(frames!=0),
        .fp_pixel_data(reference_hud),.map_bits(dut.frame_map),.p1_addr(dut.frame_p1),
        .p2_addr(dut.frame_p2),.seed(dut.frame_seed),.map_ready(dut.frame_ready),
        .busy(dut.frame_busy),.bfs_enabled(1'b1),.error_code(dut.frame_error),
        .pixel_data(expected));
    initial begin
        repeat(40) @(negedge clk); btnU=0;
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
                        if(failures<5) $display("FAIL oled: frame %0d pixel %0d received=%h expected=%h",frames,pixels,serial_word,expected);
                    end
                    bit_count=0; pixels=pixels+1;
                    if(pixels==6144) sw0=1;
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
        if(frames==2) begin
            repeat(100) @(posedge dut.oled_clk);
            if(commands_in!=commands_out) begin
                $display("FAIL oled: missing command bits in=%0d out=%0d",commands_in,commands_out);
                failures=failures+1;
            end
            if(failures==0) $display("PASS oled: two complete 6144-pixel frames (HUD view/HUD plus 64x64 zoom), command preservation, max queue=%0d",max_queue);
            else $display("FAIL oled total=%0d",failures);
            $finish;
        end
    end
    initial begin
        #250000000;
        $display("FAIL oled: startup/frame timeout after %0d frames",frames);
        $finish;
    end
endmodule
