`timescale 1ns / 1ps
// Decode the actual JB SPI stream, including the tail bridge. Expected world
// pixels come from an independent real-valued trig/ray reference on the
// generated map; the existing compositor supplies the unchanged UI layers.
module oled_renderer_tb;
    reg clk=0, btnC=0, sw0=0;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    wire [7:0] jb;
    My_Top_Module #(.DEBOUNCE_CYCLES(2),.GEN_SHIFT(8)) board (
        .clk(clk),.JB(jb),.btnC(btnC),.btnU(1'b0),.btnL(1'b0),.btnR(1'b0),.btnD(1'b0),
        .sw0(sw0),.sw13(1'b0),.sw14(1'b0),.sw15(1'b0),
        .ps2_clk(ps2_clk),.ps2_data(ps2_data),.led(),.seg(),.dp(),.an());
    integer heights[0:95], depths[0:95];
    integer pixel=0, bits=0, frames=0;
    reg [15:0] shift=0;
    reg checking=0;
    wire [6:0] px=pixel%96;
    wire [5:0] py=pixel/96;
    integer top, grey;
    reg [15:0] reference_world;
    wire [15:0] expected;
    always @* begin
        top=(64-heights[px])/2;
        grey=23-((depths[px]/64)>7 ? 7 : depths[px]/64);
        reference_world=py<top ? 16'h18e7 : py<top+heights[px] ?
            ((grey<<11)|((2*grey+1)<<5)|grey) : 16'h3184;
    end
    pixel_compositor reference_ui(
        .px(px),.py(py),.world_pixel(reference_world),
        .game_state(board.game.frame_screen),.minimap_mode(board.game.frame_mode),
        .map_bits(board.game.frame_map),.p1_addr(board.game.frame_p1),.p2_addr(board.game.frame_p2),
        .player_x(board.game.frame_pos_x),.player_y(board.game.frame_pos_y),.player_angle(board.game.frame_angle),
        .seed(board.game.frame_seed),.map_ready(board.game.frame_ready),.map_busy(board.game.frame_busy),
        .error_code(board.game.frame_error),.health(board.game.frame_health),.low_blink(board.game.frame_blink),
        .wave(board.game.frame_wave),.remaining(board.game.frame_remaining),.zombie_tiles(board.game.frame_zombies),
        .tint(board.game.frame_tint),.weapon_recoil(board.game.frame_recoil),.weapon_flash(board.game.frame_flash),
        .weapon_reloading(board.game.frame_reloading),.ammo(board.game.frame_ammo),.weapon_drop(board.game.frame_drop),
        .menu_sel(board.game.frame_sel),.cursor_x(board.game.frame_cx),.cursor_y(board.game.frame_cy),
        .progress(board.game.frame_progress),.over_ready(board.game.frame_over_ready),.pixel_out(expected));
    task build_reference;
        integer c, offset, a, sx, sy, x, y, steps, factor, depth;
        real pi, sv;
        reg wall;
        begin
            pi=3.141592653589793;
            for(c=0;c<96;c++) begin
                offset=$rtoi($floor(-85.0+170.0*c/95.0+0.5));
                a=(128+offset+1024)%1024;
                sx=$rtoi($floor(128.0*$sin(a*pi/512.0)+0.5));
                sy=$rtoi($floor(128.0*$cos(a*pi/512.0)+0.5));
                x=board.spawn_x; y=board.spawn_y; steps=0; wall=0;
                while(!wall && steps<768 && x>=0 && x<65536 && y>=0 && y<65536) begin
                    wall=board.published_map[(15-(y/4096))*16+(x/4096)];
                    if(!wall) begin x=x+sx; y=y+sy; steps++; end
                end
                if(!wall) $fatal(1,"Reference missed enclosing wall");
                factor=$rtoi($floor(4096.0*$cos(offset*pi/512.0)+0.5));
                depth=(steps*factor+2048)/4096;
                depths[c]=depth;
                heights[c]=depth<=32 ? 64 : 2048/depth;
            end
        end
    endtask
    initial begin
        force board.mouse_event=0; force board.mouse_left=0; force board.mouse_right=0;
        wait(!board.reset); repeat(5) @(negedge clk);
        btnC=1; repeat(10) @(negedge clk); btnC=0;
        wait(board.playing); repeat(5) @(negedge clk);
        build_reference;
        // Skip only hardware power-up delays. Pixel/SPI/frame timings stay real.
        wait(!board.game.oled_reset);
        force board.game.oled.delay=0;
        wait(board.game.oled.state==board.game.oled.WaitNextFrame);
        @(posedge clk); release board.game.oled.delay;
        wait(board.u_Map_Renderer.display_valid);
        // Enter checking before the first complete gameplay frame's stream.
        wait(board.game.frame_screen==3);
        checking=1;
    end
    always @(posedge jb[3]) begin
        if(checking && !jb[0] && jb[4]) begin
            shift={shift[14:0],jb[1]}; bits++;
            if(bits==16) begin
                if(shift!==expected) $fatal(1,"SPI frame %0d pixel %0d got %h expected %h (world %h)",frames,pixel,shift,expected,reference_world);
                bits=0;
                if(pixel==6143) begin
                    frames++; pixel=0;
                    if(frames==1) sw0=1; // Second frame exercises the full map overlay.
                    if(frames==2) begin
                        $display("PASS: two complete 6144-pixel JB OLED frames, generated-map ray reference, HUD/weapon and minimap, final pixel");
                        $finish;
                    end
                end else pixel++;
            end
        end
    end
    initial begin #80000000; $fatal(1,"OLED integration timeout frames=%0d pixel=%0d",frames,pixel); end
endmodule
