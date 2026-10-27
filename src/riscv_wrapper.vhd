library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscv_wrapper is
    generic (
        USE_ASYNC_RESET    : boolean   := TRUE;
        USE_SYNC_RESET     : boolean   := TRUE;
        ASYNC_RESET_ACTIVE : std_logic := '1';
        SYNC_RESET_ACTIVE  : std_logic := '1';
        start_address      : std_logic_vector(31 downto 0) := x"00000000";
        enable_multiplier  : boolean := true;
        enable_divider     : boolean := true
    );
    port (
        -- Clock and reset
        clock_i       : in std_logic;
        async_reset : in std_logic;
        sync_reset  : in std_logic;

        -- CPU control
        stall_i : in std_logic;
        fault_i : in std_logic;
        fault_o : out std_logic;

        -- Debug interface
        registers_debug_o : out std_logic_vector(1023 downto 0);
        pc_debug_o        : out std_logic_vector(31 downto 0);
        previous_pc_debug_o : out std_logic_vector(31 downto 0);

        -- AXI4-Lite write address channel
        m_axi_awaddr_o  : out std_logic_vector(31 downto 0);
        m_axi_awprot_o  : out std_logic_vector(2 downto 0);
        m_axi_awvalid_o : out std_logic;
        m_axi_awready_i : in std_logic;

        -- AXI4-Lite write data channel
        m_axi_wdata_o  : out std_logic_vector(31 downto 0);
        m_axi_wstrb_o  : out std_logic_vector(3 downto 0);
        m_axi_wvalid_o : out std_logic;
        m_axi_wready_i : in std_logic;

        -- AXI4-Lite write response channel
        m_axi_bresp_i  : in std_logic_vector(1 downto 0);
        m_axi_bvalid_i : in std_logic;
        m_axi_bready_o : out std_logic;

        -- AXI4-Lite read address channel
        m_axi_araddr_o  : out std_logic_vector(31 downto 0);
        m_axi_arprot_o  : out std_logic_vector(2 downto 0);
        m_axi_arvalid_o : out std_logic;
        m_axi_arready_i : in std_logic;

        -- AXI4-Lite read data channel
        m_axi_rdata_i  : in std_logic_vector(31 downto 0);
        m_axi_rresp_i  : in std_logic_vector(1 downto 0);
        m_axi_rvalid_i : in std_logic;
        m_axi_rready_o : out std_logic
    );
end entity;


