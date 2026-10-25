
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use STD.textio.all;
use ieee.std_logic_textio.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity soc_tb is
    generic (runner_cfg : string := runner_cfg_default);
end soc_tb;

architecture rtl of soc_tb is

constant C_SYS_FREQ : natural := 100_000_000;
constant C_BAUDRATE : natural := 781248;

constant clk_const      : time := 5 ns;
constant reset_n_const  : time := 83.334 ns;

-- DUT signals
signal clk          : std_logic;
signal reset_n      : std_logic:='0';
signal uart_rx      : std_logic;
signal uart_tx      : std_logic;

-- CPU control and debug
signal cpu_reset_i        : std_logic := '0';
signal stall_i            : std_logic := '0';
signal fault_i            : std_logic := '0';
signal fault_o            : std_logic;
signal registers_debug_o : std_logic_vector(1023 downto 0);
signal pc_debug_o        : std_logic_vector(31 downto 0);
signal previous_pc_debug_o : std_logic_vector(31 downto 0);


--- UART signals
signal byte_in      : std_logic_vector(7 downto 0) := (others => '0');
signal byte_en_in   : std_logic := '0';
signal byte_out     : std_logic_vector(7 downto 0);
signal byte_en_out  : std_logic;
signal busy_tx      : std_logic;

function generate_frame(addr : std_logic_vector(31 downto 0); 
                       data : std_logic_vector(31 downto 0)) 
                       return std_logic_vector is
    variable frame : std_logic_vector(71 downto 0);
begin
    frame(71 downto 40) := data(7 downto 0) & data(15 downto 8) & data(23 downto 16) & data(31 downto 24);
    frame(39 downto 8)  := addr(7 downto 0) & addr(15 downto 8) & addr(23 downto 16) & addr(31 downto 24);
    frame(7 downto 0)   :=  x"AA";
    return frame;
end function;

function generate_jump_frame(addr : std_logic_vector(31 downto 0); 
                       data : std_logic_vector(31 downto 0)) 
                       return std_logic_vector is
    variable frame : std_logic_vector(71 downto 0);
begin
    frame(71 downto 40) := data(7 downto 0) & data(15 downto 8) & data(23 downto 16) & data(31 downto 24);
    frame(39 downto 8)  := addr(7 downto 0) & addr(15 downto 8) & addr(23 downto 16) & addr(31 downto 24);
    frame(7 downto 0)   :=  x"55";
    return frame;
end function;


