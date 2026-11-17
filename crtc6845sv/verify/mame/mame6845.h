// Character-clock transliteration of MAME src/devices/video/mc6845.cpp (Wilbert Pol, Nigel Barnes; BSD-3-Clause),
// md5 aaaff6e62887123c9a8c5de1a30b6682 (mamedev/mame master, fetched 2026-10-29).
// MAME runs the CRTC from emu_timers: a line timer every R0 + 1 characters (re-armed at each line start), plus de_off
// (R1), hsync_on (R2), hsync_off (width), cursor_on / cursor_off, the light pen latch (+1 character) and the transparent
// update timer (4 characters). Here every timer becomes a character position or a down-counter stepped once per
// character clock; at equal times, timers armed earlier fire first (MAME's timer list order).
// handle_line_timer, match_line, is_row_end, check_cursor_visible (mc6845 / hd6845s), update_cursor_state,
// register_r / register_w / status_r and the transparent-update logic follow MAME's code in logic and order.
//
// Knobs: each one replaces one MAME behaviour with the crtc6845sv choice. All knobs off = MAME. The variant harness
// enables, per variant, exactly the knobs listed in REPORT.md and requires zero mismatches; reverting one knob at a
// time measures that difference alone.
#pragma once
#include <cstdint>

enum MameType { M_MC6845, M_MC6845_1, M_R6545_1, M_C6545_1, M_SY6545_1, M_SY6845E, M_AMS40489, M_HD6845S };

struct Knobs {
    bool hsw0_none = false;     // R3 HSYNC width 0 = no HSYNC (MAME: 16)
    bool vsw_prog = false;      // R3 high nibble VSYNC width although MAME's type has it fixed
    bool frame_match = false;   // R6 / R7 also compared on row 0 at frame start (MAME: only if vert sync width supported)
    bool blink_ds = false;      // blink from the field counter: 1/16 = 8 on / 8 off, 1/32 = 16 / 16 (MAME: half that rate)
    bool cursor_line = false;   // line latch set at R10, cleared after R11, every line (MAME: per-row range rules)
    bool cursor_fleet = false;  // fleet: latch updated only at the cursor character, cleared on line 0
    bool first_off = false;     // display off until the first frame start after reset
    bool engine_t0 = false;     // type-0 / fleet vertical engine: adjust lines compare the line counter with R5 - 1,
                                // no row counting inside the adjust, row counter = R4 + 1 there
    bool adj_hold = false;      // (with engine_t0) row counter held at R4 during the adjust
    bool de_fleet = false;      // vertical display = row < R6 and not in adjust (comparator, CRTCADJ fix)
    bool vs_r2 = false;         // VSYNC evaluated and switched at character R2 (with HSYNC) instead of character 0
    bool il_fleet = false;      // R8 = 3: scan lines count in twos with bit 0 forced 0 (MAME: rudimentary +adjust)
    bool hs_cont = false;       // HSYNC from a width counter that runs while HSYNC is active and is not restarted
                                // by a new start (MAME restarts its off timer)
    bool hs_strict = false;     // HSYNC only when R2 <= R0 (MAME fires R2 = R0 + 1 at the line end)
    bool r6z = false;           // R6 = 0 keeps the display off at any time (UM6845R)
    bool vma_row0 = false;      // start address reloaded on every line of row 0 (UM6845R)
    bool rowcol = false;        // R8 b2 row / column addressing: rows advance by 0x100 (MAME: only in its draw path)
    bool upd_needs_mode = false;// transparent updates only while R8 b3 set (MAME arms them on any DE fall)
    bool lp_now = false;        // light pen latches the address of the character being output when LPSTB is seen
    bool vs_hdl = false;        // VSYNC: R7 / line 0 tested on every line, width counter not restarted while
                                // VSYNC is active (MAME: tested at row changes, a match restarts the width)
    bool r1z_no_de = false;     // R1 = 0: no DE edge at all (MAME raises DE for zero time at each line start, which
                                // cancels and re-arms its transparent-update timer)
    bool first_ma0 = false;     // the first frame after reset runs from address 0 (row start register cleared by
                                // reset), not from R12/R13
    bool upd_access3 = false;   // R31 access mid-character: update on the 4th following character (MAME: 4 character
                                // times after the access, i.e. inside that character)
};