architecture rtl of riscv_wrapper is

    -- Internal reset
    signal reset_n : std_logic;

    -- CPU trap indication
    signal cpu_trap : std_logic;

    -- Reset synchronization
    signal async_reset_request : std_logic;
    signal sync_reset_request  : std_logic;
    signal reset_sync_1        : std_logic;
    signal reset_sync_2        : std_logic;

    -- picorv32_axi signal

    component picorv32_axi is
        generic (
            ENABLE_COUNTERS       : integer := 1;
            ENABLE_COUNTERS64     : integer := 1;
            ENABLE_REGS_16_31     : integer := 1;
            ENABLE_REGS_DUALPORT  : integer := 1;
            TWO_STAGE_SHIFT       : integer := 1;
            BARREL_SHIFTER        : integer := 0;
            TWO_CYCLE_COMPARE     : integer := 0;
            TWO_CYCLE_ALU         : integer := 0;
            COMPRESSED_ISA        : integer := 0;
            CATCH_MISALIGN        : integer := 1;
            CATCH_ILLINSN         : integer := 1;
            ENABLE_PCPI           : integer := 0;
            ENABLE_MUL            : integer := 0;
            ENABLE_FAST_MUL       : integer := 0;
            ENABLE_DIV            : integer := 0;
            ENABLE_IRQ            : integer := 0;
            ENABLE_IRQ_QREGS      : integer := 1;
            ENABLE_IRQ_TIMER      : integer := 1;
            ENABLE_TRACE          : integer := 0;
            REGS_INIT_ZERO        : integer := 0;

            MASKED_IRQ            : std_logic_vector(31 downto 0)
                                := x"00000000";
            LATCHED_IRQ           : std_logic_vector(31 downto 0)
                                := x"FFFFFFFF";
            PROGADDR_RESET        : std_logic_vector(31 downto 0)
                                := x"00000000";
            PROGADDR_IRQ          : std_logic_vector(31 downto 0)
                                := x"00000010";
            STACKADDR             : std_logic_vector(31 downto 0)
                                := x"FFFFFFFF"
        );
        port (
            clk                   : in  std_logic;
            resetn                : in  std_logic;
            trap                  : out std_logic;

            -- AXI4-Lite master write-address channel
            mem_axi_awvalid       : out std_logic;
            mem_axi_awready       : in  std_logic;
            mem_axi_awaddr        : out std_logic_vector(31 downto 0);
            mem_axi_awprot        : out std_logic_vector(2 downto 0);

            -- AXI4-Lite master write-data channel
            mem_axi_wvalid        : out std_logic;
            mem_axi_wready        : in  std_logic;
            mem_axi_wdata         : out std_logic_vector(31 downto 0);
            mem_axi_wstrb         : out std_logic_vector(3 downto 0);

            -- AXI4-Lite master write-response channel
            mem_axi_bvalid        : in  std_logic;
            mem_axi_bready        : out std_logic;

            -- AXI4-Lite master read-address channel
            mem_axi_arvalid       : out std_logic;
            mem_axi_arready       : in  std_logic;
            mem_axi_araddr        : out std_logic_vector(31 downto 0);
            mem_axi_arprot        : out std_logic_vector(2 downto 0);

            -- AXI4-Lite master read-data channel
            mem_axi_rvalid        : in  std_logic;
            mem_axi_rready        : out std_logic;
            mem_axi_rdata         : in  std_logic_vector(31 downto 0);

            -- Pico Co-Processor Interface
            pcpi_valid            : out std_logic;
            pcpi_insn             : out std_logic_vector(31 downto 0);
            pcpi_rs1              : out std_logic_vector(31 downto 0);
            pcpi_rs2              : out std_logic_vector(31 downto 0);
            pcpi_wr               : in  std_logic;
            pcpi_rd               : in  std_logic_vector(31 downto 0);
            pcpi_wait             : in  std_logic;
            pcpi_ready            : in  std_logic;

            -- IRQ interface
            irq                   : in  std_logic_vector(31 downto 0);
            eoi                   : out std_logic_vector(31 downto 0);

            -- Trace interface
            trace_valid           : out std_logic;
            trace_data            : out std_logic_vector(35 downto 0)
        );
    end component;

