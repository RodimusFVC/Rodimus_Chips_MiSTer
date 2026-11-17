#!/usr/bin/env python3
"""compare_results.py <native.json> <refnet.json> <t48sv.json>: per (cell, tb) result + time"""
import json, sys
nat, ref, dut = (({(x['cell'], x['tb']): x for x in json.load(open(f))}) for f in sys.argv[1:4])
same_rd = sum(1 for k in dut if ref[k]['result'] == dut[k]['result'] and ref[k].get('time_ns') == dut[k].get('time_ns'))
same_nd = sum(1 for k in dut if nat[k]['result'] == dut[k]['result'] and nat[k].get('time_ns') == dut[k].get('time_ns'))
print('runs %d | t48sv == reference netlist (same bench, result+time): %d | t48sv == native VHDL: %d'
      % (len(dut), same_rd, same_nd))
for k in sorted(dut):
    if (ref[k]['result'], ref[k].get('time_ns')) != (dut[k]['result'], dut[k].get('time_ns')):
        print('  REF!=T48SV', k, ref[k]['result'], ref[k].get('time_ns'), dut[k]['result'], dut[k].get('time_ns'))
for k in sorted(dut):
    if (nat[k]['result'], nat[k].get('time_ns')) != (dut[k]['result'], dut[k].get('time_ns')):
        print('  NATIVE!=T48SV', k, 'native', nat[k]['result'], nat[k].get('time_ns'), 't48sv', dut[k]['result'], dut[k].get('time_ns'))
