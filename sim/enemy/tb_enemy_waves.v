`timescale 1ns / 1ps
// Exercise the real wave controller handshake through a complete short session.
module tb_enemy_waves;
    reg clk=0, rst=1, start=0, playing=0, defeat=0;
    reg [255:0] map_bits;
    wire req,ack,dead,clear_wave,won,spawn_busy;
    wire [7:0] tile,active;
    wire [255:0] occupied;
    wire [6:0] wave,remaining;
    wire [5:0] alive;
    integer i,cycles,spawns=0,kills=0,live_count;
    always #5 clk=~clk;
    wave_controller #(.SPAWN_SHIFT(2),.CLEAR_SHIFT(2),.MIN_DIST(2),.WIN_WAVE(2)) waves(
        .clk(clk),.rst(rst),.play_start(start),.playing(playing),.map_bits(map_bits),
        .occupied(occupied),.player_tile(8'h11),.spawn_ack(ack),.enemy_defeated(dead),
        .wave(wave),.spawn_req(req),.spawn_tile(tile),.spawn_busy(spawn_busy),
        .alive(alive),.remaining(remaining),
        .wave_clear(clear_wave),.game_won(won));
    enemy_manager enemies(.clk(clk),.rst(rst),.clear(start || !playing),
        .playing(playing),.map_ready(1'b1),.map_bits(map_bits),.spawn_req(req),
        .spawn_tile(tile),.debug_defeat(defeat),.spawn_ack(ack),.enemy_defeated(dead),
        .move_tick(1'b1),.spawn_busy(spawn_busy),.player_tile(8'h11),
        .occupied(occupied),.active(active),.read_id(3'd0),.read_active(),
        .read_x(),.read_y(),.read_hp(),.read_type(),.read_state(),.read_cooldown());
    always @(posedge clk) if(!rst && playing && !start) begin
        if(ack) spawns=spawns+1;
        if(dead) kills=kills+1;
    end
    initial begin
        map_bits=0;
        for(i=0;i<256;i=i+1)
            if(i%16==0 || i%16==15 || i/16==0 || i/16==15) map_bits[i]=1;
        repeat(3) @(negedge clk); rst=0; playing=1; start=1;
        @(negedge clk); start=0;
        cycles=0;
        while(!won && cycles<10000) begin
            // Interleave kills with spawning, leaving time for registered events.
            defeat=(cycles%11==0);
            @(negedge clk); cycles=cycles+1;
            live_count=0;
            for(i=0;i<8;i=i+1) live_count=live_count+active[i];
            if(live_count != alive + (ack ? 1 : 0) - (dead ? 1 : 0))
                $fatal(1,"population mismatch at cycle %0d",cycles);
            if((occupied & map_bits)!=0) $fatal(1,"enemy spawned in wall");
        end
        defeat=0;
        if(!won || wave!=2 || remaining!=0 || active!=0 || spawns!=8 || kills!=8)
            $fatal(1,"wave completion: wave=%0d spawns=%0d kills=%0d",wave,spawns,kills);
        playing=0; repeat(3) @(negedge clk);
        playing=1; start=1; @(negedge clk); start=0;
        if(wave!=1 || remaining!=3 || alive!=0 || active!=0)
            $fatal(1,"restart retained old state");
        $display("TB_ENEMY_WAVES: PASS"); $finish;
    end
    initial begin #200000; $fatal(1,"timeout"); end
endmodule
