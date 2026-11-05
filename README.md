# EE2026_Zombie_Survival_Basys_3

## Set up the Vivado project

The Vivado project is generated locally using `create_project.tcl`. The repository
contains the HDL sources and constraints; generated project and build files are
ignored by Git.

### Prerequisites

- Install Vivado with support for Artix-7 devices. The current local setup uses
  Vivado 2025.2.
- Clone or download this repository, keeping `create_project.tcl` and
  `FDP2026.srcs/` together in the repository root.

### Create the project in Vivado

1. Open Vivado with no project open.
2. Open the **Tcl Console** at the bottom of the window. If it is hidden, select
   **Window > Tcl Console**.
3. Run the following command, replacing the example path with the full path to
   your copy of `create_project.tcl`:

   ```tcl
   source {C:/path/to/EE2026_Zombie_Survival_Basys_3/create_project.tcl}
   ```

   On Windows, use forward slashes (`/`) and keep the braces so paths containing
   spaces work. The script resolves all project files relative to itself, so you
   do not need to change Vivado's working directory.

4. Wait for the script to finish. It creates and opens the `FDP2026` project at
   `build/FDP2026/FDP2026.xpr` with:
   - FPGA part: `xc7a35tcpg236-1` (Basys 3).
   - Top module: `My_Top_Module`.
   - Sources: all `.v`, `.sv`, `.vhd`, `.vhdl`, `.vh`, and `.svh` files under
     `FDP2026.srcs/sources_1/new/`, including subfolders.
   - Constraints: `Basys3_Master.xdc`.

### Reopen or regenerate the project

For later sessions, open `build/FDP2026/FDP2026.xpr` directly in Vivado; you do
not need to run the script again. The script sets up the project only; run
synthesis, implementation, and bitstream generation from Vivado when needed.

If you need to regenerate the project, close it in Vivado first, preserve any
needed build results, then delete only the generated `build/FDP2026/` folder and
run the script again. The script does not overwrite an existing project.

Edit and commit the HDL and constraint files under `FDP2026.srcs/`. Put new HDL
source files under `FDP2026.srcs/sources_1/new/` (or its subfolders). The script
discovers them each time it creates a project, so you do not need to edit the
script when adding or removing HDL files.

An already-open project does not automatically refresh when files appear on disk.
Use Vivado's **Add Sources** to add new files to your existing project, or
regenerate the project using the steps above. Keep simulation-only testbenches
outside this design-source folder.

## Test UART between two Basys 3 boards

The repository includes a standalone test design for the UART byte link and
packet layer. It uses 115200 baud, 8 data bits, no parity, and 1 stop bit. Build
it separately from the game project so the test pin constraints do not conflict
with the game constraints.

1. Close any open Vivado project. In Vivado's Tcl Console, run
   `source {C:/path/to/EE2026_Zombie_Survival_Basys_3/create_uart_test.tcl}`.
   Replace the example path with the location of your checkout. The script
   creates `build/UART_Board_Test/UART_Board_Test.xpr` and sets
   `uart_test_top` as the top module.
2. Generate the bitstream, then program both Basys 3 boards with that same
   bitstream.
3. Connect the boards with three jumper wires: board A JC1 (UART TX) to board B
   JC2 (UART RX), board B JC1 (UART TX) to board A JC2 (UART RX), and GND to
   GND. JC1 is FPGA pin K17 and JC2 is FPGA pin M18 in `constraints/uart_test.xdc`.
   Do not connect the boards' 3.3 V or 5 V pins. Both boards must be powered
   separately. The UART I/O standard is LVCMOS33.
4. Press btnU on both boards to reset. Keep switches [15:14] low for raw-byte
   mode. Set switches [7:0] to a value on board A and press btnC; board B's
   LEDs [7:0] should show that byte and its four-digit display should count
   received bytes. Swap the sender to check the reverse direction.
5. For packet mode, set switch 15 high on both boards. Press btnC on one board;
   the receiving board should increment the good-packet count and show the
   first payload byte on LEDs [7:0]. To check checksum rejection, set switch 14
   high only on the sending board and send again. The receiving board should
   increment its bad-packet count and leave the payload LEDs unchanged.

The test packet is `A5, type, length, payload..., checksum`; the checksum is
the 8-bit sum of type, length, and payload. Packet mode reports good and bad
packet counts on the seven-segment display; LEDs 14 and 15 indicate transmit
busy and packet mode. LED 8 latches a UART framing error. A one-way test only
needs TX, RX, and ground; the crossed TX/RX wires let both boards send and
receive.

### UART simulations

The self-contained Verilog testbenches are under `sim/uart/`. They cover UART
byte transmission, packet framing/checksums/timeouts, and the board test top in
loopback. They are simulation checks; the physical two-board check still
requires programming both boards and connecting the jumpers as above.

The game-facing packet interface is described in
[`docs/multiplayer-link.md`](docs/multiplayer-link.md). The two-board build uses
the project's shared game core and ray-cast map renderer, with the multiplayer
link synchronizing both players and the host's zombie simulation.

## Two-player game

1. In Vivado, close the UART test project, then run
   `source {D:/ee2026_project/create_zombie_multiplayer.tcl}` in the Tcl Console.
2. Run `source {D:/ee2026_project/scripts/build_zombie_multiplayer.tcl}` to build
   the project top `My_Top_Module`. The bitstream is
   `build/Zombie_Multiplayer_Clean/Zombie_Multiplayer_Clean.runs/impl_1/My_Top_Module.bit`.
   Program both Basys 3 boards with that same bitstream.
3. Set switch 3 **high on the host board** and **low on the client board**.
   Keep the already-tested crossed JC1/JC2 wires and common ground connected.
4. Press btnU on both boards. From the title screen, press btnD once on each
   board to select **2 PLAYERS**, then press btnC on both boards to start. On
   the host, SW[7:4] moves Player 1; on the client those switches move Player 2.
   SW[2:1] aims, btnC fires, and btnL reloads during play. The ray-cast view
   follows each board's local player; SW0 toggles the map view.
5. The host owns the zombie simulation and sends player state and zombie
   positions to the client. Both boards show the game HUD and map, and LED 15
   indicates the UART link is up. Movement is grid-based and stops at walls or
   the other player.
   LED 15 should light on both boards after the handshake. Zombies target the
   nearer active player and either player's shots can damage them.

Switch 3 selects host/client role. SW4, SW5, SW6, and SW7 mean north, south,
west, and east. SW2:SW1 aim right, down, left, or up. btnR removes a zombie for
debugging and btnD simulates a hit on the local player. The two-player game uses
`constraints/map_preview.xdc`, `constraints/enemy_aim.xdc`, and
`constraints/multiplayer_zombie.xdc`; do not add the UART test constraints to
this project.

One Basys 3 can verify the game UI, map, ray-cast view, and local controls. A
physical test of board-to-board player synchronization needs two boards wired
TX-to-RX in both directions plus common ground.
