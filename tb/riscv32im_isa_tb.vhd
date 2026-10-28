library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library vunit_lib;
context vunit_lib.vunit_context;
use work.test_selection_pkg.all;
use work.test_programs_pkg.all;

entity riscv32im_isa_tb is
  generic (runner_cfg : string := runner_cfg_default;
           selected_case : natural := 0;
           entry_address : natural := 0);
end entity;
architecture beh of riscv32im_isa_tb is
  constant C_SYS_FREQ : natural := 100_000_000;
  constant C_BAUDRATE : natural := 781248;
  constant USE_ASYNC_RESET : boolean := false;
  constant USE_SYNC_RESET : boolean := true;
  constant ASYNC_RESET_ACTIVE : std_logic := '1';
  constant SYNC_RESET_ACTIVE : std_logic := '1';
  signal clk : std_logic := '0';
  signal async_reset : std_logic := '0';
  signal sync_reset : std_logic := '1';
  signal cpu_reset_i : std_logic := '1';
  signal stall_i : std_logic := '1';
  signal fault_i : std_logic := '0';
  signal fault_o : std_logic;
  signal registers_debug_o : std_logic_vector(1023 downto 0);
  signal pc_debug_o, previous_pc_debug_o : std_logic_vector(31 downto 0);
  signal uart_tx : std_logic;
signal ext_axi_awaddr  : std_logic_vector(31 downto 0) := (others => '0');

signal ext_axi_awprot  : std_logic_vector(2 downto 0)  := (others => '0');

signal ext_axi_awvalid : std_logic := '0';

signal ext_axi_awready : std_logic;

signal ext_axi_wdata   : std_logic_vector(31 downto 0) := (others => '0');

signal ext_axi_wstrb   : std_logic_vector(3 downto 0)  := (others => '0');

signal ext_axi_wvalid  : std_logic := '0';

signal ext_axi_wready  : std_logic;

signal ext_axi_bresp   : std_logic_vector(1 downto 0);

signal ext_axi_bvalid  : std_logic;

signal ext_axi_bready  : std_logic := '0';

signal ext_axi_araddr  : std_logic_vector(31 downto 0) := (others => '0');

signal ext_axi_arprot  : std_logic_vector(2 downto 0)  := (others => '0');

signal ext_axi_arvalid : std_logic := '0';

signal ext_axi_arready : std_logic;

signal ext_axi_rdata   : std_logic_vector(31 downto 0);

signal ext_axi_rresp   : std_logic_vector(1 downto 0);

signal ext_axi_rvalid  : std_logic;

signal ext_axi_rready  : std_logic := '0';

procedure axi_write(

    signal clock_i   : in  std_logic;

    signal awaddr_o  : out std_logic_vector(31 downto 0);

    signal awvalid_o : out std_logic;

    signal awready_i : in  std_logic;

    signal wdata_o   : out std_logic_vector(31 downto 0);

    signal wstrb_o   : out std_logic_vector(3 downto 0);

    signal wvalid_o  : out std_logic;

    signal wready_i  : in  std_logic;

    signal bresp_i   : in  std_logic_vector(1 downto 0);

    signal bvalid_i  : in  std_logic;

    signal bready_o  : out std_logic;

    constant addr    : in  std_logic_vector(31 downto 0);

    constant data    : in  std_logic_vector(31 downto 0)

) is

    variable aw_done : boolean;

    variable w_done  : boolean;

begin

    wait until falling_edge(clock_i);

    awaddr_o  <= addr;

    awvalid_o <= '1';

    wdata_o   <= data;

    wstrb_o   <= "1111";

    wvalid_o  <= '1';

    bready_o  <= '1';

    aw_done := false;

    w_done  := false;

    -- AW and W are independent AXI-Lite channels.

    while not (aw_done and w_done) loop

        wait until rising_edge(clock_i);

        if not aw_done and awready_i = '1' then

            aw_done := true;

            awvalid_o <= '0';

        end if;

        if not w_done and wready_i = '1' then

            w_done := true;

            wvalid_o <= '0';

        end if;

    end loop;

    -- Wait for write response.

    loop

        wait until rising_edge(clock_i);

        exit when bvalid_i = '1';

    end loop;

    check_equal(bresp_i, std_logic_vector'("00"),

                "AXI-Lite WRITE BRESP");

    wait until falling_edge(clock_i);

    bready_o <= '0';