struct Mame6845 {
    Knobs k;
    bool supports_disp_start_addr_r = false, supports_vert_sync_width = false, status_d5 = false, status_d6 = false,
         status_d7 = false, supports_transparent = false, hd_cursor = false;
    int noninterlace_adjust = 1, interlace_adjust = 1;
    uint8_t horiz_char_total = 0xff, horiz_disp = 0, horiz_sync_pos = 1, sync_width = 1, vert_char_total = 0x7f,
            vert_total_adj = 0, vert_disp = 0, vert_sync_pos = 0, mode_control = 0, max_ras_addr = 0x1f,
            cursor_start_ras = 0, cursor_end_ras = 0;
    uint16_t disp_start_addr = 0, cursor_addr = 0, light_pen_addr = 0, update_addr = 0;
    uint8_t register_address_latch = 0;
    bool cursor_state = false, light_pen_latched = false, update_ready_bit = false;
    uint8_t cursor_blink_count = 0;
    int cur = 0, hsync = 0, vsync = 0, de = 0;
    uint8_t line_counter = 0, line_counter_mask = 0x7f, raster_counter = 0, field = 0, adjust_counter = 0,
            vsync_width_counter = 0;
    bool interlace_fields = false, latch_row_end = false, row_end = false, line_enable_ff = false;
    uint8_t vsync_ff = 0, adjust_active = 0;
    uint16_t line_address = 0;
    int cursor_x = -1;
    // timers (characters)
    int char_counter = 0, line_len = 256, de_off_at = -1, de_off_pending = -1, hsync_on_at = -1, hsync_off_left = -1,
        cur_on_at = -1, cur_off_left = -1, lp_left = -1, upd_left = -1;
    bool started = false;
    // knob state
    unsigned frame_ends = 0;    // fields since reset (fleet field counter)
    bool cur_carry = false, cur_latch = false;
    int vs_pending = -1;        // vs_r2: VSYNC value to apply at character R2
    // transparent update events produced at this character (for the harness)
    bool upd_strobe = false;
    uint16_t upd_strobe_addr = 0;
    uint64_t frames = 0;

    virtual ~Mame6845() {}
    // subclass hooks (MAME virtuals: frame_start, set_vsync, update_cursor_state)
    virtual void on_frame_start() {}
    virtual void on_set_vsync(int state) { vsync = state; }
    virtual void cursor_state_hook() { update_cursor_state(); }
    explicit Mame6845(MameType t) {
        switch (t) {
        case M_MC6845: break;
        case M_MC6845_1: supports_disp_start_addr_r = true; supports_vert_sync_width = true; break;
        case M_R6545_1: case M_SY6545_1: case M_SY6845E:
            supports_vert_sync_width = true; status_d5 = status_d6 = status_d7 = true; supports_transparent = true; break;
        case M_C6545_1: supports_vert_sync_width = true; status_d5 = status_d6 = true; break;
        case M_AMS40489: supports_disp_start_addr_r = true; break;
        case M_HD6845S: supports_disp_start_addr_r = true; supports_vert_sync_width = true; hd_cursor = true;
            noninterlace_adjust = 1; interlace_adjust = 2; break;
        }
    }
    bool MODE_INTERLACE_AND_VIDEO() const { return (mode_control & 3) == 3; }
    bool MODE_TRANSPARENT() const { return (mode_control & 0x08) != 0; }
    bool MODE_TRANSPARENT_PHI2() const { return (mode_control & 0x88) == 0x88; }
    bool MODE_TRANSPARENT_BLANK() const { return (mode_control & 0x88) == 0x08; }
    bool vsw_supported() const { return supports_vert_sync_width || k.vsw_prog; }
    bool il_knob() const { return k.il_fleet && MODE_INTERLACE_AND_VIDEO(); }

