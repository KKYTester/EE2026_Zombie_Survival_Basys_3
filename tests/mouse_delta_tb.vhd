-- Test the controller at its synchronous byte boundary. This Ps2Interface
-- stand-in is compiled ONLY in the isolated mouse_delta_checks directory.
library ieee;
use ieee.std_logic_1164.all;
package mouse_delta_stimulus is
   signal received_byte : std_logic_vector(7 downto 0) := (others => '0');
   signal received_valid, receive_error : std_logic := '0';
   signal sent_byte : std_logic_vector(7 downto 0);
   signal sent_valid : std_logic;
end package;

library ieee;
use ieee.std_logic_1164.all;
use work.mouse_delta_stimulus.all;
entity Ps2Interface is
   port(ps2_clk, ps2_data : inout std_logic;
        clk, rst : in std_logic;
        tx_data : in std_logic_vector(7 downto 0);
        write_data : in std_logic;
        rx_data : out std_logic_vector(7 downto 0);
        read_data, busy, err : out std_logic);
end entity;
architecture byte_stub of Ps2Interface is
begin
   ps2_clk <= 'Z'; ps2_data <= 'Z';
   rx_data <= received_byte; read_data <= received_valid;
   err <= receive_error; busy <= '0';
   sent_byte <= tx_data; sent_valid <= write_data;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mouse_delta_stimulus.all;
entity mouse_delta_tb is end entity;
architecture test of mouse_delta_tb is
   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal ps2_clk, ps2_data : std_logic := 'H';
   signal x_delta, y_delta : signed(8 downto 0);
   signal new_event, left, middle, right : std_logic;
