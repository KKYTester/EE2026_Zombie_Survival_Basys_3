`timescale 1ns / 1ps
// Project top: the two-board multiplayer version of the current game.
// The common game core owns the menu, maps, HUD and OLED; the multiplayer
// top adds UART synchronization, player controls and the enemy simulation.
module My_Top_Module (
    input wire clk,
    input wire sw0, sw1, sw2, sw3, sw4, sw5, sw6, sw7,
    input wire btnC, btnU, btnL, btnR, btnD,
    inout wire PS2Clk, PS2Data,
    output wire [15:0] led,
    output wire [7:0] JB,
    output wire [6:0] seg,
    output wire dp,
    output wire [3:0] an,
    output wire uart_tx_pin,
    input wire uart_rx_pin
);
    enemy_test_top #(.USE_MOUSE(0),.ENABLE_2P(1)) multiplayer_game (
        .clk(clk),.sw0(sw0),.sw1(sw1),.sw2(sw2),.sw3(sw3),
        .sw4(sw4),.sw5(sw5),.sw6(sw6),.sw7(sw7),
        .btnC(btnC),.btnU(btnU),.btnL(btnL),.btnR(btnR),.btnD(btnD),
        .PS2Clk(PS2Clk),.PS2Data(PS2Data),.led(led),.JB(JB),
        .seg(seg),.dp(dp),.an(an),.uart_tx_pin(uart_tx_pin),.uart_rx_pin(uart_rx_pin)
    );
endmodule