    void address_w(uint8_t d) { register_address_latch = d & 0x1f; }
    uint8_t status_r() const {
        uint8_t r = 0;
        if (status_d5 && !line_enable_ff) r |= 0x20;
        if (status_d6 && light_pen_latched) r |= 0x40;
        if (status_d7 && update_ready_bit) r |= 0x80;
        return r;
    }
    bool in_access = false;
    void update_upd_adr_timer() {
        if (!de && supports_transparent && (!k.upd_needs_mode || MODE_TRANSPARENT_BLANK()))
            upd_left = (in_access && k.upd_access3) ? 3 : 4;
    }
    void transparent_update() {
        if (supports_transparent && MODE_TRANSPARENT()) {
            if (MODE_TRANSPARENT_PHI2()) {
                update_addr = (update_addr + 1) & 0x3fff;
            } else if (update_ready_bit) {
                update_ready_bit = false;
                update_upd_adr_timer();
            }
        }
    }
    uint8_t register_r() {
        in_access = true;
        uint8_t r = register_r_();
        in_access = false;
        return r;
    }
    uint8_t register_r_at(uint8_t idx) {
        uint8_t save = register_address_latch;
        register_address_latch = idx;
        uint8_t r = register_r();
        register_address_latch = save;
        return r;
    }
    uint8_t register_r_() {
        uint8_t r = 0;
        switch (register_address_latch) {
        case 0x0c: r = supports_disp_start_addr_r ? (disp_start_addr >> 8) & 0xff : 0; break;
        case 0x0d: r = supports_disp_start_addr_r ? disp_start_addr & 0xff : 0; break;
        case 0x0e: r = (cursor_addr >> 8) & 0xff; break;
        case 0x0f: r = cursor_addr & 0xff; break;
        case 0x10: r = (light_pen_addr >> 8) & 0xff; light_pen_latched = false; break;
        case 0x11: r = light_pen_addr & 0xff; light_pen_latched = false; break;
        case 0x1f: transparent_update(); break;
        default: break;
        }
        return r;
    }
    void register_w(uint8_t d) {
        in_access = true;
        register_w_(d);
        in_access = false;
    }
    void register_w_(uint8_t d) {
        switch (register_address_latch) {
        case 0x00: horiz_char_total = d; break;
        case 0x01: horiz_disp = d; break;
        case 0x02: horiz_sync_pos = d; break;
        case 0x03: sync_width = d; break;
        case 0x04: vert_char_total = d & 0x7f; break;
        case 0x05: vert_total_adj = d & 0x1f; break;
        case 0x06: vert_disp = d & 0x7f; break;
        case 0x07: vert_sync_pos = d & 0x7f; break;
        case 0x08: mode_control = d; break;
        case 0x09: max_ras_addr = d & 0x1f; break;
        case 0x0a: cursor_start_ras = d & 0x7f; break;
        case 0x0b: cursor_end_ras = d & 0x1f; break;
        case 0x0c: disp_start_addr = ((d & 0x3f) << 8) | (disp_start_addr & 0x00ff); break;
        case 0x0d: disp_start_addr = d | (disp_start_addr & 0xff00); break;
        case 0x0e: cursor_addr = ((d & 0x3f) << 8) | (cursor_addr & 0x00ff); break;
        case 0x0f: cursor_addr = d | (cursor_addr & 0xff00); break;
        case 0x12: if (supports_transparent) update_addr = ((d & 0x3f) << 8) | (update_addr & 0x00ff); break;
        case 0x13: if (supports_transparent) update_addr = d | (update_addr & 0xff00); break;
        case 0x1f: transparent_update(); break;
        default: break;
        }
    }

