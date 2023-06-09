library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity video_card is
  port (
    -- Main Clock and reset
    clk : in    std_logic;
    rst : in    std_logic;

    -- SPI control interface
    spi_sck  : in    std_logic;
    spi_mosi : in    std_logic;
    spi_miso : out   std_logic;
    spi_cs   : in    std_logic;

    -- SPI RAM interface
    ram_sck  : out   std_logic;
    ram_mosi : out   std_logic;
    ram_miso : in    std_logic;
    ram_cs   : out   std_logic;

    -- VGA out
    hsync_o : out   std_logic;
    vsync_o : out   std_logic;
    red     : out   std_logic;
    green   : out   std_logic;
    blue    : out   std_logic
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

  type spi_state_t is (control, data, dma);

  signal spi_state        : spi_state_t;
  signal spi_reg          : std_logic_vector(7 downto 0);
  signal spi_reg_pointer  : integer range 0 to 7;
  signal spi_data_pointer : integer range 0 to 7500;

  type lf_state_t is (active, front, sync, back);

  type videocard_state_t is (display, reset, init, idle);

  signal videocard_state : videocard_state_t;

  constant ram_wrsr_addr  : std_logic_vector(7 downto 0) := "00000001";
  constant ram_wrsr_data  : std_logic_vector(7 downto 0) := "01000001";
  constant ram_read_instr : std_logic_vector(7 downto 0) := "00000011";

  signal init_pointer        : integer range 0 to (16 * (2 / clock_scaler));
  signal ram_data_pointer    : integer range 0 to 32;
  signal ram_data_o_register : std_logic_vector(9 downto 0);
  signal rampixelbuffer      : std_logic_vector(3 downto 0);

  signal line_state  : lf_state_t;
  signal frame_state : lf_state_t;
  signal hsync_count : integer range 0 to 1056 / clock_scaler;
  signal vsync_count : integer range 0 to 628;
  signal pixelbuffer : std_logic_vector(3 downto 0);

begin

  process_clk : process (clk, rst, spi_sck) is
  begin

    -- Handle master clock
    if rising_edge(clk) then
      -- Handle Reset
      if ((rst = '0') or videocard_state = reset) then
        spi_state           <= control;
        spi_data_pointer    <= 0;
        init_pointer        <= 0;
        ram_data_pointer    <= 0;
        ram_data_o_register <= (others => '0');

        line_state     <= active;
        frame_state    <= active;
        hsync_count    <= 0;
        vsync_count    <= 0;
        hsync_o        <= '0';
        vsync_o        <= '0';
        red            <= '0';
        green          <= '0';
        blue           <= '0';
        pixelbuffer    <= (others => '0');
        rampixelbuffer <= (others => '0');
        -- framebuffer <= (others => (others => '0'));

        videocard_state <= init;
      else

        case videocard_state is

          when init =>

            -- Initialize RAM to sequential mode

            if (init_pointer < (16 * (2 / clock_scaler))) then
              ram_cs   <= '0';
              ram_mosi <= ram_wrsr_addr(init_pointer / (2 / clock_scaler));
              if (clock_scaler = 2) then
                ram_sck <= clk;
              elsif (clock_scaler = 1) then
                ram_sck <= not ram_sck;
              end if;
              init_pointer <= init_pointer + 1;
            else
              ram_cs          <= '1';
              videocard_state <= display;

              -- Set videocard hsync & vsync count to be just before the first line,
              -- leaving time to read the first pixel data
              vsync_count <= whole_frame - 1;
              hsync_count <= whole_line - 24;
              line_state  <= back;
              frame_state <= back;
            end if;

          when display | idle =>

            if (videocard_state = display) then
              -- Handle RAM

              ram_data_o_register <= std_logic_vector(to_unsigned(vsync_count, ram_data_o_register'length));

              -- Generate RAM clock (20MHz) from main clock (40MHz)
              ram_sck <= not ram_sck;

              -- if ram_sck is 0, put the next value on MOSI bus
              if (ram_sck = '0') then

                case hsync_count is

                  -- Set read address before reading a new line
                  when whole_line - 24 to whole_line =>

                    ram_cs <= '0';

                    case ram_data_pointer is

                      when 0 to 7 =>

                        ram_mosi <= ram_read_instr(ram_data_pointer);

                      when 8 to 15 =>

                        ram_mosi <= ram_data_o_register(ram_data_pointer - 6);

                      when 16 to 23 =>

                        ram_mosi <= '0';

                      when others =>

                        ram_mosi <= '0';

                    end case;

                  -- Read data from RAM
                  when 0 to h_visible_area =>

                    ram_cs         <= '0';
                    rampixelbuffer <= rampixelbuffer(2 downto 0) & ram_miso;
                    if (hsync_count mod 4 = 0) then
                      pixelbuffer <= rampixelbuffer;
                    end if;

                  when others =>

                    ram_cs           <= '1';
                    ram_data_pointer <= 0;

                    null;

                end case;

              else
                ram_data_pointer <= ram_data_pointer + 1;
              end if;
            end if;

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
              red   <= pixelbuffer(3);
              green <= pixelbuffer(2);
              blue  <= pixelbuffer(1);
            else
              red   <= '0';
              green <= '0';
              blue  <= '0';
            end if;

          when others =>

            null;

        end case;

      end if;

    -- Handle SPI interface
    elsif rising_edge(spi_sck) then
      if (spi_cs = '1') then
        if (spi_state = dma) then
          ram_cs   <= '1';
          ram_mosi <= '0';

          videocard_state <= display;
        end if;

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

                spi_state       <= dma;
                videocard_state <= idle;

              when others =>

                null;

            end case;

          when data =>

            if (spi_data_pointer = 7500) then
              spi_state        <= control;
              spi_data_pointer <= 0;
            else
              null;
            -- framebuffer(2 to 7499) <= framebuffer(0 to 7497);
            -- framebuffer(0)         <= spi_reg(3 downto 0);
            -- framebuffer(1)         <= spi_reg(7 downto 4);
            -- spi_data_pointer       <= spi_data_pointer + 1;
            end if;

          when dma =>

            ram_cs   <= '0';
            ram_mosi <= spi_mosi;
            spi_miso <= ram_miso;
            ram_sck  <= spi_sck;

          when others =>

            null;

        end case;

      end if;
    elsif falling_edge(spi_sck) then
      if (spi_state = dma) then
        ram_cs   <= '0';
        ram_mosi <= spi_mosi;
        spi_miso <= ram_miso;
        ram_sck  <= spi_sck;
      end if;
    end if;

  end process process_clk;

end architecture rtl;
