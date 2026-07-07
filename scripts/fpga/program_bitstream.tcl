# Vivado bitstream programming helper for xsai-env FPGA bring-up.
# Input is a directory containing one .bit and one .ltx file.

if {$argc != 1} {
  puts "Usage: vivado -mode batch -source program_bitstream.tcl -tclargs <bitstream-dir>"
  exit 1
}

set bitdir [file normalize [lindex $argv 0]]
if {![file isdirectory $bitdir]} {
  puts "ERROR: bitstream directory not found: $bitdir"
  exit 1
}

set bit_files [lsort [glob -nocomplain -directory $bitdir *.bit]]
set ltx_files [lsort [glob -nocomplain -directory $bitdir *.ltx]]

proc pick_preferred {files preferred_name} {
  foreach file $files {
    if {[file tail $file] eq $preferred_name} {
      return $file
    }
  }
  return [lindex $files 0]
}

if {[llength $bit_files] == 0} {
  puts "ERROR: no .bit file found in $bitdir"
  exit 1
}
if {[llength $ltx_files] == 0} {
  puts "ERROR: no .ltx file found in $bitdir"
  exit 1
}
if {[llength $bit_files] > 1} {
  puts "WARNING: multiple .bit files found; using [lindex $bit_files 0]"
}

set bit_file [lindex $bit_files 0]
set ltx_file [pick_preferred $ltx_files "pcie_part_gating_wrapper.ltx"]
if {[llength $ltx_files] > 1} {
  puts "WARNING: multiple .ltx files found; using $ltx_file"
}

puts "Bitstream directory: $bitdir"
puts "Bitstream: $bit_file"
puts "Probes: $ltx_file"

open_hw_manager
connect_hw_server
open_hw_target

set target [current_hw_target]
if {$target ne ""} {
  catch {set_property PARAM.FREQUENCY 12000000 $target}
}

set dev [lindex [get_hw_devices] 0]
if {$dev eq ""} {
  error "No hardware device found"
}

current_hw_device $dev
refresh_hw_device $dev
set_property PROGRAM.FILE $bit_file $dev
set_property PROBES.FILE $ltx_file $dev
catch {set_property FULL_PROBES.FILE $ltx_file $dev}

puts "Programming FPGA device: $dev"
program_hw_devices $dev
refresh_hw_device $dev
puts "FPGA programmed successfully."

close_hw_target
disconnect_hw_server
close_hw_manager
exit
