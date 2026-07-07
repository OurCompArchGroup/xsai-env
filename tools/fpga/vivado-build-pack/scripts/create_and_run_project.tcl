set PART "xcvu19p-fsva3824-2-e"
set TOP "pcie_part_gating_wrapper"
set BD_NAME "pcie_part_gating"

proc fail {msg} {
  puts stderr "ERROR: $msg"
  exit 1
}

proc usage {} {
  puts "Usage: create_and_run_project.tcl --template <template_root> --rtl <rtl_dir> --out <output_dir> --name <project_name> --jobs <N> --run-to <project|synth|impl|bitstream>"
}

proc parse_args {argv} {
  array set opts {
    --template ""
    --rtl ""
    --out ""
    --name "cpu_fpga_build"
    --jobs "8"
    --run-to "synth"
  }

  set i 0
  while {$i < [llength $argv]} {
    set key [lindex $argv $i]
    if {![info exists opts($key)]} {
      usage
      fail "unknown argument: $key"
    }
    incr i
    if {$i >= [llength $argv]} {
      fail "$key requires a value"
    }
    set opts($key) [lindex $argv $i]
    incr i
  }
  return [array get opts]
}

proc abs_path {path} {
  set norm [file normalize $path]
  return $norm
}

proc copy_clean {src dst} {
  if {[file exists $dst]} {
    file delete -force $dst
  }
  file mkdir [file dirname $dst]
  file copy -force $src $dst
}

proc relative_path {root path} {
  set root [file normalize $root]
  set path [file normalize $path]
  set prefix "${root}/"
  if {[string first $prefix $path] != 0} {
    fail "$path is not under $root"
  }
  return [string range $path [string length $prefix] end]
}

proc find_hdl_files {root} {
  set result {}
  foreach item [glob -nocomplain -directory $root *] {
    if {[file isdirectory $item]} {
      set result [concat $result [find_hdl_files $item]]
    } else {
      set ext [string tolower [file extension $item]]
      if {$ext in {.v .sv .vh .svh}} {
        lappend result [file normalize $item]
      }
    }
  }
  return [lsort -dictionary $result]
}

proc collect_existing {patterns} {
  set files {}
  foreach pattern $patterns {
    foreach f [glob -nocomplain {*}$pattern] {
      if {[file exists $f]} {
        lappend files [file normalize $f]
      }
    }
  }
  return [lsort -dictionary -unique $files]
}

proc run_and_check {run_name} {
  set progress [get_property PROGRESS [get_runs $run_name]]
  set status [get_property STATUS [get_runs $run_name]]
  puts "$run_name progress: $progress"
  puts "$run_name status: $status"
  if {![string match "100%*" $progress]} {
    fail "$run_name did not complete: $status"
  }
  if {[string match -nocase "*fail*" $status] || [string match -nocase "*error*" $status]} {
    fail "$run_name failed: $status"
  }
}

proc run_is_complete {run_name} {
  set progress [get_property PROGRESS [get_runs $run_name]]
  set status [get_property STATUS [get_runs $run_name]]
  if {[string match -nocase "*fail*" $status] || [string match -nocase "*error*" $status]} {
    return 0
  }
  return [string match "100%*" $progress]
}

proc launch_if_needed {run_name jobs {to_step ""}} {
  if {[run_is_complete $run_name]} {
    puts "$run_name already complete; skipping launch."
    run_and_check $run_name
    return
  }

  if {$to_step eq ""} {
    launch_runs $run_name -jobs $jobs
  } else {
    launch_runs $run_name -to_step $to_step -jobs $jobs
  }
  wait_on_run $run_name
  run_and_check $run_name
}

array set opts [parse_args $argv]

set template_root [abs_path $opts(--template)]
set rtl_dir [abs_path $opts(--rtl)]
set out_dir [abs_path $opts(--out)]
set project_name $opts(--name)
set jobs $opts(--jobs)
set run_to $opts(--run-to)

if {![file isdirectory $template_root]} {
  fail "template root does not exist: $template_root"
}
if {![file isdirectory $rtl_dir]} {
  fail "RTL directory does not exist: $rtl_dir"
}
if {![string is integer -strict $jobs] || $jobs < 1} {
  fail "--jobs must be a positive integer"
}
if {$run_to ni {project synth impl bitstream}} {
  fail "--run-to must be one of: project, synth, impl, bitstream"
}

set template_srcs "${template_root}/kmh_mini_ai_raw_bigddr8g_0522.srcs"
set wrapper_src "${template_srcs}/sources_1/imports/verilog_wrapper"
set top_wrapper_src "${template_srcs}/sources_1/imports/pcie_part_gating_wrapper.v"
set bd_tcl_src "${template_root}/kmh_mini_ai_raw_bigddr8g_0522.gen/sources_1/bd/${BD_NAME}/hw_handoff/${BD_NAME}_bd.tcl"
set xdc_src "${template_srcs}/constrs_1/imports/constr/vu19p.xdc"

foreach required [list $wrapper_src $top_wrapper_src $bd_tcl_src $xdc_src] {
  if {![file exists $required]} {
    fail "required template path does not exist: $required"
  }
}

set rtl_files [find_hdl_files $rtl_dir]
if {[llength $rtl_files] == 0} {
  fail "no RTL files found under $rtl_dir"
}

file mkdir $out_dir
set project_dir "${out_dir}/${project_name}"
set existing_project 0

set vivado_version [version -short]
set start_time [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S %Z}]

