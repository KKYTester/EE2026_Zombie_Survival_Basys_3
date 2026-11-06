# Two-board link for My_Top_Module (same bitstream on both boards).
# SW1: down = host / Player 1 board, up = Player 2 board.
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports sw1]
set_false_path -from [get_ports sw1]

# UART on Pmod JC: JC1 (K17) = TX, JC2 (M18) = RX. Cross TX->RX between the
# boards and connect GND to GND.
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports uart_tx_pin]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports uart_rx_pin]
set_false_path -from [get_ports uart_rx_pin]
set_false_path -to [get_ports uart_tx_pin]
