import re
from pathlib import Path                                  
from vunit import VUnit                                  
                                  
ROOT = Path(__file__).parent / "../"   
 
# Call Vunit addons
VU = VUnit.from_argv()
VU.add_vhdl_builtins()
VU.add_verification_components()

# Source files                                
LIB = VU.add_library("lib")
LIB.add_source_files( ROOT / "picorv32" /"picorv32.v")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "axi_fifo.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "axi_interconnect_single.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "axi_lite_interconnect.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "axi_lite_interconnect_pkg.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "axi_ram.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "src" / "axi_soc_subsystem.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "axi_uart.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "uart.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "src" / "soc.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "axi_gpio.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "rams_sp_wf.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "rams_sp_wf_pkg.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "axi_slave_reg_bank.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "axi_slave_reg_bank_pkg.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "rtl_common" /  "src" / "time_elapsed.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" /  "src" / "timestamp_pkg.vhd")
LIB.add_source_files( ROOT / "src" / "riscv_wrapper.vhd")

#Libraries
LIB.add_source_files( ROOT / "riscv_soc_shell" / "tb" / "pkg" / "test_selection_pkg.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "tb" / "pkg" / "test_programs_pkg.vhd")
LIB.add_source_files( ROOT / "riscv_soc_shell" / "tb" / "riscv32im_isa_tb.vhd")

# Modelsim options
VU.set_sim_option('modelsim.init_files.after_load', [str(ROOT / 'sim' / 'wave_riscv32im_isa_tb.do')])
VU.set_sim_option('modelsim.vsim_flags', ["-voptargs=\"+acc\""])

tb = LIB.test_bench("riscv32im_isa_tb")

selection_file = ROOT / "riscv_soc_shell" / "tb" / "pkg" / "test_selection_pkg.vhd"
cases = re.findall(
    r"constant\s+tc_(\w+)\s*:\s*case_id_type\s*:=\s*(\d+)",
    selection_file.read_text(encoding="utf-8"),
    flags=re.IGNORECASE,
)

for name, case_id in cases:
    tb.add_config(
        name=name,
        generics={"selected_case": int(case_id)},
    )

VU.main()
