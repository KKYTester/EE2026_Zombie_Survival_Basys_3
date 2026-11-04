# Basys 3 SW1 and SW2, used by enemy_test_top.
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports sw1]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports sw2]
set_false_path -from [get_ports sw1] -to [get_pins {aim_meta_reg[0]/D}]
set_false_path -from [get_ports sw2] -to [get_pins {aim_meta_reg[1]/D}]
