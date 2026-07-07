# Vivado VIO CPU reset helper for xsai-env FPGA bring-up.
# Inspired by OpenXiangShan/env-scripts fpga_diff reset helpers.
# Expected probe on the currently programmed design: pcie_part_gating_i/vio_0_probe_out0.

if {$argc < 1 || $argc > 2} {
  puts "Usage: vivado -mode batch -source reset_cpu.tcl -tclargs <path/to/xsai.ltx> ?reset_value?"
  exit 1
}

set ltx [lindex $argv 0]
set reset_value 1
if {$argc == 2} {
  set reset_value [lindex $argv 1]
}
if {$reset_value ne "0" && $reset_value ne "1"} {
  error "reset_value must be 0 or 1"
}

proc commit_all_vio {device} {
  foreach vio [get_hw_vios -of_objects $device] {
    commit_hw_vio $vio
  }
}

proc refresh_all_vio {device} {
  foreach vio [get_hw_vios -of_objects $device] {
    refresh_hw_vio $vio
  }
}

proc require_probe {device pattern} {
  set probes [get_hw_probes -of_objects [get_hw_vios -of_objects $device] -filter "NAME =~ *$pattern*"]
  if {[llength $probes] == 0} {
    error "Required VIO probe not found: $pattern"
  }
  return [lindex $probes 0]
}

open_hw_manager
connect_hw_server
open_hw_target

set dev [lindex [get_hw_devices] 0]
if {$dev eq ""} {
  error "No hardware device found"
}

current_hw_device $dev
set_property PROBES.FILE $ltx $dev
refresh_hw_device $dev
refresh_all_vio $dev

set reset_probe [require_probe $dev "vio_0_probe_out0"]

# set vio_sw4 [require_probe $dev "vio_sw4"]
# set vio_sw5 [require_probe $dev "vio_sw5"]
# set vio_sw6 [require_probe $dev "vio_sw6"]

set_property OUTPUT_VALUE $reset_value $reset_probe
commit_all_vio $dev
after 100
refresh_all_vio $dev

close_hw_target
disconnect_hw_server
close_hw_manager