end procedure;

procedure axi_read(

    signal clock_i   : in  std_logic;

    signal araddr_o  : out std_logic_vector(31 downto 0);

    signal arvalid_o : out std_logic;

    signal arready_i : in  std_logic;

    signal rdata_i   : in  std_logic_vector(31 downto 0);

    signal rresp_i   : in  std_logic_vector(1 downto 0);

    signal rvalid_i  : in  std_logic;

    signal rready_o  : out std_logic;

    constant addr    : in  std_logic_vector(31 downto 0);

    variable data    : out std_logic_vector(31 downto 0)

) is

begin

    wait until falling_edge(clock_i);

    araddr_o  <= addr;

    arvalid_o <= '1';

    rready_o <= '1';

    -- Wait for address acceptance.

    loop

        wait until rising_edge(clock_i);

        exit when arready_i = '1';

    end loop;

    arvalid_o <= '0';

    -- Wait for read response.

    loop

        wait until rising_edge(clock_i);

        exit when rvalid_i = '1';

    end loop;

    data := rdata_i;

    check_equal(rresp_i, std_logic_vector'("00"),

                "AXI-Lite READ RRESP");

    wait until falling_edge(clock_i);

    rready_o <= '0';

end procedure;

begin
  clk <= not clk after 5 ns;
  soc_inst : entity work.soc

    generic map (

        USE_ASYNC_RESET    => USE_ASYNC_RESET,

        USE_SYNC_RESET     => USE_SYNC_RESET,

        ASYNC_RESET_ACTIVE => ASYNC_RESET_ACTIVE,

        SYNC_RESET_ACTIVE  => SYNC_RESET_ACTIVE,

        G_SYS_FREQ => C_SYS_FREQ,

        G_BAUDRATE => C_BAUDRATE

    )

    port map (

        -- Clock, reset and UART

        clk         => clk,

        async_reset => async_reset,

        sync_reset  => sync_reset,

        cpu_reset_i => cpu_reset_i,

        uart_rx     => '1',

        uart_tx     => uart_tx,

        -- CPU control and debug

        stall_i             => stall_i,

        fault_i             => fault_i,

        fault_o             => fault_o,

        registers_debug_o   => registers_debug_o,

        pc_debug_o          => pc_debug_o,

        previous_pc_debug_o => previous_pc_debug_o,

        -- Axi lite AXI RAM direct access

        ext_axi_awaddr  => ext_axi_awaddr,

        ext_axi_awprot  => ext_axi_awprot,

        ext_axi_awvalid => ext_axi_awvalid,

        ext_axi_awready => ext_axi_awready,

        ext_axi_wdata   => ext_axi_wdata,

        ext_axi_wstrb   => ext_axi_wstrb,

        ext_axi_wvalid  => ext_axi_wvalid,

        ext_axi_wready  => ext_axi_wready,

        ext_axi_bresp   => ext_axi_bresp,

        ext_axi_bvalid  => ext_axi_bvalid,

        ext_axi_bready  => ext_axi_bready,

        ext_axi_araddr  => ext_axi_araddr,

        ext_axi_arprot  => ext_axi_arprot,

        ext_axi_arvalid => ext_axi_arvalid,

        ext_axi_arready => ext_axi_arready,

        ext_axi_rdata   => ext_axi_rdata,

        ext_axi_rresp   => ext_axi_rresp,

        ext_axi_rvalid  => ext_axi_rvalid,

        ext_axi_rready  => ext_axi_rready

    );

  test_runner : process
    variable value, expected, init_data : std_logic_vector(31 downto 0);
    variable init_address : natural;
    variable active_case, finished, expect_fault : boolean;
    variable executed : natural := 0;
  begin
    test_runner_setup(runner, runner_cfg);
    if run("instructions") then
      wait for 100 ns;
      wait until falling_edge(clk);
      sync_reset <= '0';
      for vi in vectors'range loop
        active_case := (selected_case = 0 or vectors(vi).case_id = selected_case);
        if active_case then
          active_case := false;
          for ei in enabled_cases'range loop
            if enabled_cases(ei) = vectors(vi).case_id then
              active_case := true;
            end if;
          end loop;
        end if;
        if active_case then
          executed := executed + 1;
          info("RUN case=" & integer'image(vectors(vi).case_id) & " vector=" & integer'image(vectors(vi).vector_id));
          stall_i <= '1';
          for i in 0 to 199 loop wait until rising_edge(clk); end loop;
          cpu_reset_i <= '1';
          wait for 100 ns;
          expected := vectors(vi).expected_c;
          if vectors(vi).case_id = 34 or vectors(vi).case_id = 35 or vectors(vi).case_id = 37 then
            expected := std_logic_vector(unsigned(expected) + to_unsigned(entry_address, 32));
          end if;
          expect_fault := vectors(vi).expect_fault;
          for i in 0 to vectors(vi).length + 5 loop
            if i = 0 then init_address := 256; init_data := vectors(vi).operand_a;
            elsif i = 1 then init_address := 260; init_data := vectors(vi).operand_b;
            elsif i = 2 then init_address := 264; init_data := vectors(vi).initial_c;
            elsif i = 3 then init_address := 268; init_data := x"00000000";
            elsif i = 4 then init_address := 272; init_data := x"A55A1234";
            elsif i = 5 then init_address := 276; init_data := x"5AA54321";
            else
              init_address := entry_address - (entry_address mod 4) + 4 * (i - 6);
              init_data := vectors(vi).program(i - 6);
              if vectors(vi).case_id = 35 and i = 9 then
                init_data := std_logic_vector(unsigned(init_data) + shift_left(to_unsigned(entry_address, 32), 20));
              end if;
            end if;
            axi_write(clk, ext_axi_awaddr, ext_axi_awvalid, ext_axi_awready, ext_axi_wdata, ext_axi_wstrb, ext_axi_wvalid, ext_axi_wready, ext_axi_bresp, ext_axi_bvalid, ext_axi_bready, std_logic_vector(to_unsigned(init_address, 32)), init_data);
          end loop;
          wait until falling_edge(clk);
          cpu_reset_i <= '0';
          stall_i <= '0';
          finished := false;
          for poll in 0 to 3000 loop
            axi_read(clk, ext_axi_araddr, ext_axi_arvalid, ext_axi_arready, ext_axi_rdata, ext_axi_rresp, ext_axi_rvalid, ext_axi_rready, x"0000010C", value);
            if expect_fault then
              if fault_o = '1' then
                check_equal(value, std_logic_vector'(x"00000000"), "DONE after fault");
                finished := true; exit;
              end if;
            else
              check_equal(fault_o, std_logic'('0'), "unexpected CPU fault");
              if value = x"00000001" then finished := true; exit; end if;
            end if;
          end loop;
          check_true(finished, "instruction completion timeout");
          if not expect_fault then stall_i <= '1'; end if;
          for i in 0 to 199 loop wait until rising_edge(clk); end loop;
          axi_read(clk, ext_axi_araddr, ext_axi_arvalid, ext_axi_arready, ext_axi_rdata, ext_axi_rresp, ext_axi_rvalid, ext_axi_rready, x"00000108", value);
          check_equal(value, expected, "instruction result");
          axi_read(clk, ext_axi_araddr, ext_axi_arvalid, ext_axi_arready, ext_axi_rdata, ext_axi_rresp, ext_axi_rvalid, ext_axi_rready, x"00000110", value);
          check_equal(value, std_logic_vector'(x"A55A1234"), "guard 1");
          axi_read(clk, ext_axi_araddr, ext_axi_arvalid, ext_axi_arready, ext_axi_rdata, ext_axi_rresp, ext_axi_rvalid, ext_axi_rready, x"00000114", value);
          check_equal(value, std_logic_vector'(x"5AA54321"), "guard 2");
        end if;
      end loop;
      check_true(executed > 0, "no instruction vector selected");
      info("ALL PASS vectors=" & integer'image(executed));
    end if;
    test_runner_cleanup(runner);
    wait;
  end process;
end architecture;