function flip_bytes(data : std_logic_vector) return std_logic_vector is
    variable result : std_logic_vector(data'range);
    variable byte_idx : integer;
begin
    byte_idx := 0;
    for i in 0 to (data'length / 8) - 1 loop
        result((i+1)*8-1 downto i*8) := data(data'length - i*8 - 1 downto data'length - (i+1)*8);
    end loop;
    return result;
end function;

signal bootloader_rx_frame      : std_logic_vector(71 downto 0);
signal data_read_from_file      : std_logic_vector(31 downto 0);

begin

-----------------------------------------
-- clk generation
-----------------------------------------
clk_gen_pr: process
begin
    clk <= '1';
    wait for clk_const;

    clk <= '0';
    wait for clk_const;
end process;

-----------------------------------------
-- reset_n generation
-----------------------------------------
reset_n_gen_pr:process
begin
    reset_n <= '0';
    wait for reset_n_const;
    reset_n <= '1';
    wait;
end process;


-- Instantiate the SoC; keep the external AXI master idle.
soc_inst : entity work.soc
    generic map (
        G_SYS_FREQ => C_SYS_FREQ,
        G_BAUDRATE => C_BAUDRATE
    )
    port map (
        -- Clock, reset and UART
        clk         => clk,
        reset_n     => reset_n,
        cpu_reset_i => cpu_reset_i,
        uart_rx     => uart_rx,
        uart_tx     => uart_tx,

        -- CPU control and debug
        stall_i             => stall_i,
        fault_i             => fault_i,
        fault_o             => fault_o,
        registers_debug_o   => registers_debug_o,
        pc_debug_o          => pc_debug_o,
        previous_pc_debug_o => previous_pc_debug_o,

        -- Disable the external AXI4-Lite initiator.
        ext_axi_awvalid => '0',
        ext_axi_awready => open,
        ext_axi_awaddr  => (others => '0'),
        ext_axi_awprot  => (others => '0'),
        ext_axi_wvalid  => '0',
        ext_axi_wready  => open,
        ext_axi_wdata   => (others => '0'),
        ext_axi_wstrb   => (others => '0'),
        ext_axi_bvalid  => open,
        ext_axi_bready  => '1',
        ext_axi_arvalid => '0',
        ext_axi_arready => open,
        ext_axi_araddr  => (others => '0'),
        ext_axi_arprot  => (others => '0'),
        ext_axi_rvalid  => open,
        ext_axi_rready  => '1',
        ext_axi_rdata   => open,
        ext_axi_bresp   => open,
        ext_axi_rresp   => open
    );

test_runner : process
variable v_bootloader_frame : std_logic_vector(32+32+8-1 downto 0);
file fid_file_in                        : text;
variable v_INLINE                       : line;
variable v_b3, v_b2, v_b1, v_b0         : std_logic_vector(7 downto 0);
variable v_word                         : std_logic_vector(31 downto 0);
variable v_cnt                          : std_logic_vector(31 downto 0):=x"00001000";
begin
test_runner_setup(runner, runner_cfg);

    if run("test_001_one_ms") then

        -- Wait for reset to be released
        wait until rising_edge(reset_n);
        wait for 1 ms;

        info("Wait 25 ms");
        wait for 25 ms;

    end if;

    if run("test_002_adder_program") then

        -- Wait for reset to be released
        wait until rising_edge(reset_n);
        wait for 100 us;

        info("Wait 12 ms");
        wait for 12 ms;

        info("Send 10");
        -- Send ASCII 1
        byte_in    <= std_logic_vector(to_unsigned(49, 8));
        byte_en_in <= '1';
        wait until rising_edge(clk);
        byte_en_in <= '0';
        wait until rising_edge(clk);
        while busy_tx = '1' loop
            wait until rising_edge(clk);
        end loop;

        -- Send ASCII 0
        byte_in    <= std_logic_vector(to_unsigned(48, 8));
        byte_en_in <= '1';
        wait until rising_edge(clk);
        byte_en_in <= '0';
        wait until rising_edge(clk);
        while busy_tx = '1' loop
            wait until rising_edge(clk);
        end loop;

        -- Send ASCII \r
        byte_in    <= x"0D";
        byte_en_in <= '1';
        wait until rising_edge(clk);
        byte_en_in <= '0';
        wait until rising_edge(clk);
        while busy_tx = '1' loop
            wait until rising_edge(clk);
        end loop;
        
        -- Send ASCII \n
        byte_in    <= x"0A";
        byte_en_in <= '1';
        wait until rising_edge(clk);
        byte_en_in <= '0';
        wait until rising_edge(clk);
        while busy_tx = '1' loop
            wait until rising_edge(clk);
        end loop;

        info("Wait 5 ms");
        wait for 5 ms;

        info("Send 11");
        -- Send ASCII 1
        byte_in    <= std_logic_vector(to_unsigned(49, 8));
        byte_en_in <= '1';
        wait until rising_edge(clk);
        byte_en_in <= '0';
        wait until rising_edge(clk);
        while busy_tx = '1' loop
            wait until rising_edge(clk);
        end loop;

        -- Send ASCII 1
        byte_in    <= std_logic_vector(to_unsigned(49, 8));
        byte_en_in <= '1';
        wait until rising_edge(clk);
        byte_en_in <= '0';
        wait until rising_edge(clk);
        while busy_tx = '1' loop
            wait until rising_edge(clk);
        end loop;

        -- Send ASCII \r
        byte_in    <= x"0D";
        byte_en_in <= '1';
        wait until rising_edge(clk);
        byte_en_in <= '0';
        wait until rising_edge(clk);
        while busy_tx = '1' loop
            wait until rising_edge(clk);
        end loop;
        
        -- Send ASCII \n
        byte_in    <= x"0A";
        byte_en_in <= '1';
        wait until rising_edge(clk);
        byte_en_in <= '0';
        wait until rising_edge(clk);
        while busy_tx = '1' loop
            wait until rising_edge(clk);
        end loop;

        wait for 10 ms;

        info("Simulation finished");

    end if;

    if run("test_003_bootloader_only") then

        -- Wait for reset to be released
        wait until rising_edge(reset_n);
        wait for 100 us;

        info("Wait 20 ms");
        wait for 20 ms;

        info("-----------------------------------------------");
        info("Send a frame");
        info("-----------------------------------------------");
        v_bootloader_frame := generate_frame(x"00000C00", x"12345678");
        wait for 0 ns;

        for i in 0 to 8 loop
            byte_in    <= v_bootloader_frame((i+1)*8-1 downto i*8);
            byte_en_in <= '1';
            wait until rising_edge(clk);
            byte_en_in <= '0';
            wait until rising_edge(clk);
            while busy_tx = '1' loop
                wait until rising_edge(clk);
            end loop;
        end loop;
        info("Frame sent");

        info("ACK receive");
        for i in 0 to 8 loop
            info("Byte " & to_string(i) & " received");
            wait until falling_edge(byte_en_out);
            bootloader_rx_frame((i+1)*8-1 downto i*8)   <= byte_out;
            wait for 0 ns;
        end loop;
        bootloader_rx_frame <= flip_bytes(bootloader_rx_frame);
        wait for 0 ns;
        check_equal(bootloader_rx_frame, std_logic_vector'(x"AA00000C0012345678"), "First frame ACK");

        info("Wait 1 ms");
        wait for 1 ms;

        info("-----------------------------------------------");
        info("Send a frame");
        info("-----------------------------------------------");
        v_bootloader_frame := generate_frame(x"00000C04", x"9abcdef1");
        wait for 0 ns;

        for i in 0 to 8 loop
            byte_in    <= v_bootloader_frame((i+1)*8-1 downto i*8);
            byte_en_in <= '1';
            wait until rising_edge(clk);
            byte_en_in <= '0';
            wait until rising_edge(clk);
            while busy_tx = '1' loop
                wait until rising_edge(clk);
            end loop;
        end loop;
        info("Frame sent");

        info("ACK receive");
        for i in 0 to 8 loop
            info("Byte " & to_string(i) & " received");
            wait until falling_edge(byte_en_out);
            bootloader_rx_frame((i+1)*8-1 downto i*8)   <= byte_out;
            wait for 0 ns;
        end loop;
        bootloader_rx_frame <= flip_bytes(bootloader_rx_frame);
        wait for 0 ns;
        check_equal(bootloader_rx_frame, std_logic_vector'(x"AA00000C049abcdef1"), "Second frame ACK");

        info("Wait 1 ms");
        wait for 1 ms;

--        info("-----------------------------------------------");
--        info("Send a frame for app jump");
--        info("-----------------------------------------------");
--
--        v_bootloader_frame := generate_jump_frame(x"00000000", x"00000000");
--        wait for 0 ns;
--
--        for i in 0 to 8 loop
--            byte_in    <= v_bootloader_frame((i+1)*8-1 downto i*8);
--            byte_en_in <= '1';
--            wait until rising_edge(clk);
--            byte_en_in <= '0';
--            wait until rising_edge(clk);
--            while busy_tx = '1' loop
--                wait until rising_edge(clk);
--            end loop;
--        end loop;
--        info("Frame sent");
--
--        info("Wait 1 ms");
--        wait for 1 ms;

        info("Simulation finished");

    end if;

    if run("test_004_bootloader_upload_and_jump") then

        -- Wait for reset to be released
        wait until rising_edge(reset_n);
        wait for 100 us;

        info("Open files");
        file_open(fid_file_in, "../../../c/bootloader_AND_gpio_write_loop/ram_data.txt",  read_mode);

        info("Wait 1.5 ms");
        wait for 1.5 ms;

        info("-----------------------------------------------");
        info("Start to send app");
        info("-----------------------------------------------");

        info("Feed input values from a file");
        while not endfile(fid_file_in) loop
            readline(fid_file_in, v_INLINE);

            hread(v_INLINE, v_b3);
            hread(v_INLINE, v_b2);
            hread(v_INLINE, v_b1);
            hread(v_INLINE, v_b0);
            wait for 0 ns;
            v_word := v_b3 & v_b2 & v_b1 & v_b0;
            wait for 0 ns;
            data_read_from_file <= v_word;
            wait until rising_edge(clk);
            wait until rising_edge(clk);


            info("Send a frame");
            v_bootloader_frame := generate_frame(v_cnt, data_read_from_file);
            v_cnt := std_logic_vector(unsigned(v_cnt)+4);
            wait for 0 ns;

            for i in 0 to 8 loop
                byte_in    <= v_bootloader_frame((i+1)*8-1 downto i*8);
                byte_en_in <= '1';
                wait until rising_edge(clk);
                byte_en_in <= '0';
                wait until rising_edge(clk);
                while busy_tx = '1' loop
                    wait until rising_edge(clk);
                end loop;
            end loop;
            info("Frame sent");

            info("ACK receive");
            for i in 0 to 8 loop
                info("Byte " & to_string(i) & " received");
                wait until falling_edge(byte_en_out);
                bootloader_rx_frame((i+1)*8-1 downto i*8)   <= byte_out;
                wait for 0 ns;
            end loop;
            bootloader_rx_frame <= flip_bytes(bootloader_rx_frame);
            wait for 0 ns;

            info("Wait 0.125 ms");
            wait for 0.125 ms;

        end loop; --end while

        info("Finished to load the app thourgh bootloader");  
        info("Generate the jump frame");
        v_bootloader_frame := generate_jump_frame(v_cnt, data_read_from_file);
        wait for 0 ns;
        
        for i in 0 to 8 loop
            byte_in    <= v_bootloader_frame((i+1)*8-1 downto i*8);
            byte_en_in <= '1';
            wait until rising_edge(clk);
            byte_en_in <= '0';
            wait until rising_edge(clk);
            while busy_tx = '1' loop
                wait until rising_edge(clk);
            end loop;
        end loop;
        info("Jump frame sent");

        info("Wait for bootloader prompt and send 'y' to jump");
        wait for 1 ms;
        byte_in    <= x"79";  -- ASCII 'y'
        byte_en_in <= '1';
        wait until rising_edge(clk);
        byte_en_in <= '0';
        wait until rising_edge(clk);
        while busy_tx = '1' loop
            wait until rising_edge(clk);
        end loop;
        info("'y' sent to bootloader");

        info("Wait 5 ms");
        wait for 5 ms;
        info("Simulation finished");

    end if;

test_runner_cleanup(runner);
end process;

uart_inst : entity work.uart
    generic map (
        G_SYS_FREQ => C_SYS_FREQ,
        G_BAUD     => C_BAUDRATE
    )
    port map (
        clk         => clk,
        byte_in     => byte_in,
        byte_en_in  => byte_en_in,
        uart_rx     => uart_tx,
        byte_out    => byte_out,
        byte_en_out => byte_en_out,
        busy_tx     => busy_tx,
        uart_tx     => uart_rx
);

uart_monitor_pr : process
-- This process monitors UART output and displays it as a console.
variable line_buffer : string(1 to 256);
variable idx         : integer := 1;
variable char_val    : character;
begin
    wait until rising_edge(clk);
    while true loop
        wait until rising_edge(clk);
        if byte_en_out = '1' then
            char_val := character'val(to_integer(unsigned(byte_out)));
            if char_val = LF or char_val = CR then
                -- Print the current line and reset buffer
                if idx > 1 then
                    report "UART RX: " & line_buffer(1 to idx-1);
                end if;
                idx := 1;
            else
                if idx <= line_buffer'length then
                    line_buffer(idx) := char_val;
                    idx := idx + 1;
                end if;
            end if;
        end if;
    end loop;
end process;


end rtl;