    bool vs_block = false;
    // device_reset: outputs low, address latch / cursor address / update address / light pen cleared
    void device_reset() {
        de = hsync = vsync = 0;
        light_pen_latched = false;
        cursor_addr = 0; line_address = 0; cursor_x = 0; register_address_latch = 0; update_addr = 0; light_pen_addr = 0;
    }
    bool match_line() {
        if (line_counter == vert_disp) line_enable_ff = false;
        if (line_counter == vert_sync_pos) { vsync_width_counter = 0; vsync_ff = 1; return true; }
        return false;
    }
    bool is_row_end() const {
        if (il_knob()) return raster_counter == (max_ras_addr & 0x1e);
        if (interlace_fields && MODE_INTERLACE_AND_VIDEO())
            return (raster_counter >= max_ras_addr) || ((raster_counter + 1) == max_ras_addr);
        return raster_counter == (uint8_t)(max_ras_addr + (MODE_INTERLACE_AND_VIDEO() ? interlace_adjust : noninterlace_adjust) - 1);
    }
    uint8_t next_raster() const {
        if (il_knob()) return (raster_counter + 2) & 0x1e;
        return (raster_counter + 1) & 0x1f;
    }
    bool check_cursor_visible(uint16_t ra, uint16_t line_addr) const {
        if (!cursor_state) return false;
        if (cursor_addr < line_addr || cursor_addr >= line_addr + horiz_disp) return false;
        uint16_t cs = cursor_start_ras & 0x1f;
        uint16_t mra = max_ras_addr + (MODE_INTERLACE_AND_VIDEO() ? interlace_adjust : noninterlace_adjust) - 1;
        if (hd_cursor) {
            if (cs > mra || cs > cursor_end_ras) return false;
            return ra >= cs && ra <= cursor_end_ras;
        }
        if (cs > mra) return false;
        if (cs <= cursor_end_ras) {
            if (cursor_end_ras > mra) return true;
            return ra >= cs && ra <= cursor_end_ras;
        }
        return ra <= cursor_end_ras || ra >= cs;
    }
    bool blink_on() const {
        switch ((cursor_start_ras >> 5) & 3) {
        case 0: return true;
        case 1: return false;
        case 2: return (frame_ends & 8) != 0;
        default: return (frame_ends & 16) != 0;
        }
    }
    // cursor decision for the line just started (knob variants), using the line's raster and address
    bool cursor_this_line() {
        bool in_row = cursor_addr >= line_address && cursor_addr < line_address + horiz_disp;
        uint8_t ra = raster_counter;
        if (k.cursor_fleet) {
            bool on = (ra == (cursor_start_ras & 0x1f)) || (cur_latch && ra != 0);
            bool hit = in_row && line_enable_ff && horiz_disp > 0;
            if (hit) cur_latch = on && ra != cursor_end_ras;
            return hit && on && (k.blink_ds ? blink_on() : cursor_state);
        }
        bool on = (ra == (cursor_start_ras & 0x1f)) || cur_carry;
        cur_carry = on && ra != cursor_end_ras;
        return in_row && line_enable_ff && on && (k.blink_ds ? blink_on() : cursor_state);
    }
    void update_cursor_state() {
        uint8_t last = cursor_blink_count;
        cursor_blink_count++;
        switch (cursor_start_ras & 0x60) {
        case 0x00: cursor_state = true; break;
        default: case 0x20: cursor_state = false; break;
        case 0x40: if ((last & 0x10) != (cursor_blink_count & 0x10)) cursor_state = !cursor_state; break;
        case 0x60: if ((last & 0x20) != (cursor_blink_count & 0x20)) cursor_state = !cursor_state; break;
        }
    }
    void frame_restart(bool &new_vsync) {
        adjust_active = 0;
        field = (interlace_fields && MODE_INTERLACE_AND_VIDEO()) ? (field ^ 1) : 0;
        raster_counter = field;
        line_counter = 0;
        line_address = disp_start_addr;
        line_enable_ff = true;
        if (vsw_supported() || k.frame_match) { if (match_line()) new_vsync = true; }
        cursor_state_hook();
        frames++;
        on_frame_start();
    }

