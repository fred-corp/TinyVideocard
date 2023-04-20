library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity video_card is
  port (
    clk   : in    std_logic;
    reset : in    std_logic;
    -- data_sda : in    std_logic;
    -- data_scl : in    std_logic;

    hsync_o : out   std_logic;
    vsync_o : out   std_logic;
    red     : out   std_logic_vector(1 downto 0);
    green   : out   std_logic_vector(1 downto 0);
    blue    : out   std_logic_vector(1 downto 0)
  );
end entity video_card;

architecture rtl of video_card is

  type lf_state is (active, front, sync, back);

  signal line_state  : lf_state;
  signal frame_state : lf_state;
  signal hsync_count : integer range 0 to 264;
  signal vsync_count : integer range 0 to 628;

begin

  process (clk) is
  begin

    if rising_edge(clk) then
      if (reset = '0') then
        line_state  <= active;
        frame_state <= active;
        hsync_count <= 0;
        vsync_count <= 0;
        hsync_o     <= '0';
        vsync_o     <= '0';
        red         <= "00";
        green       <= "00";
        blue        <= "00";
      else
        hsync_count <= hsync_count + 1;

        if (hsync_count = 264) then
          hsync_count <= 0;
          vsync_count <= vsync_count + 1;
        end if;
        if (vsync_count = 628) then
          vsync_count <= 0;
        end if;

        case hsync_count is

          when 0 =>

            line_state <= active;

          when 200 =>

            line_state <= front;

          when 210 =>

            line_state <= sync;

          when 242 =>

            line_state <= back;

          when others =>

            null;

        end case;

        case vsync_count is

          when 0 =>

            frame_state <= active;

          when 600 =>

            frame_state <= front;

          when 601 =>

            frame_state <= sync;

          when 605 =>

            frame_state <= back;

          when others =>

            null;

        end case;

        case line_state is

          when active =>

            hsync_o <= '1';

          when front =>

            hsync_o <= '1';

          when sync =>

            hsync_o <= '0';

          when back =>

            hsync_o <= '1';

        end case;

        case frame_state is

          when active =>

            vsync_o <= '1';

          when front =>

            vsync_o <= '1';

          when sync =>

            vsync_o <= '0';

          when back =>

            vsync_o <= '1';

        end case;

      end if;
    end if;

  end process;

end architecture rtl;