begin
   clk <= not clk after 5 ns;
   dut: entity work.Mouse_Control_Delta
      port map(clk => clk, rst => rst, x_delta => x_delta, y_delta => y_delta,
               left => left, middle => middle, right => right,
               new_event => new_event, ps2_clk => ps2_clk, ps2_data => ps2_data);

   stimulus: process
      procedure send_byte(b : std_logic_vector(7 downto 0)) is
      begin
         wait until falling_edge(clk);
         received_byte <= b; received_valid <= '1';
         wait until falling_edge(clk);
         received_valid <= '0';
         wait for 1 ns;
      end procedure;

      procedure initialize(wheel : boolean) is
         type commands_t is array(natural range <>) of std_logic_vector(7 downto 0);
         constant commands : commands_t(0 to 12) :=
            (x"FF", x"F3", x"C8", x"F3", x"64", x"F3", x"50",
             x"F2", x"E8", x"03", x"F3", x"28", x"F4");
      begin
         for i in commands'range loop
            for cycle in 0 to 20 loop
               wait until rising_edge(clk); wait for 1 ns;
               exit when sent_valid = '1';
               assert cycle < 20 report "Missing initialization command" severity failure;
            end loop;
            assert sent_byte = commands(i)
               report "Wrong initialization command " & integer'image(i) &
                      ": expected " & to_hstring(commands(i)) & ", got " & to_hstring(sent_byte)
               severity failure;
            send_byte(x"FA");
            if i = 0 then send_byte(x"AA"); send_byte(x"00"); end if;
            if i = 7 then
               if wheel then send_byte(x"03"); else send_byte(x"00"); end if;
            end if;
         end loop;
         assert new_event = '0' and x_delta = 0 report "Initialization emitted movement" severity failure;
      end procedure;

      procedure packet(header, xbyte, ybyte : std_logic_vector(7 downto 0);
                       expected : integer; wheel : boolean) is
         variable previous, previous_y : signed(8 downto 0);
         variable expected_y : integer;
      begin
         previous := x_delta; previous_y := y_delta;
         expected_y := to_integer(signed(header(5) & ybyte));
         if header(7) = '1' then
            if header(5) = '1' then expected_y := -256; else expected_y := 255; end if;
         end if;
         send_byte(header); send_byte(xbyte);
         assert new_event = '0' and x_delta = previous and y_delta = previous_y
            report "Published before packet completion" severity failure;
         send_byte(ybyte);
         if wheel then
            assert new_event = '0' and x_delta = previous and y_delta = previous_y
               report "Published before wheel byte" severity failure;
            send_byte(x"F9");
         end if;
         wait until rising_edge(clk); wait for 1 ns;
         assert new_event = '1' and to_integer(x_delta) = expected
            report "Wrong signed delta: expected " & integer'image(expected) &
                   ", got " & integer'image(to_integer(x_delta)) severity failure;
         assert to_integer(y_delta) = expected_y report "Wrong signed Y delta" severity failure;
         assert left = header(0) and middle = header(2) and right = header(1)
            report "Button outputs changed" severity failure;
         wait until rising_edge(clk); wait for 1 ns;
         assert new_event = '0' and to_integer(x_delta) = expected
            report "Event is not one cycle or delta was not held" severity failure;
      end procedure;

      procedure reset_controller is
      begin
         rst <= '1'; received_valid <= '0'; receive_error <= '0';
         wait until falling_edge(clk); wait for 1 ns;
         assert x_delta = 0 and y_delta = 0 and new_event = '0' and
                left = '0' and middle = '0' and right = '0'
            report "Reset failed" severity failure;
         rst <= '0';
      end procedure;

      variable header : std_logic_vector(7 downto 0);
      variable movement : signed(8 downto 0);
   begin
      for mode in 0 to 1 loop
         reset_controller;
         initialize(mode = 1);
         -- Exhaust all 512 encodings, including +/-128, +255 and -256.
         -- Vary Y data/sign/overflow and button states independently of X.
         for delta in -256 to 255 loop
            movement := to_signed(delta, 9);
            header := x"A8";
            header(4) := movement(8);
            header(2 downto 0) := std_logic_vector(to_unsigned((delta + 256) mod 8, 3));
            packet(header, std_logic_vector(movement(7 downto 0)),
                   std_logic_vector(to_unsigned((delta + 256) mod 256, 8)), delta, mode = 1);
         end loop;
         for delta in -256 to 255 loop
            movement := to_signed(delta, 9);
            header := x"08"; header(5) := movement(8);
            packet(header, x"00", std_logic_vector(movement(7 downto 0)), 0, mode = 1);
         end loop;
         packet(x"88", x"00", x"00", 0, mode = 1);
         packet(x"A8", x"00", x"FF", 0, mode = 1);
         packet(x"48", x"00", x"FF", 255, mode = 1);
         packet(x"58", x"FF", x"00", -256, mode = 1);
         -- Repeated same-direction packets must remain deltas without saturation.
         for i in 1 to 16 loop packet(x"08", x"64", x"00", 100, mode = 1); end loop;
         packet(x"08", x"00", x"FF", 0, mode = 1);
         -- Error after X but before Y must not publish a partial packet.
         send_byte(x"08"); send_byte(x"7F");
         receive_error <= '1';
         wait until rising_edge(clk); wait for 1 ns;
         receive_error <= '0';
         wait until rising_edge(clk); wait for 1 ns;
         assert new_event = '0' and x_delta = 0 report "Partial packet escaped on error" severity failure;
         -- Reset while a partial packet is pending, then verify framing recovers.
         reset_controller; initialize(mode = 1);
         send_byte(x"18"); send_byte(x"FE");
         reset_controller; initialize(mode = 1);
         packet(x"08", x"01", x"00", 1, mode = 1);
      end loop;
      report "PASS: all signed X/Y deltas, overflow, buttons, ignored wheel, event timing, repeated movement, partial-packet error/reset";
      std.env.finish;
      wait;
   end process;

   watchdog: process
   begin
      wait for 1 ms;
      assert false report "Mouse delta test timed out" severity failure;
   end process;
end architecture;
