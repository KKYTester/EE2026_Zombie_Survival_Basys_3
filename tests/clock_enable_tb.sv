`timescale 1ns / 1ps
`include "Game_Config.vh"

module clock_enable_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg player_tick = 0;
    reg [31:0] dx = 3, dy = 5, omega = 7;
    wire [31:0] x, y, theta;
    wire [15:0] pixels, single_cycle_pixels, default_pixels;
    wire [7:0] jb;
    tri1 ps2_clk, ps2_data;
    My_Top_Module board (.clk(clk), .JB(jb), .btnC(1'b0), .sw0(1'b0), .sw13(1'b0), .sw14(1'b0), .sw15(1'b0), .btnU(1'b0), .btnL(1'b0),
        .btnR(1'b0), .btnD(1'b0), .ps2_clk(ps2_clk), .ps2_data(ps2_data), .led());

    Player player (
        .clk(clk), .reset(reset), .game_tick(player_tick),
        .dx(dx), .dy(dy), .omega(omega),
        .x_coord(x), .y_coord(y), .theta(theta)
    );
    // Short periods exercise multiple pulses and independent enable rates.
    Map_Renderer #(.CLK_HZ(96), .GAME_HZ(24), .PIXEL_UPDATE_HZ(12)) dut (
        .clk(clk), .reset(reset), .display_clk(clk), .frame_begin(1'b0),
        .pixel_index(13'd0), .pixel_data(pixels), .column_depth(),
        .x_coord(x), .y_coord(y), .theta(theta), .game_tick()
    );
    Map_Renderer #(.CLK_HZ(24), .GAME_HZ(24), .PIXEL_UPDATE_HZ(24)) single_cycle (
        .clk(clk), .reset(reset), .display_clk(clk), .frame_begin(1'b0),
        .pixel_index(13'd0), .pixel_data(single_cycle_pixels), .column_depth(),
        .x_coord(`GAME_SPAWN_X), .y_coord(`GAME_SPAWN_Y), .theta(`GAME_SPAWN_ANGLE), .game_tick()
    );
    Map_Renderer defaults (
        .clk(clk), .reset(reset), .display_clk(clk), .frame_begin(1'b0),
        .pixel_index(13'd0), .pixel_data(default_pixels), .column_depth(),
        .x_coord(`GAME_SPAWN_X), .y_coord(`GAME_SPAWN_Y), .theta(`GAME_SPAWN_ANGLE), .game_tick()
    );

    integer cycle, game_updates, pixel_updates;
    reg sampled_game_tick, sampled_pixel_tick;
    integer startup_cycle;

    initial begin
        for (startup_cycle = 1; startup_cycle <= 256; startup_cycle = startup_cycle + 1) begin
            @(posedge clk);
            #1;
            if (board.reset !== (startup_cycle < 2))
                $fatal(1, "Top-level startup reset failed at cycle %0d", startup_cycle);
        end
    end

    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        step;
        if ({x,y,theta} !== 96'd0 || pixels !== 16'd0)
            $fatal(1, "Reset failed");
        @(negedge clk);
        reset = 0;
        #1; // Allow combinational enables to reflect reset release.

        game_updates = 0;
        pixel_updates = 0;
        for (cycle = 1; cycle <= 32; cycle = cycle + 1) begin
            // Sample enables before the consuming edge, then check its results.
            sampled_game_tick = dut.game_tick;
            sampled_pixel_tick = dut.pixel_tick;
            if (sampled_game_tick !== ((cycle % 4) == 0))
                $fatal(1, "Game enable period/width failed at cycle %0d", cycle);
            if (sampled_pixel_tick !== ((cycle % 8) == 0))
                $fatal(1, "Pixel enable period/width failed at cycle %0d", cycle);
            if (single_cycle.game_tick !== 1'b1 || single_cycle.pixel_tick !== 1'b1)
                $fatal(1, "One-cycle period failed");
            player_tick = (cycle == 3 || cycle == 17);
            step;
            if (sampled_game_tick) game_updates = game_updates + 1;
            if (sampled_pixel_tick) pixel_updates = pixel_updates + 1;
            if (cycle < 3) begin
                if ({x,y,theta} !== 96'd0) $fatal(1, "Player changed without enable");
            end else if (cycle < 17) begin
                if (x !== 3 || y !== 5 || theta !== 7) $fatal(1, "Player failed hold/update");
            end else begin
                if (x !== 6 || y !== 10 || theta !== 14) $fatal(1, "Player failed second update");
            end
            @(negedge clk);
        end
        if (game_updates != 8 || pixel_updates != 4) $fatal(1, "Incorrect pulse totals");

        // Reset must work without waiting for a game tick and must beat an enable.
        reset = 1;
        player_tick = 1;
        step;
        if ({x,y,theta} !== 96'd0 ||
            dut.game_counter !== 0 || dut.pixel_counter !== 0 ||
            dut.game_tick !== 0 || dut.pixel_tick !== 0)
            $fatal(1, "Reset priority/counter restart failed");
        @(negedge clk);
        player_tick = 0;
        reset = 0;
        #1;
        // Verify the actual default divider, including two successive game ticks.
        for (cycle = 1; cycle <= 8_333_334; cycle = cycle + 1) begin
            if (defaults.game_tick !== ((cycle % 4_166_667) == 0))
                $fatal(1, "Default game timing failed at cycle %0d", cycle);
            if (defaults.pixel_tick !== ((cycle % 4) == 0))
                $fatal(1, "Default pixel timing failed at cycle %0d", cycle);
            step;
            if (board.map_valid_delayed && (board.player_angle !== `GAME_SPAWN_ANGLE ||
                board.player_x !== board.spawn_x || board.player_y !== board.spawn_y))
                $fatal(1, "Player moved without input at cycle %0d", cycle);
            @(negedge clk);
        end
        $display("PASS: player hold/update/reset; enable periods/widths; reset restart; default 24 Hz and 25 MHz timing; no automatic spin/movement");
        $finish;
    end
endmodule