    // handle_line_timer (with the knob alternatives)
    void line_timer() {
        bool new_vsync = vsync;
        char_counter = 0;
        cursor_x = -1;
        bool vs_was = vsync_ff;
        uint8_t vs_cnt_was = vsync_width_counter;
        bool vsync_was = vsync;
        uint8_t lc_was = line_counter;
        vs_block = vs_was;
        if (vsync_ff) {
            uint8_t vw = vsw_supported() ? (sync_width >> 4) & 0x0f : 0;
            vsync_width_counter = (vsync_width_counter + 1) & 0x0f;
            if (vsync_width_counter == vw) { vsync_ff = 0; new_vsync = false; }
        }
        bool restarted = false;
        if (k.engine_t0) {
            // fleet / type 0 vertical engine (crtc6845sv f_end / r_end)
            uint8_t msl = adjust_active ? ((vert_total_adj - 1) & 0x1f) : max_ras_addr;
            if (il_knob()) msl &= 0x1e;
            bool line_eq = raster_counter == msl;
            if (line_eq && (adjust_active || (line_counter == vert_char_total && vert_total_adj == 0))) {
                frame_ends++;
                frame_restart(new_vsync);
                restarted = true;
            } else if (line_eq && !adjust_active) {
                bool go = line_counter == vert_char_total && vert_total_adj != 0;
                raster_counter = 0;
                if (!(k.adj_hold && go)) line_counter = (line_counter + 1) & line_counter_mask;
                line_address = (line_address + ((k.rowcol && (mode_control & 4)) ? 0x100 : horiz_disp)) & 0x3fff;
                if (go) { adjust_active = 1; }
                if (!(k.adj_hold && go)) { if (match_line()) new_vsync = true; }
                else if (line_counter == vert_sync_pos) {
                    vsync_width_counter = 0; vsync_ff = 1; new_vsync = true;
                }
            } else
                raster_counter = next_raster();
        } else {
            bool field_raster = interlace_fields && MODE_INTERLACE_AND_VIDEO();
            if (latch_row_end ? row_end : is_row_end()) {
                if (line_counter == vert_char_total) { adjust_counter = 0; adjust_active = 1; }
                raster_counter = field_raster ? (~(raster_counter ^ max_ras_addr) & 1) : 0;
                line_counter = (line_counter + 1) & line_counter_mask;
                line_address = (line_address + ((k.rowcol && (mode_control & 4)) ? 0x100 : horiz_disp)) & 0x3fff;
                if (match_line()) new_vsync = true;
            } else
                raster_counter = (k.il_fleet && MODE_INTERLACE_AND_VIDEO()) ? next_raster()
                                 : (raster_counter + (field_raster ? 2 : 1)) & 0x1f;
            if (adjust_active) {
                if (adjust_counter == vert_total_adj) {
                    frame_ends++;
                    frame_restart(new_vsync);
                    restarted = true;
                } else
                    adjust_counter = (adjust_counter + 1) & 0x1f;
            }
        }
        if (k.vma_row0 && line_counter == 0 && (lc_was == 0 || restarted)) line_address = disp_start_addr;
        if (k.r6z && vert_disp == 0) line_enable_ff = false;
        bool de_v = line_enable_ff;
        if (k.de_fleet) de_v = line_counter < vert_disp && !adjust_active;
        if (de_v) {
            de_off_at = horiz_disp;
            bool vis;
            if (k.cursor_line || k.cursor_fleet) {
                bool keep = line_enable_ff;
                line_enable_ff = de_v;
                vis = cursor_this_line();
                line_enable_ff = keep;
            } else
                vis = check_cursor_visible(raster_counter, line_address);
            if (vis) { cursor_x = cursor_addr - line_address; cur_on_at = cursor_x; }
        } else if (k.cursor_line) {
            cursor_this_line();          // the line latch runs on every line
        }
        row_end = is_row_end();
        hsync_on_at = horiz_sync_pos;
        line_len = horiz_char_total + 1;
        if (k.vs_hdl) {
        } else if (k.vs_r2) {
            // the fleet evaluates VSYNC only at character R2: no R2 on this line = VSYNC state frozen
            if (horiz_sync_pos < line_len) vs_pending = new_vsync ? 1 : 0;
            else { vs_pending = -1; vsync_ff = vs_was; vsync_width_counter = vs_cnt_was; vsync = vsync_was; }
        } else
            on_set_vsync(new_vsync);
        set_de((de_v && !(k.r1z_no_de && horiz_disp == 0)) ? 1 : 0);
        line_de = de_v;
    }
    bool line_de = false;
    bool hs_state = false, vs_state = false;
    int hs_cnt = 0, vs_cnt = 0;
    void set_de(int s) {
        if (de != s) {
            de = s;
            if (de) upd_left = -1;
            else if (!update_ready_bit) update_upd_adr_timer();
        }
    }
    void fire_hsync_on() {
        hsync_on_at = -1;
        int w = sync_width & 0x0f;
        if (k.hsw0_none && w == 0) return;
        if (k.hs_cont && hsync) return;
        hsync = 1;
        hsync_off_left = w ? w : 0x10;
    }

