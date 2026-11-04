`ifndef GAME_CONFIG_VH
`define GAME_CONFIG_VH
// World: x east, y north, one unit per cell. Bit (x + 16*y) is 1 for a wall.
// The least significant 16-bit row is y=0; within each row bit 0 is x=0.
// Rows are listed north to south (y=15 down to y=0). The north block occupies
// x=6..10, y=10..14; 16'h87c1 encodes "#     #####    #" from west to east.
`define GAME_MAP {16'hffff, {5{16'h87c1}}, {9{16'h8001}}, 16'hffff}
// Positions use 12 fractional bits. Angles use 1024 units/turn, clockwise
// from north. This prototype starts in the room's interior, looking northeast.
`define GAME_SPAWN_X 32'd34816
`define GAME_SPAWN_Y 32'd34816
`define GAME_SPAWN_ANGLE 32'd128
// Controller: 10 ms debounce at 100 MHz, 1/8 cell movement per 24 Hz tick,
// and a square body with 1/8-cell half-width. Keep steps below one cell.
`define GAME_BUTTON_DEBOUNCE_CYCLES 1_000_000
`define GAME_MOVE_SHIFT 2
`define GAME_PLAYER_RADIUS 18'sd512
`endif
