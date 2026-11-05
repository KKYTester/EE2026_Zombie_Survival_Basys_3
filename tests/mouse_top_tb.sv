`timescale 1ns / 1ps
module mouse_top_tb;
    reg clk=0;
    always #5 clk=~clk;
    tri1 ps2_clk,ps2_data;
    reg btnC=0, sw13=0, sw14=0, sw15=0;
    wire [15:0] led;
    My_Top_Module #(.DEBOUNCE_CYCLES(2),.GEN_SHIFT(8),.OVER_SHIFT(8),
        .SPAWN_SHIFT(8),.CLEAR_SHIFT(8),.WIN_WAVE(1),
        .FLASH_SHIFT(5),.RECOIL_SHIFT(6),.RELOAD_SHIFT(6)) board (
        .clk(clk),.JB(),.btnC(btnC),.btnU(1'b0),.btnL(1'b0),.btnR(1'b0),.btnD(1'b0),
        .sw0(1'b0),.sw13(sw13),.sw14(sw14),.sw15(sw15),
        .ps2_clk(ps2_clk),.ps2_data(ps2_data),.led(led),.seg(),.dp(),.an());
    reg signed [8:0] dx=0, dy=0;
    reg event_in=0, left_in=0, right_in=0;
    reg [255:0] first_map;
    task packet(input integer x, y);
        @(negedge clk); dx=x; dy=y; event_in=1;
        @(negedge clk); event_in=0;
        repeat(3) @(negedge clk);
    endtask
    task update_player;
        force board.game_tick=1;
        @(negedge clk); force board.game_tick=0;
        repeat(6) @(negedge clk);
    endtask
    task confirm;
        @(negedge clk); btnC=1;
        repeat(10) @(negedge clk); btnC=0;
        repeat(10) @(negedge clk);
    endtask
    task check_spawn;
        wait(board.playing); repeat(3) @(negedge clk);
        if(board.player_tile!==board.p1_addr || board.published_map[board.player_tile]!==0)
            $fatal(1,"Validated spawn not loaded");
        if(board.player_x[11:0]!==12'h800 || board.player_y[11:0]!==12'h800)
            $fatal(1,"Spawn not centered");
        if(board.game.ammo!==6) $fatal(1,"Menu confirmation fired a shot");
        for(integer row=0;row<16;row++)
            if(board.world_map[row*16 +:16]!==board.published_map[(15-row)*16 +:16])
                $fatal(1,"Map row conversion");
    endtask
    integer n;
    initial begin
        force board.mouse_x_delta=dx; force board.mouse_y_delta=dy;
        force board.mouse_event=event_in;
        force board.mouse_left=left_in; force board.mouse_right=right_in;
        wait(!board.reset); repeat(4) @(negedge clk);
        if(board.game_state!==0) $fatal(1,"Startup title");
        // The disabled 2-player rectangle must not start a session.
        left_in=1; packet(0,0); left_in=0;
        repeat(10) @(negedge clk);
        if(board.game_state!==0) $fatal(1,"Disabled 2P started");
        packet(0,10);
        if(board.mouse_x!==48 || board.mouse_y!==30) $fatal(1,"2D title cursor");
        left_in=1; packet(0,0); left_in=0;
        check_spawn; first_map=board.published_map;
        force board.game_tick=0;
        packet(255,0); packet(1,0); update_player;
        if(board.player_angle!==384) $fatal(1,"Signed positive turn");
        packet(-256,0); update_player;
        if(board.player_angle!==128) $fatal(1,"Signed negative turn");
        update_player;
        if(board.player_angle!==128) $fatal(1,"Held delta replayed");
        if(board.mouse_y!==30) $fatal(1,"Gameplay moved menu cursor");
        confirm;
        if(board.game.ammo!==5) $fatal(1,"Gameplay btnC did not fire");
        right_in=1; packet(0,0); right_in=0;
        repeat(250) @(negedge clk);
        if(board.game.ammo!==6 || board.game.weapon_reloading) $fatal(1,"Reload failed");
        // Preserve the demo's game-over/retry flow via the real test switch.
        repeat(3) begin sw13=~sw13; repeat(20) @(negedge clk); end
        wait(board.game_state==4); repeat(270) @(negedge clk);
        confirm; wait(board.game_state==0);
        repeat(17) @(negedge clk);
        confirm; check_spawn;
        if(board.published_map===first_map) $fatal(1,"New session reused map");
        if(board.player_angle!==128 || board.game.health!==3) $fatal(1,"Restart state");
        // Accelerated single-wave victory uses the same untouched wave FSM.
        wait(board.game.waves.spawned==3);
        repeat(3) begin sw14=~sw14; repeat(20) @(negedge clk); end
        wait(board.game_state==5); repeat(270) @(negedge clk);
        confirm; wait(board.game_state==0);
        sw15=1; repeat(10) @(negedge clk); sw15=0;
        repeat(10) @(negedge clk);
        if(board.game_state!==0 || board.mouse_x!==48 || board.mouse_y!==40)
            $fatal(1,"SW15 reset");
        $display("PASS: mixed-language top, disabled 2P, mouse and btnC starts, random-map spawn, signed turning, fire/reload, game over, victory, retry/reset");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Integrated flow timeout state=%0d",board.game_state); end
endmodule