begin

    --------------------------------------------------------------------
    -- Reset controller
    --------------------------------------------------------------------

    -- Decode reset polarity and enable
    async_reset_request <= '1' when
        USE_ASYNC_RESET and async_reset = ASYNC_RESET_ACTIVE
        else '0';

    sync_reset_request <= '1' when
        USE_SYNC_RESET and sync_reset = SYNC_RESET_ACTIVE
        else '0';

    -- Asynchronous assertion, synchronous release
    process (clock_i, async_reset) is
    begin
        if ((async_reset = ASYNC_RESET_ACTIVE) and (USE_ASYNC_RESET = true)) then
            reset_sync_1 <= '0';
            reset_sync_2 <= '0';
        elsif rising_edge(clock_i) then
            if ((sync_reset = SYNC_RESET_ACTIVE) and (USE_SYNC_RESET = true)) then
                reset_sync_1 <= '0';
                reset_sync_2 <= '0';
            else
                reset_sync_1 <= '1';
                reset_sync_2 <= reset_sync_1;
            end if;
        end if;
    end process;

    -- Generate active-low CPU reset
    reset_n <= reset_sync_2 and not sync_reset_request when USE_ASYNC_RESET or USE_SYNC_RESET else '1';


    --------------------------------------------------------------------
    -- CPU fault management
    --------------------------------------------------------------------

    -- Report CPU trap condition
    fault_o <= cpu_trap;

    -- TODO: Implement external fault handling (fault_i)
    -- TODO: Implement CPU stall control (stall_i)


    --------------------------------------------------------------------
    -- Debug interface
    --------------------------------------------------------------------

    -- TODO: Expose CPU internal registers and program counter
    registers_debug_o   <= (others => '0');
    pc_debug_o          <= (others => '0');
    previous_pc_debug_o <= (others => '0');


    --------------------------------------------------------------------
    -- PicoRV32 AXI processor
    --------------------------------------------------------------------

    picorv32_axi_inst : picorv32_axi
        generic map (
            ENABLE_COUNTERS      => 1,
            ENABLE_COUNTERS64    => 1,
            ENABLE_REGS_16_31    => 1,
            ENABLE_REGS_DUALPORT => 1,
            TWO_STAGE_SHIFT      => 1,
            BARREL_SHIFTER       => 0,
            TWO_CYCLE_COMPARE    => 0,
            TWO_CYCLE_ALU        => 0,
            COMPRESSED_ISA       => 0,
            CATCH_MISALIGN       => 1,
            CATCH_ILLINSN        => 1,
            ENABLE_PCPI          => 0,

            -- Optional arithmetic extensions
            ENABLE_MUL           => boolean'pos(enable_multiplier),
            ENABLE_FAST_MUL      => 0,
            ENABLE_DIV           => boolean'pos(enable_divider),

            -- Interrupt configuration
            ENABLE_IRQ           => 0,
            ENABLE_IRQ_QREGS     => 1,
            ENABLE_IRQ_TIMER     => 1,

            -- Trace and register initialization
            ENABLE_TRACE         => 0,
            REGS_INIT_ZERO       => 0,

            -- Interrupt masks
            MASKED_IRQ           => x"00000000",
            LATCHED_IRQ          => x"FFFFFFFF",

            -- Program and stack addresses
            PROGADDR_RESET       => start_address,
            PROGADDR_IRQ         => x"00000010",
            STACKADDR            => x"FFFFFFFF"
        )
        port map (

            -- Clock and reset
            clk    => clock_i,
            resetn => reset_n,

            -- CPU trap
            trap => cpu_trap,

            -- AXI write address channel
            mem_axi_awvalid => m_axi_awvalid_o,
            mem_axi_awready => m_axi_awready_i,
            mem_axi_awaddr  => m_axi_awaddr_o,
            mem_axi_awprot  => m_axi_awprot_o,

            -- AXI write data channel
            mem_axi_wvalid => m_axi_wvalid_o,
            mem_axi_wready => m_axi_wready_i,
            mem_axi_wdata  => m_axi_wdata_o,
            mem_axi_wstrb  => m_axi_wstrb_o,

            -- AXI write response channel
            mem_axi_bvalid => m_axi_bvalid_i,
            mem_axi_bready => m_axi_bready_o,

            -- AXI read address channel
            mem_axi_arvalid => m_axi_arvalid_o,
            mem_axi_arready => m_axi_arready_i,
            mem_axi_araddr  => m_axi_araddr_o,
            mem_axi_arprot  => m_axi_arprot_o,

            -- AXI read data channel
            mem_axi_rvalid => m_axi_rvalid_i,
            mem_axi_rready => m_axi_rready_o,
            mem_axi_rdata  => m_axi_rdata_i,

            -- PCPI interface disabled
            pcpi_valid => open,
            pcpi_insn  => open,
            pcpi_rs1   => open,
            pcpi_rs2   => open,
            pcpi_wr    => '0',
            pcpi_rd    => (others => '0'),
            pcpi_wait  => '0',
            pcpi_ready => '0',

            -- Interrupts disabled
            irq => (others => '0'),
            eoi => open,

            -- Trace disabled
            trace_valid => open,
            trace_data  => open
        );

    -- AXI response codes are not handled by PicoRV32 AXI.
    -- m_axi_bresp_i and m_axi_rresp_i are currently unused.

end architecture;