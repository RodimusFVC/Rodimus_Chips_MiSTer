#!/usr/bin/env python3
"""Build GHDL-synthesised Verilog reference models of the T48 tops.

Usage: build_refs.py <lineageA_dir> <lineageB_dir> <r295_rtl_vhdl_dir> <out_dir> [config ...]

Lineage A: fleet stock T48 r295 (e.g. Arcade-Galaxian_MiSTer rtl/cpu/i8039)
Lineage B: T48 2023+ release as carried by Arcade-DECOCassette_MiSTer rtl/cpu/T48
Every module of a model is prefixed with "<config>__" so that several models can
be linked into one Verilator build.
"""
import os, re, subprocess, sys, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
VH = os.path.join(HERE, 'vhdl')

A_FILES = ['t48_pack-p', 'alu_pack-p', 'cond_branch_pack-p', 'dmem_ctrl_pack-p', 'pmem_ctrl_pack-p',
           'decoder_pack-p', 't48_tb_pack-p', 't48_comp_pack-p', 't48_core_comp_pack-p',
           'alu', 'bus_mux', 'clock_ctrl', 'cond_branch', 'db_bus', 'dmem_ctrl', 'int', 'decoder',
           'p1', 'p2', 'pmem_ctrl', 'psw', 'timer', 't48_core', 'generic_ram_ena', 't8039_notri',
           't8039_notri_extrom']
B_FILES = ['t48_pack-p', 'alu_pack-p', 'cond_branch_pack-p', 'dmem_ctrl_pack-p', 'pmem_ctrl_pack-p',
           'decoder_pack-p', 't48_tb_pack-p', 'alu', 'bus_mux', 'clock_ctrl', 'cond_branch', 'db_bus',
           'dmem_ctrl', 'int', 'decoder', 'p1', 'p2', 'pmem_ctrl', 'psw', 'timer', 'adc', 't48_core',
           'upi41_db_bus', 'upi41_core', 't21_core', 't22_core', 'system/generic_ram_ena',
           'system/t48_rom-e', 'system/t49_rom-e', '@harness_roms',
           'system/t8039_notri', 'system/t8048_notri', 'system/t8041_notri', 'system/t8041a_notri',
           'system/t8042ah_notri', 'system/t8021_notri', 'system/t8022_notri',
           '@harness_t48_core_comp_pack-p', '@recovered/t48_system_comp_pack-p',
           '@recovered/syn_rom-e', '@recovered/syn_ram-e', '@harness_syn', 'system/wb_master',
           'system/t8050_wb']

# lineage R: upstream r295 snapshot (013d615) incl. its system tops; same core as A
R_FILES = ['t48_pack-p', 'alu_pack-p', 'cond_branch_pack-p', 'dmem_ctrl_pack-p', 'pmem_ctrl_pack-p',
           'decoder_pack-p', 't48_tb_pack-p', 't48_comp_pack-p', 't48_core_comp_pack-p',
           'alu', 'bus_mux', 'clock_ctrl', 'cond_branch', 'db_bus', 'dmem_ctrl', 'int', 'decoder',
           'p1', 'p2', 'pmem_ctrl', 'psw', 'timer', 't48_core', 'system/generic_ram_ena',
           'system/t48_rom-e', 'system/t49_rom-e', '@harness_roms', 'system/t8039_notri',
           'system/t8048_notri']

