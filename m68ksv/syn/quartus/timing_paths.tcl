# Copyright (C) 2026 Rodimus
# m68ksv Quartus test project: write the worst setup paths of a compiled revision to a text file.
# Run after a full compile, from this folder (Quartus 17.0):
#   quartus_sta -t timing_paths.tcl <revision> [number of paths, default 30]
# e.g. quartus_sta -t timing_paths.tcl m68ksv_qtop
# Output: output_files/<revision>.paths.txt - one line per path (distinct endpoints, worst first): slack, data delay,
# logic levels, from node, to node, at the slow 1100 mV 100 C corner (the corner the brief's 96 MHz target uses),
# followed by Quartus's own report_timing summary of the same paths.

set rev [lindex $quartus(args) 0]
if {$rev eq ""} {
    post_message -type error "usage: quartus_sta -t timing_paths.tcl <revision> \[npaths\]"
    qexit -error
}
set npaths 30
if {[llength $quartus(args)] > 1} { set npaths [lindex $quartus(args) 1] }

project_open m68ksv_qtop -revision $rev
create_timing_netlist
read_sdc
# pick the slow 1100 mV 100 C operating condition (name depends on the speed grade, e.g. 7_slow_1100mv_100c)
set cond ""
set cname "default corner (check the header of the .sta.rpt)"
catch {
    foreach_in_collection oc [get_available_operating_conditions] {
        set nm [get_operating_conditions_info -display_name $oc]
        if {[string match -nocase "*slow*1100*100*" $nm]} { set cond $oc; set cname $nm }
    }
    if {$cond ne ""} { set_operating_conditions $cond }
}
update_timing_netlist

set out "output_files/${rev}.paths.txt"
set f [open $out w]
puts $f "m68ksv timing paths: revision $rev, $cname"
puts $f "worst $npaths setup paths, one per endpoint (slack ns, data delay ns, logic levels, from -> to)"
puts $f ""
puts $f [format "%4s %8s %8s %6s  %s" "#" "slack" "delay" "levels" "from -> to"]
set i 0
foreach_in_collection p [get_timing_paths -setup -npaths $npaths -nworst 1] {
    incr i
    set slack [get_path_info $p -slack]
    set dd    [get_path_info $p -data_delay]
    set lv "?"
    catch { set lv [get_path_info $p -num_logic_levels] }
    set from  [get_node_info -name [get_path_info $p -from]]
    set to    [get_node_info -name [get_path_info $p -to]]
    puts $f [format "%4d %8.3f %8.3f %6s  %s -> %s" $i $slack $dd $lv $from $to]
}
close $f

# Quartus's own summary of the same paths, appended
report_timing -setup -npaths $npaths -nworst 1 -detail summary -file "output_files/${rev}.paths_summary.txt"
set g [open "output_files/${rev}.paths_summary.txt" r]
set summary [read $g]
close $g
set f [open $out a]
puts $f ""
puts $f "---- report_timing -setup -npaths $npaths -nworst 1 -detail summary"
puts $f $summary
close $f
file delete "output_files/${rev}.paths_summary.txt"

delete_timing_netlist
project_close
post_message "m68ksv: wrote $out"
