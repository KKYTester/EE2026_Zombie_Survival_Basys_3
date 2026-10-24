# ASSUMPTION: Basys 3, 100 MHz W5 clock, Pmod OLEDrgb on JB.
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk -period 10.000 [get_ports clk]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports sw0]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports btnC]
set_property -dict {PACKAGE_PIN T18 IOSTANDARD LVCMOS33} [get_ports btnU]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {led[8]}]
set_property -dict {PACKAGE_PIN V3 IOSTANDARD LVCMOS33} [get_ports {led[9]}]
set_property -dict {PACKAGE_PIN W3 IOSTANDARD LVCMOS33} [get_ports {led[10]}]
set_property -dict {PACKAGE_PIN U3 IOSTANDARD LVCMOS33} [get_ports {led[11]}]
set_property -dict {PACKAGE_PIN P3 IOSTANDARD LVCMOS33} [get_ports {led[12]}]
set_property -dict {PACKAGE_PIN N3 IOSTANDARD LVCMOS33} [get_ports {led[13]}]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD LVCMOS33} [get_ports {led[14]}]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports {led[15]}]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports {JB[0]}]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports {JB[1]}]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS33} [get_ports {JB[2]}]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports {JB[3]}]
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports {JB[4]}]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports {JB[5]}]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports {JB[6]}]
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports {JB[7]}]
# Related generated clock: frame snapshots are timed, not false-pathed.
create_generated_clock -name oled_clk -source [get_ports clk] -divide_by 16 [get_pins {clk_div_reg[3]/Q}]
# Only external asynchronous inputs up to their first synchronizer are exempt.
set_false_path -from [get_ports btnU] -to [get_pins {reset_sync_reg[0]/D}]
set_false_path -from [get_ports sw0] -to [get_pins {switch_sync_reg[0]/D}]
set_false_path -from [get_ports btnC] -to [get_pins {button_filter/sync_ff_reg[0]/D}]
# ASSUMPTION: reserve 20 ns external setup budget for SPI data/control.
# The course driver changes data on falling OLED-clock edges.
set_output_delay -clock oled_clk -max 20 [get_ports {JB[0] JB[1] JB[4]}]
set_output_delay -clock oled_clk -min 0 [get_ports {JB[0] JB[1] JB[4]}]
# LEDs and OLED power/reset are asynchronous indicators/control, not sampled data.
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Basys 3 active-low seven-segment seed display; existing pins unchanged.
set_property -dict {PACKAGE_PIN W7 IOSTANDARD LVCMOS33} [get_ports {seg[0]}]
set_property -dict {PACKAGE_PIN W6 IOSTANDARD LVCMOS33} [get_ports {seg[1]}]
set_property -dict {PACKAGE_PIN U8 IOSTANDARD LVCMOS33} [get_ports {seg[2]}]
set_property -dict {PACKAGE_PIN V8 IOSTANDARD LVCMOS33} [get_ports {seg[3]}]
set_property -dict {PACKAGE_PIN U5 IOSTANDARD LVCMOS33} [get_ports {seg[4]}]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS33} [get_ports {seg[5]}]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports {seg[6]}]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33} [get_ports dp]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33} [get_ports {an[0]}]
set_property -dict {PACKAGE_PIN U4 IOSTANDARD LVCMOS33} [get_ports {an[1]}]
set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33} [get_ports {an[2]}]
set_property -dict {PACKAGE_PIN W4 IOSTANDARD LVCMOS33} [get_ports {an[3]}]


# Menu buttons (debounced; first synchronizer stage exempt like btnC).
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports btnL]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33} [get_ports btnR]
set_false_path -from [get_ports btnL] -to [get_pins {button_left/sync_ff_reg[0]/D}]
set_false_path -from [get_ports btnR] -to [get_pins {button_right/sync_ff_reg[0]/D}]
# btnD: test 'take damage' button during play (stand-in until combat exists).
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports btnD]
set_false_path -from [get_ports btnD] -to [get_pins {button_down/sync_ff_reg[0]/D}]

# USB mouse via the Basys 3 USB-HID host (PS/2 signals), used by MouseCtl.
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33 PULLUP true} [get_ports PS2Clk]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33 PULLUP true} [get_ports PS2Data]
