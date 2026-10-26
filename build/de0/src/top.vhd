--
--          GPIO 0 CONNECTOR
--          
--  1       xxx    UART TX
--  2       xxx    UART RX
--  3       xxx    xxx
--  4       xxx    xxx
--  5       xxx    xxx
--  6       xxx    GND
--  7       xxx    xxx
--          ...    ...
-- 20       xxx    xxx
--
--

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
entity top is
    generic (
        simu   : integer := 0;
        target : integer := 0 -- 0: altera, 1: xilinx
    );
    port (
        CLOCK_50  : in std_logic;
        SW        : in std_logic_vector(9 downto 0);
        LEDG      : out std_logic_vector(9 downto 0);
        GPIO0_D_1 : in std_logic; --uart rx
        GPIO0_D_0 : out std_logic --uart tx           
    );
end entity top;

architecture rtl of top is
    --------------------------------------------------------
    --Integration design constants
    --------------------------------------------------------
    constant clock_frequency : natural := 100_000_000;
    constant uart_baudrate   : natural := 250_000;
    constant USE_ASYNC_RESET    : boolean   := FALSE;
    constant USE_SYNC_RESET     : boolean   := FALSE;
    --------------------------------------------------------
    --Global
    --------------------------------------------------------
    signal rst        : std_logic;
    signal clk_main   : std_logic;
    signal rst_main   : std_logic;
    signal rst_n_main : std_logic;
    --------------------------------------------------------
    --NCO generation signals
    --------------------------------------------------------
    signal nco_accu            : unsigned(31 downto 0) := (others => '0');
    signal nco_accu_incr_const : unsigned(31 downto 0) := to_unsigned(43, 32);
    signal nco_accu_incr       : unsigned(31 downto 0) := nco_accu_incr_const;
    signal nco_clock           : std_logic;
    signal nco_clock_d1        : std_logic;
    signal nco_clock_top       : std_logic;

    --------------------------------------------------------
    --Integration signals
    --------------------------------------------------------
    signal top_axi_awvalid : std_logic;
    signal top_axi_awready : std_logic;
    signal top_axi_awaddr  : std_logic_vector(31 downto 0);
    signal top_axi_wvalid  : std_logic;
    signal top_axi_wready  : std_logic;
    signal top_axi_wdata   : std_logic_vector(31 downto 0);
    signal top_axi_wstrb   : std_logic_vector(3 downto 0);
    signal top_axi_bvalid  : std_logic;
    signal top_axi_bready  : std_logic;
    signal top_axi_bresp   : std_logic_vector(1 downto 0);
    signal top_axi_arvalid : std_logic;
    signal top_axi_arready : std_logic;
    signal top_axi_araddr  : std_logic_vector(31 downto 0);
    signal top_axi_rvalid  : std_logic;
    signal top_axi_rready  : std_logic;
    signal top_axi_rdata   : std_logic_vector(31 downto 0);
    signal top_axi_rresp   : std_logic_vector(1 downto 0);
    signal uart_rxd_d1     : std_logic;
    signal uart_rxd_d2     : std_logic;
    signal soft_reset      : std_logic;

begin
    rst <= SW(0);

    --------------------------------------------------------
    -- Clock and reset generation
    --------------------------------------------------------
    clk_rst_gen_inst : entity work.clk_rst_gen
        generic map(
            simu   => simu,
            target => target
        )
        port map
        (
            clk   => CLOCK_50,
            rst   => rst,
            clk0  => clk_main,
            rst0  => rst_main,
            rstn0 => rst_n_main
    
    );

    --------------------------------------------------------
    --NCO
    --------------------------------------------------------
nco_pro : process (clk_main, rst_main)
        begin
        if (rst_main = '1' and USE_ASYNC_RESET = TRUE) then
            nco_accu      <= (others => '0');
            nco_clock     <= '0';
            nco_clock_d1  <= '0';
            nco_clock_top <= '0';
        nco_accu_incr <= nco_accu_incr_const;
            elsif rising_edge(clk_main) then
            nco_accu     <= nco_accu + nco_accu_incr;
            nco_clock    <= nco_accu(31);
            nco_clock_d1 <= nco_clock;
            if nco_clock = '1' and nco_clock_d1 = '0' then
            nco_clock_top <= not(nco_clock_top);
            end if;
        end if;
        end process;

    --------------------------------------------------------
    --Outputs
    --------------------------------------------------------   
    LEDG <= "000000000" & nco_clock_top;

    --------------------------------------------------------
    -- SOC
    --------------------------------------------------------

    soc_inst : entity work.soc
        generic map (
            G_SYS_FREQ  => clock_frequency,
            G_BAUDRATE          => uart_baudrate
            --start_address     => x"00000000",
            --enable_multiplier => false,
            --enable_divider    => false
        )
        port map (
            clock_i             => clk_main,
            reset_n_i           => rst_n_main,

            uart_rx_i           => uart_rxd_d2,
            uart_tx_o           => GPIO0_D_0,

            gpio_i              => (others => '0'),
            gpio_o              => soc_gpio_o,

            stall_i             => '0',
            fault_i             => '0',
            fault_o             => soc_fault,

            registers_debug_o   => open,
            pc_debug_o          => open,
            previous_pc_debug_o => open,

            cpu_sync_reset_i    => '0',

            tb_axi_awaddr_i     => (others => '0'),
            tb_axi_awprot_i     => (others => '0'),
            tb_axi_awvalid_i    => '0',
            tb_axi_awready_o    => open,

            tb_axi_wdata_i      => (others => '0'),
            tb_axi_wstrb_i      => (others => '0'),
            tb_axi_wvalid_i     => '0',
            tb_axi_wready_o     => open,

            tb_axi_bresp_o      => open,
            tb_axi_bvalid_o     => open,
            tb_axi_bready_i     => '0',

            tb_axi_araddr_i     => (others => '0'),
            tb_axi_arprot_i     => (others => '0'),
            tb_axi_arvalid_i    => '0',
            tb_axi_arready_o    => open,

            tb_axi_rdata_o      => open,
            tb_axi_rresp_o      => open,
            tb_axi_rvalid_o     => open,
            tb_axi_rready_i     => '0'
        );

    -- UART assignments
sync_pr : process (clk_main, rst_main)
        begin
        if (rst_main = '1' and USE_ASYNC_RESET = TRUE) then
            uart_rxd_d1 <= '1';
        uart_rxd_d2 <= '1';
            elsif rising_edge(clk_main) then
            uart_rxd_d1 <= GPIO0_D_1;
        uart_rxd_d2 <= uart_rxd_d1;
        end if;
        end process;
        
end rtl;