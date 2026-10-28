add wave -noupdate -divider {=====================}
add wave -noupdate -divider {         TB          }
add wave -noupdate -divider {=====================}

add wave -noupdate -divider {riscv32im_isa_tb}
add wave -position insertpoint sim:/riscv32im_isa_tb/*

add wave -noupdate -divider {=====================}
add wave -noupdate -divider {       SOC           }
add wave -noupdate -divider {=====================}

add wave -noupdate -divider {soc_inst}
add wave -position insertpoint sim:/riscv32im_isa_tb/soc_inst/*

add wave -noupdate -divider {picorv32_axi_inst}
add wave -position insertpoint sim:/riscv32im_isa_tb/soc_inst/riscv_wrapper_inst/picorv32_axi_inst/*

add wave -noupdate -divider {axi_soc_subsystem_inst}
add wave -position insertpoint sim:/riscv32im_isa_tb/soc_inst/axi_soc_subsystem_inst/*

add wave -noupdate -divider {u_axi_lite_interconnect}
add wave -position insertpoint sim:/riscv32im_isa_tb/soc_inst/axi_soc_subsystem_inst/u_axi_lite_interconnect/*

add wave -noupdate -divider {axi_interconnect_single_first_inst}
add wave -position insertpoint sim:/riscv32im_isa_tb/soc_inst/axi_soc_subsystem_inst/u_axi_lite_interconnect/axi_interconnect_single_first_inst/*

add wave -noupdate -divider {u_axi_uart}
add wave -position insertpoint sim:/riscv32im_isa_tb/soc_inst/axi_soc_subsystem_inst/u_axi_uart/*


config wave -signalnamewidth 1