# name: (lineage, top entity, generics)
CONFIGS = {
    # --- lineage A (fleet) ---
    'A_extrom_g0_r7': ('A', 't8039_notri_extrom', {'gate_port_input_g': 0, 'ram_addr_width_g': 7}),
    'A_extrom_g0_r6': ('A', 't8039_notri_extrom', {'gate_port_input_g': 0, 'ram_addr_width_g': 6}),
    'A_extrom_g1_r7': ('A', 't8039_notri_extrom', {'gate_port_input_g': 1, 'ram_addr_width_g': 7}),
    'A_extrom_g1_r6': ('A', 't8039_notri_extrom', {'gate_port_input_g': 1, 'ram_addr_width_g': 6}),
    'A_extrom_g0_r8': ('A', 't8039_notri_extrom', {'gate_port_input_g': 0, 'ram_addr_width_g': 8}),
    'A_core':         ('A', 't48_core', {}),
    'A_core_x0':      ('A', 't48_core', {'xtal_div_3_g': 0}),
    'A_core_m0':      ('A', 't48_core', {'register_mnemonic_g': 0}),
    'A_core_t3':      ('A', 't48_core', {'sample_t1_state_g': 3}),
    'A_core_min':     ('A', 't48_core', {'include_port1_g': 0, 'include_port2_g': 0,
                                         'include_bus_g': 0, 'include_timer_g': 0}),
    'A_t8039_notri':  ('A', 't8039_notri', {}),
    'R_core':           ('R', 't48_core', {}),
    'R_t8039_notri_g0': ('R', 't8039_notri', {'gate_port_input_g': 0}),
    'R_t8039_notri_g1': ('R', 't8039_notri', {'gate_port_input_g': 1}),
    'R_t8048_notri_g0': ('R', 't8048_notri', {'gate_port_input_g': 0}),
    'R_t8048_notri_g1': ('R', 't8048_notri', {'gate_port_input_g': 1}),
    # --- lineage B (2023+ release, fleet DECO copy) ---
    'B_t8039_notri_g0': ('B', 't8039_notri', {'gate_port_input_g': 0}),
    'B_t8041_notri_g0': ('B', 't8041_notri', {'gate_port_input_g': 0}),
    'B_t8041a_notri_g0': ('B', 't8041a_notri', {'gate_port_input_g': 0}),
    'B_t8042ah_notri_g0': ('B', 't8042ah_notri', {'gate_port_input_g': 0}),
    'B_t8021_notri_g0': ('B', 't8021_notri', {'gate_port_input_g': 0}),
    'B_t8022_notri_g0': ('B', 't8022_notri', {'gate_port_input_g': 0}),
    'B_core':         ('B', 't48_core', {}),
    'B_t8039_notri':  ('B', 't8039_notri', {}),
    'B_t8048_notri':  ('B', 't8048_notri', {}),
    'B_t8048_notri_g0': ('B', 't8048_notri', {'gate_port_input_g': 0}),
    'B_upi41_core':   ('B', 'upi41_core', {}),
    'B_upi41_core_a0': ('B', 'upi41_core', {'is_upi_type_a_g': 0}),
    'B_t8041_notri':  ('B', 't8041_notri', {}),
    'B_t8041a_notri': ('B', 't8041a_notri', {}),
    'B_t8042ah_notri': ('B', 't8042ah_notri', {}),
    'B_t21_core':     ('B', 't21_core', {}),
    'B_t22_core':     ('B', 't22_core', {}),
    'B_t8021_notri':  ('B', 't8021_notri', {}),
    'B_t8022_notri':  ('B', 't8022_notri', {}),
    'B_t8050_wb':     ('B', 't8050_wb', {}),
}


def analyse(lineage, src, work):
    os.makedirs(work, exist_ok=True)
    for f in os.listdir(work):
        if f.endswith('.cf'):
            os.remove(os.path.join(work, f))
    files = {'A': A_FILES, 'B': B_FILES, 'R': R_FILES}[lineage]
    for f in files:
        path = os.path.join(VH, f[1:] + '.vhd') if f.startswith('@') else os.path.join(src, f + '.vhd')
        subprocess.run(['ghdl', '-a', '--std=93c', '-frelaxed', '--workdir=' + work, path],
                       check=True, capture_output=True)


def synth(cfg, work, out_dir):
    lineage, top, gens = CONFIGS[cfg]
    cmd = ['ghdl', 'synth', '--std=93c', '-frelaxed', '--workdir=' + work, '--out=verilog']
    cmd += ['-g%s=%d' % kv for kv in gens.items()]
    cmd.append(top)
    v = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
    mods = re.findall(r'^module (\w+)', v, re.M)
    for m in sorted(mods, key=len, reverse=True):
        v = re.sub(r'\b%s\b' % re.escape(m), '%s__%s' % (cfg, m), v)
    # the black-box ROM is shared harness code, not renamed
    out = os.path.join(out_dir, cfg + '.v')
    with open(out, 'w') as fh:
        fh.write('// GHDL %s synth of %s %s %s -- reference model, do not edit\n' %
                 (lineage, top, gens, cfg))
        fh.write(v)
    return out


def main():
    a_src, b_src, r_src, out_dir = sys.argv[1:5]
    want = sys.argv[5:] or list(CONFIGS)
    os.makedirs(out_dir, exist_ok=True)
    srcs = {'A': a_src, 'B': b_src, 'R': r_src}
    done = set()
    for cfg in want:
        lin = CONFIGS[cfg][0]
        work = os.path.join(out_dir, 'work' + lin)
        if lin not in done:
            analyse(lin, srcs[lin], work)
            done.add(lin)
        print(cfg, synth(cfg, work, out_dir))


if __name__ == '__main__':
    main()
