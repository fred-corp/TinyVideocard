library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity video_card is
  port (
    -- Master Clock and reset
    clk : in    std_logic;
    rst : in    std_logic;

    -- SPI control interface
    spi_sck  : in    std_logic;
    spi_mosi : in    std_logic;
    -- spi_miso : out   std_logic;
    spi_cs : in    std_logic;

    -- SPI RAM interface
    -- ram_sck  : out   std_logic;
    -- ram_mosi : out   std_logic;
    -- ram_miso : in    std_logic;
    -- ram_cs   : out   std_logic;

    -- VGA out
    hsync_o : out   std_logic;
    vsync_o : out   std_logic;
    red     : out   std_logic_vector(1 downto 0);
    green   : out   std_logic_vector(1 downto 0);
    blue    : out   std_logic_vector(1 downto 0)
  );
end entity video_card;

architecture rtl of video_card is

  -- Clock scaler (1 : 40MHz, 2: 20MHz, 4: 10MHz)
  constant clock_scaler : integer := 1;

  -- Horizontal timing constants
  constant h_visible_area : integer := 800 / clock_scaler;
  constant h_front_porch  : integer := 40 / clock_scaler;
  constant h_sync_pulse   : integer := 128 / clock_scaler;
  constant h_back_porch   : integer := 88 / clock_scaler;
  constant whole_line     : integer := 1056 / clock_scaler;

  -- Vertical timing constants
  constant v_visible_area : integer := 600;
  constant v_front_porch  : integer := 1;
  constant v_sync_pulse   : integer := 4;
  constant v_back_porch   : integer := 23;
  constant whole_frame    : integer := 628;

  type spi_state_t is (control, data);

  signal spi_state        : spi_state_t;
  signal spi_reg          : std_logic_vector(7 downto 0);
  signal spi_reg_pointer  : integer range 0 to 7;
  signal spi_data_pointer : integer range 0 to 7500;

  type lf_state_t is (active, front, sync, back);

  type framebuffer_t is array (0 to 7500) of std_logic_vector(3 downto 0);

  type videocard_state_t is (display, reset, write, idle);

  signal videocard_state : videocard_state_t;

  signal line_state  : lf_state_t;
  signal frame_state : lf_state_t;
  signal hsync_count : integer range 0 to 1056;
  signal vsync_count : integer range 0 to 628;
  signal framebuffer : framebuffer_t;

begin

  process_clk : process (clk, rst, spi_sck) is
  begin

    -- Handle master clock
    if rising_edge(clk) then
      -- Handle Reset
      if (rst = '0') then
        spi_state        <= control;
        spi_data_pointer <= 0;

        line_state  <= active;
        frame_state <= active;
        hsync_count <= 0;
        vsync_count <= 0;
        hsync_o     <= '0';
        vsync_o     <= '0';
        red         <= "00";
        green       <= "00";
        blue        <= "00";
        framebuffer <= (others => (others => '0'));
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
          red(0)   <= framebuffer((hsync_count / (8 / clock_scaler)) + ((vsync_count / 8) * 100))(3);
          green(0) <= framebuffer((hsync_count / (8 / clock_scaler)) + ((vsync_count / 8) * 100))(2);
          blue(0)  <= framebuffer((hsync_count / (8 / clock_scaler)) + ((vsync_count / 8) * 100))(1);
        else
          red   <= "00";
          green <= "00";
          blue  <= "00";
        end if;
      end if;

    -- Handle SPI interface
    elsif rising_edge(spi_sck) then
      if (spi_cs = '1') then
        spi_reg_pointer  <= 0;
        spi_data_pointer <= 0;
        spi_state        <= control;
      else
        spi_reg         <= spi_reg(6 downto 0) & spi_mosi;
        spi_reg_pointer <= spi_reg_pointer + 1;
      end if;

      if (spi_reg_pointer = 7) then

        case spi_state is

          when control =>

            case spi_reg is

              when "00000001" =>

                spi_state <= data;

              when others =>

                null;

            end case;

          when data =>

            if (spi_data_pointer = 7500) then
              spi_state        <= control;
              spi_data_pointer <= 0;
            else
              framebuffer(2 to 7499) <= framebuffer(0 to 7497);
              framebuffer(0)         <= spi_reg(3 downto 0);
              framebuffer(1)         <= spi_reg(7 downto 4);
              spi_data_pointer       <= spi_data_pointer + 1;
            end if;

          when others =>

            null;

        end case;

      end if;
    end if;

  end process process_clk;

end architecture rtl;
