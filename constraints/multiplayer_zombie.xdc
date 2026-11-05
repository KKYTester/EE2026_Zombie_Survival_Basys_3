# Two-board game link and local movement controls for My_Top_Module.
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports uart_tx_pin]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports uart_rx_pin]
set_false_path -from [get_ports uart_rx_pin] -to [get_pins {multiplayer_game/multiplayer_link_i/receiver/rx_sync_reg[0]/D}]

# Basys 3 pushbuttons (BTN D selects player mode on the title screen).
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports btnL]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33} [get_ports btnR]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports btnD]
set_false_path -from [get_ports btnL] -to [get_pins {multiplayer_game/game/button_left/sync_ff_reg[0]/D}]
set_false_path -from [get_ports btnR] -to [get_pins {multiplayer_game/button_right/sync_ff_reg[0]/D}]
set_false_path -from [get_ports btnD] -to [get_pins {multiplayer_game/button_down/sync_ff_reg[0]/D}]

# SW3 selects host (1) or client (0); SW[7:4] move the active player.
set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS33} [get_ports sw3]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports sw4]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports sw5]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports sw6]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports sw7]
set_false_path -from [get_ports sw3] -to [get_pins {multiplayer_game/role_sync_reg[0]/D}]
set_false_path -from [get_ports sw4] -to [get_pins {multiplayer_game/move_meta_reg[0]/D}]
set_false_path -from [get_ports sw5] -to [get_pins {multiplayer_game/move_meta_reg[1]/D}]
set_false_path -from [get_ports sw6] -to [get_pins {multiplayer_game/move_meta_reg[2]/D}]
set_false_path -from [get_ports sw7] -to [get_pins {multiplayer_game/move_meta_reg[3]/D}]

set_false_path -from [get_ports btnC] -to [get_pins {multiplayer_game/fire_meta_reg/D}]
set_false_path -from [get_ports btnL] -to [get_pins {multiplayer_game/reload_meta_reg/D}]