    struct Out { uint16_t ma; uint8_t ra; int de, hs, vs, cur, ustb; };
    Out step() {
        upd_strobe = false;
        if (started && char_counter >= line_len) {
            if (hsync_on_at == char_counter && !k.hs_strict) fire_hsync_on();
            line_timer();
            de_off_pending = de_off_at;
        }
        if (k.hs_cont) {
            int w = sync_width & 15;
            bool act = char_counter == horiz_sync_pos || hs_state;
            bool nhs = k.hsw0_none ? (act && hs_cnt != w) : (act && !(hs_state && hs_cnt == w));
            hs_cnt = act ? ((hs_cnt + 1) & 15) : 0;
            hs_state = nhs; hsync = nhs;
            hsync_on_at = -1; hsync_off_left = -1;
        }
        if (k.vs_hdl && char_counter == (k.vs_r2 ? horiz_sync_pos : 0)) {
            int w = vsw_supported() ? (sync_width >> 4) & 15 : 0;
            bool act = (line_counter == vert_sync_pos && raster_counter == 0) || vs_state;
            bool nvs = act && !(vs_state && vs_cnt == w);
            vs_cnt = act ? ((vs_cnt + 1) & 15) : 0;
            vs_state = nvs; vsync = nvs;
        }
        if (hsync_off_left == 0) { hsync = 0; hsync_off_left = -1; }
        if (de_off_pending >= 0 && char_counter == de_off_pending) { set_de(0); de_off_pending = -1; }
        if (cur_off_left == 0) { cur = 0; cur_off_left = -1; }
        if (cur_on_at >= 0 && char_counter == cur_on_at) { cur = 1; cur_on_at = -1; cur_off_left = 1; }
        if (hsync_on_at >= 0 && char_counter == hsync_on_at) fire_hsync_on();
        if (k.vs_r2 && vs_pending >= 0 && char_counter == horiz_sync_pos) { vsync = vs_pending; vs_pending = -1; }
        if (lp_left == 0) { light_pen_addr = (line_address + char_counter) & 0x3fff; light_pen_latched = true; lp_left = -1; }
        if (upd_left == 0) {
            upd_left = -1;
            upd_strobe = true; upd_strobe_addr = update_addr;           // adr_update_tick -> callback
            if (!update_ready_bit && MODE_TRANSPARENT_BLANK()) { update_addr = (update_addr + 1) & 0x3fff; update_ready_bit = true; }
        }
        Out o{(uint16_t)((line_address + char_counter) & 0x3fff), raster_counter, de, hsync, vsync, cur, upd_strobe};
        char_counter++;
        if (hsync_off_left > 0) hsync_off_left--;
        if (cur_off_left > 0) cur_off_left--;
        if (lp_left > 0) lp_left--;
        if (upd_left > 0) upd_left--;
        return o;
    }
    void assert_light_pen_input() {
        lp_left = k.lp_now ? 0 : 1;
    }
    // Start exactly at a frame restart, lined up with the HDL leaving reset at row 0 / line 0 / character 0.
    void init_at_frame_start() {
        bool nv = false;
        vsync_ff = 0; vsync = 0; vs_block = false;
        frame_restart(nv);
        if (k.first_off) line_enable_ff = false;
        if (k.first_ma0) line_address = 0;
        frames = 0;
        char_counter = 0; cursor_x = -1; de_off_at = -1; cur_on_at = -1; cur_carry = false; cur_latch = false;
        if (k.r6z && vert_disp == 0) line_enable_ff = false;
        bool de_v = line_enable_ff;
        if (k.de_fleet) de_v = line_counter < vert_disp;
        if (k.first_off) de_v = false;
        if (de_v) {
            de_off_at = horiz_disp;
            bool vis;
            if (k.cursor_line || k.cursor_fleet) vis = cursor_this_line();
            else vis = check_cursor_visible(raster_counter, line_address);
            if (vis) { cursor_x = cursor_addr - line_address; cur_on_at = cursor_x; }
        } else if (k.cursor_line) cursor_this_line();
        row_end = is_row_end();
        hsync_on_at = horiz_sync_pos; line_len = horiz_char_total + 1;
        if (k.vs_r2) {
            vs_pending = (horiz_sync_pos < line_len) ? (nv ? 1 : 0) : -1;
            vsync = 0;
            if (vs_pending < 0) { vsync_ff = 0; vsync_width_counter = 0; }
        }
        else vsync = nv;
        de = (de_v && !(k.r1z_no_de && horiz_disp == 0)) ? 1 : 0; line_de = de_v; hsync = 0; cur = 0;
        hs_state = vs_state = false; hs_cnt = vs_cnt = 0;
        if (k.vs_hdl) vsync = 0;
        de_off_pending = de_off_at; started = true;
        if (!de && !update_ready_bit) update_upd_adr_timer();
    }
};