if {[file exists $project_dir]} {
  set xpr "${project_dir}/${project_name}.xpr"
  if {![file exists $xpr]} {
    fail "project directory already exists but .xpr was not found: $xpr"
  }
  puts "Existing project found; opening for resume: $xpr"
  open_project $xpr
  set existing_project 1
} else {
  create_project $project_name $project_dir -part $PART
  set_property target_language Verilog [current_project]
  set_property default_lib xil_defaultlib [current_project]
  set_property source_mgmt_mode All [current_project]

  set local_srcs "${project_dir}/${project_name}.srcs"
  set local_imports "${local_srcs}/sources_1/imports"
  set local_bd_dir "${local_srcs}/sources_1/bd/${BD_NAME}"
  set local_constr_dir "${local_srcs}/constrs_1/imports/constr"
  set local_wrapper_dir "${local_imports}/verilog_wrapper"
  set local_rtl_dir "${local_imports}/rtl"

  copy_clean $wrapper_src $local_wrapper_dir
  copy_clean $top_wrapper_src "${local_imports}/pcie_part_gating_wrapper.v"
  copy_clean $xdc_src "${local_constr_dir}/vu19p.xdc"
  file mkdir $local_rtl_dir

  foreach src $rtl_files {
    set rel [relative_path $rtl_dir $src]
    set dst "${local_rtl_dir}/${rel}"
    file mkdir [file dirname $dst]
    file copy -force $src $dst
  }

  set wrapper_files [find_hdl_files $local_wrapper_dir]
  set local_rtl_files [find_hdl_files $local_rtl_dir]

  add_files -fileset sources_1 $wrapper_files
  add_files -fileset sources_1 $local_rtl_files
  add_files -fileset sources_1 "${local_imports}/pcie_part_gating_wrapper.v"
  add_files -fileset constrs_1 "${local_constr_dir}/vu19p.xdc"

  update_compile_order -fileset sources_1
  source $bd_tcl_src
  if {![file exists "${local_bd_dir}/${BD_NAME}.bd"]} {
    fail "BD Tcl did not create expected design: ${local_bd_dir}/${BD_NAME}.bd"
  }

  set_property top $TOP [current_fileset]
  set_property top XSTop_wrapper_dse [get_filesets sim_1]
  set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
  set_property strategy "Congestion_SSI_SpreadLogic_high" [get_runs impl_1]

  generate_target all [get_files "${local_bd_dir}/${BD_NAME}.bd"]
  export_ip_user_files -of_objects [get_files "${local_bd_dir}/${BD_NAME}.bd"] -no_script -sync -force -quiet
  update_compile_order -fileset sources_1
}

if {$run_to in {synth impl bitstream}} {
  launch_if_needed synth_1 $jobs
}

if {$run_to eq "impl"} {
  launch_if_needed impl_1 $jobs
}

if {$run_to eq "bitstream"} {
  set impl_run_dir "${project_dir}/${project_name}.runs/impl_1"
  set existing_bits [glob -nocomplain -directory $impl_run_dir *.bit]
  if {[llength $existing_bits] > 0 && [run_is_complete impl_1]} {
    puts "Bitstream already exists; skipping launch: [lindex $existing_bits 0]"
    run_and_check impl_1
  } else {
    launch_runs impl_1 -to_step write_bitstream -jobs $jobs
    wait_on_run impl_1
    run_and_check impl_1
  }
}

set artifacts_dir "${out_dir}/artifacts"
file mkdir $artifacts_dir

set synth_run_dir "${project_dir}/${project_name}.runs/synth_1"
set impl_run_dir "${project_dir}/${project_name}.runs/impl_1"
set artifact_patterns [list \
  [list -directory $synth_run_dir *.dcp] \
  [list -directory $synth_run_dir *.rpt] \
]

if {$run_to in {impl bitstream}} {
  lappend artifact_patterns [list -directory $impl_run_dir *.dcp]
  lappend artifact_patterns [list -directory $impl_run_dir *timing_summary*.rpt]
  lappend artifact_patterns [list -directory $impl_run_dir *utilization*.rpt]
  lappend artifact_patterns [list -directory $impl_run_dir *route_status*.rpt]
}
if {$run_to eq "bitstream"} {
  lappend artifact_patterns [list -directory $impl_run_dir *.bit]
  lappend artifact_patterns [list -directory $impl_run_dir *.ltx]
}

foreach artifact [collect_existing $artifact_patterns] {
  file copy -force $artifact "${artifacts_dir}/[file tail $artifact]"
}

set summary "${out_dir}/build_summary.txt"
set fp [open $summary w]
puts $fp "project_name: $project_name"
puts $fp "project_dir: $project_dir"
puts $fp "template_root: $template_root"
puts $fp "bd_tcl: $bd_tcl_src"
puts $fp "rtl_dir: $rtl_dir"
puts $fp "part: $PART"
puts $fp "top: $TOP"
puts $fp "vivado_version: $vivado_version"
puts $fp "start_time: $start_time"
puts $fp "finish_time: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S %Z}]"
puts $fp "run_to: $run_to"
puts $fp "jobs: $jobs"
puts $fp "existing_project: $existing_project"
puts $fp "rtl_file_count: [llength $rtl_files]"
puts $fp "synth_status: [get_property STATUS [get_runs synth_1]]"
puts $fp "synth_progress: [get_property PROGRESS [get_runs synth_1]]"
if {$run_to in {impl bitstream}} {
  puts $fp "impl_status: [get_property STATUS [get_runs impl_1]]"
  puts $fp "impl_progress: [get_property PROGRESS [get_runs impl_1]]"
}
puts $fp "artifacts_dir: $artifacts_dir"
close $fp

puts "Build complete."
puts "Project: $project_dir"
puts "Summary: $summary"
puts "Artifacts: $artifacts_dir"
