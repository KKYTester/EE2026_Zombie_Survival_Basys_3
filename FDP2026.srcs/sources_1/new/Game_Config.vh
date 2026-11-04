`ifndef GAME_CONFIG_VH
`define GAME_CONFIG_VH
// World: x east, y north, one unit per cell. Bit (x + 16*y) is 1 for a wall.
// The least significant 16-bit row is y=0; within each row bit 0 is x=0.
`define GAME_MAP {16'hffff, {14{16'h8001}}, 16'hffff}
// Positions use 12 fractional bits. Angles use 1024 units/turn, clockwise
// from north. This prototype starts in the room's interior, looking north.
`define GAME_SPAWN_X 32'd34816
`define GAME_SPAWN_Y 32'd34816
`define GAME_SPAWN_ANGLE 32'd128
`endif
