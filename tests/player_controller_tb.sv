`timescale 1ns / 1ps
`include "Game_Config.vh"
module player_controller_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, tick=0, event_in=0;
    reg [3:0] buttons=0; // U,D,L,R
    reg [11:0] mouse_x=0;
    wire [31:0] x,y,angle;
    Player_Controller #(.DEBOUNCE_CYCLES(3)) dut (
        .clk(clk), .reset(reset), .game_tick(tick),
        .btnU(buttons[3]), .btnD(buttons[2]), .btnL(buttons[1]), .btnR(buttons[0]),
        .mouse_x(mouse_x), .mouse_event(event_in), .x_coord(x), .y_coord(y), .theta(angle)
    );
    // Open map tests bounds independently of enclosing walls.
    wire [31:0] open_x,open_y,open_angle;
    Player_Controller #(.DEBOUNCE_CYCLES(3), .MAP(256'd0)) open_map (
        .clk(clk), .reset(reset), .game_tick(tick),
        .btnU(buttons[3]), .btnD(buttons[2]), .btnL(buttons[1]), .btnR(buttons[0]),
        .mouse_x(mouse_x), .mouse_event(event_in),
        .x_coord(open_x), .y_coord(open_y), .theta(open_angle)
    );
    task cycle; begin @(posedge clk); #1; @(negedge clk); end endtask
    task restart;
        begin
            reset=1; tick=0; event_in=0; buttons=0; mouse_x=0;
            cycle; cycle;
            if (x!==`GAME_SPAWN_X || y!==`GAME_SPAWN_Y || angle!==`GAME_SPAWN_ANGLE)
                $fatal(1,"Controller reset failed");
            reset=0; cycle;
        end
    endtask
    task point_at(input integer a);
        begin
            mouse_x=(a-128)&1023; event_in=1; cycle; event_in=0; cycle;
        end
    endtask
    task press(input [3:0] b);
        begin buttons=b; repeat(6) cycle; end
    endtask
    task update_player;
        reg [95:0] before_update;
        begin
            before_update={x,y,angle}; tick=1; cycle; tick=0;
            if ({x,y,angle}!==before_update) $fatal(1,"State changed before commit");
            repeat(4) begin
                cycle;
                if ({x,y,angle}!==before_update) $fatal(1,"Non-atomic pipeline update");
            end
            if ({x,y,angle}!==before_update) $fatal(1,"Non-atomic state update");
            cycle;
        end
    endtask
    integer a,b,s,c,dx,dy,raw_x,raw_y,n;
    reg f_active,r_active;
    reg [95:0] saved;
    real pi=3.141592653589793;
    initial begin
        restart;
        // Short bouncing pulses cannot assert/deassert the debounced level.
        buttons=8; cycle; buttons=0; repeat(5) cycle;
        if (dut.forward_down) $fatal(1,"Debounce accepted short pulse");
        press(8);
        if (!dut.forward_down) $fatal(1,"Debounce missed stable press");
        buttons=0; cycle; buttons=8; repeat(5) cycle;
        if (!dut.forward_down) $fatal(1,"Debounce accepted short release");
        press(0);
        if (dut.forward_down) $fatal(1,"Debounce missed stable release");

        // Independent trig reference: all 1024 orientations, all 16 button masks.
        for(a=0;a<1024;a=a+1) begin
            s=$rtoi($floor(128.0*$sin((a%512)*pi/512.0)+0.5));
            if (a>=512) s=-s;
            n=(a+256)%1024;
            c=$rtoi($floor(128.0*$sin((n%512)*pi/512.0)+0.5));
            if (n>=512) c=-c;
            for(b=0;b<16;b=b+1) begin
                restart; point_at(a); press(b);
                f_active=((b>>3)&1)^((b>>2)&1);
                r_active=((b>>1)&1)^(b&1);
                raw_x=f_active ? ((b&8) ? s*4 : -s*4) : 0;
                raw_y=f_active ? ((b&8) ? c*4 : -c*4) : 0;
                if(r_active) begin
                    raw_x=raw_x+((b&1) ? c*4 : -c*4);
                    raw_y=raw_y+((b&1) ? -s*4 : s*4);
                end
                dx=raw_x; dy=raw_y;
                if(f_active && r_active) begin dx=(raw_x*3)>>>2; dy=(raw_y*3)>>>2; end
                update_player;
                if(x!==34816+dx || y!==34816+dy || angle!==a)
                    $fatal(1,"Movement angle=%0d mask=%0d got %0d,%0d,%0d expected delta=%0d,%0d",
                        a,b,x,y,angle,dx,dy);
                saved={x,y,angle}; repeat(2) cycle;
                if({x,y,angle}!==saved) $fatal(1,"Moved without game tick");
            end
        end

        restart; point_at(0); press(8);
        repeat(300) update_player;
        if(y!==39936 || x!==34816) $fatal(1,"Passed through north block"); // 9.75
        if(open_y!==64512) $fatal(1,"Open-map north bound failed"); // 15.75
        point_at(128);
        repeat(20) update_player;
        if(x<=34816 || y<39936 || y>=40448) $fatal(1,"Failed to slide along block");
        restart; point_at(256); press(8); repeat(300) update_player;
        if(x!==60416 || open_x!==64512) $fatal(1,"East wall/bound failed");
        restart; point_at(512); press(8); repeat(300) update_player;
        if(y!==4608 || open_y!==512) $fatal(1,"South wall/bound failed");
        restart; point_at(768); press(8); repeat(300) update_player;
        if(x!==4608 || open_x!==512) $fatal(1,"West wall/bound failed");

        // Latest of multiple events wins; left/right moves wrap 1023 -> 0.
        restart; point_at(1023); point_at(0); update_player;
        if(angle!==0) $fatal(1,"Lost mouse event/clockwise wrap");
        point_at(1023); update_player;
        if(angle!==1023) $fatal(1,"Counterclockwise wrap");
        mouse_x=960; event_in=1; tick=1; cycle;
        event_in=0; tick=0; repeat(5) cycle;
        update_player;
        if(angle!==64) $fatal(1,"Simultaneous event and tick lost");

        // Every in-flight stage can be reset, even when a tick is asserted.
        for(n=0;n<6;n=n+1) begin
            restart; press(8); tick=1; cycle; tick=0;
            repeat(n) cycle;
            reset=1; tick=1; cycle;
            if(x!==34816 || y!==34816 || angle!==128 || dut.state!==0)
                $fatal(1,"Reset during movement stage %0d",n);
        end
        $display("PASS: 16384 movement references; debounce; opposing/diagonal controls; mouse wrap/events; wall sliding; map bounds; atomic commits; reset");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Controller timeout"); end
endmodule
