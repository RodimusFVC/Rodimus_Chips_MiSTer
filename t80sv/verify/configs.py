"""Every reference top x every value of every generic. name -> (vhdl top, source tree, generics, dut module, dut params)."""

GB_FLAGS = dict(Flag_S=0, Flag_P=0, Flag_X=0, Flag_Y=0, Flag_C=4, Flag_H=5, Flag_N=6, Flag_Z=7)

def _all():
    c = {}
    for top in ('T80s', 'T80se'):
        for m in range(4):
            for t in (0, 1):
                for w in (0, 1):
                    c[f'{top.lower()}_m{m}_t{t}_w{w}'] = (top, 'stock', dict(Mode=m, T2Write=t, IOWait=w))
    c['t80sed'] = ('T80sed', 'stock', {})
    for m in range(4):
        c[f't80pa_m{m}'] = ('T80pa', 'stock', dict(Mode=m))
        c[f'phx_t80pa_m{m}'] = ('T80pa', 'phx', dict(Mode=m))
        for t in (0, 1):
            c[f't8080se_m{m}_t{t}'] = ('T8080se', 'stock', dict(Mode=m, T2Write=t))
        for w in (0, 1):
            c[f't80a_m{m}_w{w}'] = ('T80a', 'stock', dict(Mode=m, IOWait=w))
            c[f't80_m{m}_w{w}'] = ('T80', 'stock', dict(Mode=m, IOWait=w))
            c[f'phx_t80_m{m}_w{w}'] = ('T80', 'phx', dict(Mode_g=m, IOWait=w))
        c[f't80as_m{m}'] = ('T80as', 'stock', dict(Mode=m))
    for t in (0, 1):
        for w in (0, 1):
            c[f'gbse_t{t}_w{w}'] = ('GBse', 'stock', dict(T2Write=t, IOWait=w))
    for w in (0, 1):
        c[f't80_m3gb_w{w}'] = ('T80', 'stock', dict(Mode=3, IOWait=w, **GB_FLAGS))
    return c

CONFIGS = _all()

# fleet configurations: regression priority (deepest runs, ZEXDOC / ZEXALL)
FLEET = ['t80s_m0_t1_w1', 't80pa_m0', 't80se_m0_t0_w1', 'phx_t80pa_m0', 't80sed', 't8080se_m2_t1', 't8080se_m2_t0']

def mode_of(name):
    top, src, g = CONFIGS[name]
    if top == 'GBse':
        return 3
    if top == 'T8080se':
        return g.get('Mode', 2)
    return g.get('Mode', g.get('Mode_g', 0))

# fleet bus-type wrappers (rtl/t80sv_fleet.sv), each locked to the reference top it replaces.
# name -> (reference config, wrapper module, input type, fixed reference inputs, extra outputs, has reset in struct)
FLEET_WRAPPERS = {
    'fleet_z80':     ('t80s_m0_t1_w1', 't80sv_z80', 'z80_i_t', {'WAIT_n': "1'b1", 'BUSRQ_n': "1'b1", 'OUT0': "1'b0"}, [], False),
    'fleet_z80r':    ('t80s_m0_t1_w1', 't80sv_z80r', 'z80r_i_t', {'WAIT_n': "1'b1", 'BUSRQ_n': "1'b1", 'OUT0': "1'b0"}, [], True),
    'fleet_z80r_t0': ('t80se_m0_t0_w1', 't80sv_z80r', 'z80r_i_t', {'WAIT_n': "1'b1", 'BUSRQ_n': "1'b1"}, [], True),
    'fleet_z80w':    ('t80s_m0_t1_w1', 't80sv_z80w', 'z80w_i_t', {'BUSRQ_n': "1'b1", 'OUT0': "1'b0"}, [], False),
    'fleet_z80sed':  ('t80sed', 't80sv_z80sed', 'z80sed_i_t', {'BUSRQ_n': "1'b1"}, [], True),
    'fleet_z80pa':   ('t80pa_m0', 't80sv_z80pa', 'z80pa_i_t', {'OUT0': "1'b0", 'R800_mode': "1'b0", 'DIRSet': "1'b0"},
                      ['busak_n', 'inte'], True),
    'fleet_z80pa85': ('phx_t80pa_m0', 't80sv_z80pa85', 'z80pa85_i_t',
                      {'BUSRQ_n': "1'b1", 'OUT0': "1'b0", 'R800_mode': "1'b0", 'DIRSet': "1'b0"}, ['sod'], False),
}
