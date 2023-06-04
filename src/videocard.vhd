library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity video_card is
  port (
    -- Master Clock and reset
    clk   : in    std_logic;
    reset : in    std_logic;

    -- SPI control interface
    spi_sck  : in    std_logic;
    spi_mosi : in    std_logic;
    spi_miso : out   std_logic;
    spi_cs   : in    std_logic;

    -- SPI RAM interface
    -- TODO

    -- VGA out
    hsync_o : out   std_logic;
    vsync_o : out   std_logic;
    red     : out   std_logic_vector(1 downto 0);
    green   : out   std_logic_vector(1 downto 0);
    blue    : out   std_logic_vector(1 downto 0)
  );
end entity video_card;

architecture rtl of video_card is

  -- Horizontal timing constants
  constant h_visible_area : integer := 800;
  constant h_front_porch  : integer := 10;
  constant h_sync_pulse   : integer := 128;
  constant h_back_porch   : integer : 88;
  constant whole_line    : integer := 1056;

  -- Vertical timing constants
  constant v_visible_area : integer := 600;
  constant v_front_porch  : integer := 1;
  constant v_sync_pulse   : integer := 4;
  constant v_back_porch   : integer : 23;
  constant whole_frame    : integer := 628;

  type lf_state is (active, front, sync, back);

  type t_framebuffer is array (0 to 99, 0 to 74) of std_logic_vector(5 downto 0);

  signal line_state  : lf_state;
  signal frame_state : lf_state;
  signal hsync_count : integer range 0 to 1056;
  signal vsync_count : integer range 0 to 628;
  signal framebuffer : t_framebuffer;

begin

  process_clk : process (clk) is
  begin

    if rising_edge(clk) then
      -- Handle Reset
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
        framebuffer <= (others => (others => (others => '0')));
      else
        -- Count lines and frames
        hsync_count <= hsync_count + 1;

        if (hsync_count = whole_line) then
          hsync_count <= 0;
          vsync_count <= vsync_count + 1;
        end if;
        if (vsync_count = whole_frame) then
          vsync_count <= 0;
        end if;

        -- Set line and frame states
        case hsync_count is

          when 0 =>

            line_state <= active;

          when h_visible_area =>

            line_state <= front;

          when h_front_porch =>

            line_state <= sync;

          when h_sync_pulse =>

            line_state <= back;

          when others =>

            null;

        end case;

        case vsync_count is

          when 0 =>

            frame_state <= active;

          when v_visible_area =>

            frame_state <= front;

          when v_front_porch =>

            frame_state <= sync;

          when v_sync_pulse =>

            frame_state <= back;

          when others =>

            null;

        end case;

        -- Generate HSYNC
        case line_state is

          when sync =>

            hsync_o <= '0';
          
          when others =>

            hsync_o <= '1';

        end case;

        -- Generate VSYNC
        case frame_state is

          when sync =>

            vsync_o <= '0';
          
          when others =>

            vsync_o <= '1';

        end case;

        -- Generate RGB from framebuffer
        if ((line_state = active) and (frame_state = active)) then
          red   <= framebuffer(hsync_count / 2, vsync_count / 8)(5 downto 4);
          green <= framebuffer(hsync_count / 2, vsync_count / 8)(3 downto 2);
          blue  <= framebuffer(hsync_count / 2, vsync_count / 8)(1 downto 0);
        else
          red   <= "00";
          green <= "00";
          blue  <= "00";
        end if;
      end if;
    end if;

  end process process_clk;

end architecture rtl;
