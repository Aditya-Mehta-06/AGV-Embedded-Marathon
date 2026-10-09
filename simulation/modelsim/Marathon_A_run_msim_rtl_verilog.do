transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+/home/aditya_mehta06/AGV_Embedded/Marathon_A {/home/aditya_mehta06/AGV_Embedded/Marathon_A/ov7670_capture.v}

vlog -vlog01compat -work work +incdir+/home/aditya_mehta06/AGV_Embedded/Marathon_A {/home/aditya_mehta06/AGV_Embedded/Marathon_A/tb_ov7670_capture.v}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cycloneive_ver -L rtl_work -L work -voptargs="+acc"  tb_ov7670_capture

add wave *
view structure
view signals
run -all
