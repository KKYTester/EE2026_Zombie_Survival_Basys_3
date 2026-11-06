`timescale 1ns / 1ps
// Reusable, purely combinational OLED drawing chain.
// World -> gun -> HUD -> ammo -> map -> zombie dots -> damage tint.
// Non-playing game states select the full-screen menu instead.
// The caller supplies coherent frame snapshots; no clocks or state live here.
// Use the same module for ordinary pixels and the tail-bridge pixel (95,63).
module pixel_compositor #(parameter STAGE=3, parameter ENABLE_2P=0,
                          parameter SHOW_CURSOR=1)(
    input wire [6:0] px, input wire [5:0] py,
    input wire [15:0] world_pixel,
    input wire [2:0] game_state, input wire minimap_mode,
    // Map snapshot and status.
    input wire [255:0] map_bits,
    input wire [7:0] p1_addr, input wire [7:0] p2_addr,
    // Player marker: 4.4 tiles, y down; angle 1024 per turn, 0 = up, clockwise.
    input wire [7:0] player_x, input wire [7:0] player_y, input wire [9:0] player_angle,
    input wire [15:0] seed,
    input wire map_ready, input wire map_busy, input wire [2:0] error_code,
    // Gameplay HUD and effects.
    input wire [1:0] health, input wire low_blink,
    input wire [6:0] wave, input wire [6:0] remaining,
    input wire [255:0] zombie_tiles, input wire tint,
    // Weapon animation and ammunition.
    input wire weapon_recoil, input wire weapon_flash, input wire weapon_reloading,
    input wire [2:0] ammo, input wire [4:0] weapon_drop,
    // Menu snapshot.
    input wire menu_sel, input wire [6:0] cursor_x, input wire [5:0] cursor_y,
    input wire [5:0] progress, input wire over_ready,
    // Two boards: link status on the title, the other board's wave on the
    // end screens of a 2-player run.
    input wire link_up, input wire two_player,
    input wire [6:0] peer_wave, input wire peer_in_run,
    output wire [15:0] pixel_out);
    wire playing = game_state==3'd3;
    // Menu screen numbers: 0 title, 1 generating, 2 reserved, 3 game over, 4 victory.
    wire [2:0] menu_screen = (game_state==3'd4) ? 3'd3 : (game_state==3'd5) ? 3'd4 : game_state;
    wire [3:0] wave_tens,wave_ones;
    wave_digits end_screen_digits(.value(wave),.tens(wave_tens),.ones(wave_ones));
    wire [3:0] peer_tens,peer_ones;
    wave_digits peer_digits(.value(peer_wave),.tens(peer_tens),.ones(peer_ones));
    wire [15:0] gun_pixel_data,hud_pixel_data,ammo_pixel_data,map_pixel_data,zombie_pixel_data,play_pixel_data,menu_pixel_data;
    weapon_overlay gun(.px(px),.py(py),.show(!minimap_mode),.recoil(weapon_recoil),.flash(weapon_flash),
        .drop(weapon_drop),.pixel_in(world_pixel),.pixel_out(gun_pixel_data));
    hud_overlay hud(.px(px),.py(py),.minimap_mode(minimap_mode),.health(health),
        .low_blink(low_blink),.wave(wave),.zombies(remaining),
        .pixel_in(gun_pixel_data),.pixel_out(hud_pixel_data));
    ammo_overlay ammo_hud(.px(px),.py(py),.show(!minimap_mode),.ammo(ammo),
        .reloading(weapon_reloading),.pixel_in(hud_pixel_data),.pixel_out(ammo_pixel_data));
    map_display_mux display_mux(.px(px),.py(py),.minimap_mode(minimap_mode),
        .fp_pixel_data(ammo_pixel_data),.map_bits(map_bits),.p1_addr(p1_addr),
        .p2_addr(p2_addr),.player_x(player_x),.player_y(player_y),.player_angle(player_angle),
        .seed(seed),.map_ready(map_ready),
        // Each board plays its own world, so no second player is drawn.
        .show_p2(1'b0),
        .busy(map_busy),.bfs_enabled(STAGE==3),.error_code(error_code),
        .pixel_data(map_pixel_data));
    zombie_overlay zombie_dots(.px(px),.py(py),.minimap_mode(minimap_mode),.zombies(zombie_tiles),
        .pixel_in(map_pixel_data),.pixel_out(zombie_pixel_data));
    play_effects effects(.pixel_in(zombie_pixel_data),.tint(tint),
        .pixel_out(play_pixel_data));
    menu_screens #(.ENABLE_2P(ENABLE_2P)) menu(.px(px),.py(py),.screen(menu_screen),
        .sel(menu_sel),.cursor_x(cursor_x),.cursor_y(cursor_y),.show_cursor(SHOW_CURSOR!=0),
        .progress(progress),.wave_tens(wave_tens),
        .wave_ones(wave_ones),.over_ready(over_ready),
        .link_up(link_up),.show_peer(two_player),.peer_tens(peer_tens),.peer_ones(peer_ones),
        .peer_in_run(peer_in_run),.pixel(menu_pixel_data));
    assign pixel_out = playing ? play_pixel_data : menu_pixel_data;
endmodule
