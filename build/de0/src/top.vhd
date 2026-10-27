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

    constant USE_ASYNC_RESET    : boolean   := FALSE;
    constant USE_SYNC_RESET     : boolean   := TRUE;
    constant ASYNC_RESET_ACTIVE : std_logic := '1';
    constant SYNC_RESET_ACTIVE  : std_logic := '1';
    constant clock_frequency    : natural := 100_000_000;
    constant uart_baudrate      : natural := 250_000;

    --------------------------------------------------------
    -- Global
    --------------------------------------------------------
    signal rst        : std_logic;
    signal clk_main   : std_logic;
    signal rst_main   : std_logic;
    signal rst_n_main : std_logic;

    --------------------------------------------------------
    -- NCO generation signals
    --------------------------------------------------------
    signal nco_accu            : unsigned(31 downto 0);
    signal nco_accu_incr_const : unsigned(31 downto 0) := to_unsigned(43, 32);
    signal nco_accu_incr       : unsigned(31 downto 0) := nco_accu_incr_const;
    signal nco_clock           : std_logic;
    signal nco_clock_d1        : std_logic;
    signal nco_clock_top       : std_logic;

    --------------------------------------------------------
    -- SOC signals
    --------------------------------------------------------
    -- AXI4-Lite external initiator
    signal top_axi_awvalid : std_logic;
    signal top_axi_awready : std_logic;
    signal top_axi_awaddr  : std_logic_vector(31 downto 0);
    signal top_axi_awprot  : std_logic_vector(2 downto 0);

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
    signal top_axi_arprot  : std_logic_vector(2 downto 0);

    signal top_axi_rvalid  : std_logic;
    signal top_axi_rready  : std_logic;
    signal top_axi_rdata   : std_logic_vector(31 downto 0);
    signal top_axi_rresp   : std_logic_vector(1 downto 0);

    -- CPU control and debug
    signal soc_cpu_reset   : std_logic;
    signal soc_stall       : std_logic;
    signal soc_fault_i     : std_logic;
    signal soc_fault_o     : std_logic;

    signal soc_registers_debug   : std_logic_vector(1023 downto 0);
    signal soc_pc_debug          : std_logic_vector(31 downto 0);
    signal soc_previous_pc_debug : std_logic_vector(31 downto 0);

    --------------------------------------------------------
    -- Misc signals
    --------------------------------------------------------
    -- UART synchronization
    signal uart_rxd_d1 : std_logic;
    signal uart_rxd_d2 : std_logic;

    signal soft_reset : std_logic;

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
        if (rst_main = '1') then
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
            USE_ASYNC_RESET    => USE_ASYNC_RESET,
            USE_SYNC_RESET     => USE_SYNC_RESET,
            ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,
            SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,
            G_SYS_FREQ => clock_frequency,
            G_BAUDRATE => uart_baudrate
        )
        port map (
            -- Clock and reset
            clk         => clk_main,
            async_reset => '0',
            sync_reset  => rst_main,

            cpu_reset_i => rst_main,

            -- UART
            uart_rx     => uart_rxd_d2,
            uart_tx     => GPIO0_D_0,

            -- CPU control
            stall_i     => soc_stall,
            fault_i     => soc_fault_i,
            fault_o     => soc_fault_o,

            -- CPU debug
            registers_debug_o   => soc_registers_debug,
            pc_debug_o          => soc_pc_debug,
            previous_pc_debug_o => soc_previous_pc_debug,

            -- AXI4-Lite write address
            ext_axi_awvalid => top_axi_awvalid,
            ext_axi_awready => top_axi_awready,
            ext_axi_awaddr  => top_axi_awaddr,
            ext_axi_awprot  => top_axi_awprot,

            -- AXI4-Lite write data
            ext_axi_wvalid  => top_axi_wvalid,
            ext_axi_wready  => top_axi_wready,
            ext_axi_wdata   => top_axi_wdata,
            ext_axi_wstrb   => top_axi_wstrb,

            -- AXI4-Lite write response
            ext_axi_bvalid  => top_axi_bvalid,
            ext_axi_bready  => top_axi_bready,
            ext_axi_bresp   => top_axi_bresp,

            -- AXI4-Lite read address
            ext_axi_arvalid => top_axi_arvalid,
            ext_axi_arready => top_axi_arready,
            ext_axi_araddr  => top_axi_araddr,
            ext_axi_arprot  => top_axi_arprot,

            -- AXI4-Lite read data
            ext_axi_rvalid  => top_axi_rvalid,
            ext_axi_rready  => top_axi_rready,
            ext_axi_rdata   => top_axi_rdata,
            ext_axi_rresp   => top_axi_rresp
        );

    --------------------------------------------------------
    -- SOC control
    --------------------------------------------------------

    soc_cpu_reset <= '0';
    soc_stall     <= '0';
    soc_fault_i   <= '0';

    --------------------------------------------------------
    -- AXI4-Lite external initiator
    --------------------------------------------------------

    -- Write address
    top_axi_awvalid <= '0';
    top_axi_awaddr  <= (others => '0');
    top_axi_awprot  <= (others => '0');

    -- Write data
    top_axi_wvalid  <= '0';
    top_axi_wdata   <= (others => '0');
    top_axi_wstrb   <= (others => '0');

    -- Write response
    top_axi_bready  <= '0';

    -- Read address
    top_axi_arvalid <= '0';
    top_axi_araddr  <= (others => '0');
    top_axi_arprot  <= (others => '0');

    -- Read data
    top_axi_rready  <= '0';

    -- UART assignments
    sync_pr : process (clk_main, rst_main)
    begin
        if (rst_main='1')  then
            uart_rxd_d1 <= '1';
            uart_rxd_d2 <= '1';
        elsif rising_edge(clk_main) then
            uart_rxd_d1 <= GPIO0_D_1;
            uart_rxd_d2 <= uart_rxd_d1;
        end if;
    end process;
        
end rtl;