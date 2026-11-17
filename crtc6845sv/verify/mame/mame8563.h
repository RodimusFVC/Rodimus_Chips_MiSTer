// Transliteration of MAME src/devices/video/mos8563.cpp (Curt Coder; BSD-3-Clause), md5 ed1577f0ebf9ac2759c9e116b05ea417
// (mamedev/mame master, fetched 2026-10-29), on top of the mc6845 base model in mame6845.h.
// Register file, read-back masks, status, R31 data port, block copy / fill (one byte per character clock),
// update_char_width, update_cursor_state (character blink), frame_start / set_vsync (start-address latch),
// reload_draw_counters / advance_draw_line / start_draw_line and draw_row follow MAME in logic and order.
// Omitted: screen geometry / bitmap weaving (MAME's monitor model). Each line is rendered when it starts, into
// `line_pix` (the R1 x cth pixels of the display window, colour indices 0-15), which is what draw_row would paint
// for that line given unchanged registers and video RAM.
#pragma once
#include "mame6845.h"
#include <algorithm>
#include <vector>

// Documentation knobs (C128 PRG + VICE agree against MAME); all off = MAME.
struct VdcKnobs {
    bool r5e0 = false;          // R5 reads back with bits 7:5 set (MAME: bit 5 reads 0)
    bool cursor_vice = false;   // cursor on lines R10 .. R11-1, start = end: that line, start > end wraps (MAME: R11 inclusive, mc6845 rules)
    bool blink_fast = false;    // cursor and character blink toggle every 8 / 16 frames (MAME: 16 / 32)
};

struct MameVdc : Mame6845 {
    VdcKnobs kv;
    uint8_t vram[0x10000];
    uint16_t attribute_addr = 0;
    uint8_t horiz_char = 0x78, vert_char_disp = 0, vert_scroll = 0, horiz_scroll = 0, color = 0, row_addr_incr = 0,
            char_base_addr = 0, underline_ras = 0, word_count = 0, data = 0, de_begin = 0, de_end = 0, dram_refresh = 0,
            sync_polarity = 0;
    uint16_t block_addr = 0;
    int revision = 1;
    bool char_blink_state = false;
    uint8_t char_blink_count = 0;
    uint8_t draw_ra = 0, draw_row_ra = 0;
    uint16_t draw_row = 0, draw_addr = 0, attr_row_addr = 0, bitmap_addr = 0;
    bool frame_started = false;
    int32_t line_index = 0;
    uint16_t latched_disp_addr = 0, latched_attr_addr = 0, frame_disp_addr = 0, frame_attr_addr = 0;
    bool start_addr_latched = false;
    int block_left = -1;                   // block_copy_timer, in character clocks
    // output of the last start_draw_line
    bool line_shown = false;
    int line_idx = 0;
    std::vector<uint8_t> line_pix;
    uint16_t line_addr_rec = 0, line_bitmap_rec = 0, line_attr_rec = 0;
    uint8_t line_ra_rec = 0;

    bool VSS_CBRATE() const { return (vert_scroll >> 5) & 1; }
    bool VSS_RVS() const { return (vert_scroll >> 6) & 1; }
    bool VSS_COPY() const { return (vert_scroll >> 7) & 1; }
    bool HSS_DBL() const { return (horiz_scroll >> 4) & 1; }
    bool HSS_SEMI() const { return (horiz_scroll >> 5) & 1; }
    bool HSS_ATTR() const { return (horiz_scroll >> 6) & 1; }
    bool HSS_BITMAP() const { return (horiz_scroll >> 7) & 1; }

    MameVdc() : Mame6845(M_MC6845) {
        // mos8563_device::device_start
        line_counter_mask = 0xff;
        interlace_fields = true;
        latch_row_end = true;
        supports_vert_sync_width = true;
        status_d5 = status_d6 = status_d7 = true;
        update_ready_bit = 1;
        uint8_t d = 0xff;
        for (int i = 0; i < 0x10000; i++) { vram[i] = d; d ^= 0xff; }
    }
    void device_reset() { Mame6845::device_reset(); sync_polarity = 0xc0; }

    uint32_t vram_address(uint32_t off) const {
        if ((char_base_addr >> 4) & 1) return off & 0xffff;
        return (off & 0x80ff) | ((off & 0x3f00) << 1) | (off & 0x0100);
    }
    uint8_t read_videoram(uint32_t off) const { return vram[vram_address(off)]; }
    void write_videoram(uint32_t off, uint8_t v) { vram[vram_address(off)] = v; }

    void address_w8563(uint8_t d) { register_address_latch = d & 0x3f; }
    uint8_t status_r8563() const {
        uint8_t r = revision;
        if (!line_enable_ff) r |= 0x20;
        if (light_pen_latched) r |= 0x40;
        if (update_ready_bit) r |= 0x80;
        return r;
    }
    uint8_t register_r8563() {
        uint8_t r = 0xff;
        switch (register_address_latch) {
        case 0x00: r = horiz_char_total; break;
        case 0x01: r = horiz_disp; break;
        case 0x02: r = horiz_sync_pos; break;
        case 0x03: r = sync_width; break;
        case 0x04: r = vert_char_total; break;
        case 0x05: r = vert_total_adj | (kv.r5e0 ? 0xe0 : 0xc0); break;
        case 0x06: r = vert_disp; break;
        case 0x07: r = vert_sync_pos; break;
        case 0x08: r = mode_control | 0xfc; break;
        case 0x09: r = max_ras_addr | 0xe0; break;
        case 0x0a: r = cursor_start_ras | 0x80; break;
        case 0x0b: r = cursor_end_ras | 0xe0; break;
        case 0x0c: r = disp_start_addr >> 8; break;
        case 0x0d: r = disp_start_addr & 0xff; break;
        case 0x0e: r = cursor_addr >> 8; break;
        case 0x0f: r = cursor_addr & 0xff; break;
        case 0x10: r = light_pen_addr >> 8; light_pen_latched = false; break;
        case 0x11: r = light_pen_addr & 0xff; light_pen_latched = false; break;
        case 0x12: r = update_addr >> 8; break;
        case 0x13: r = update_addr & 0xff; break;
        case 0x14: r = attribute_addr >> 8; break;
        case 0x15: r = attribute_addr & 0xff; break;
        case 0x16: r = horiz_char; break;
        case 0x17: r = vert_char_disp | 0xe0; break;
        case 0x18: r = vert_scroll; break;
        case 0x19: r = horiz_scroll; break;
        case 0x1a: r = color; break;
        case 0x1b: r = row_addr_incr; break;
        case 0x1c: r = char_base_addr | 0x0f; break;
        case 0x1d: r = underline_ras | 0xe0; break;
        case 0x1e: r = word_count; break;
        case 0x1f: r = read_videoram(update_addr); update_addr++; break;
        case 0x20: r = block_addr >> 8; break;
        case 0x21: r = block_addr & 0xff; break;
        case 0x22: r = de_begin; break;
        case 0x23: r = de_end; break;
        case 0x24: r = dram_refresh | 0xf0; break;
        case 0x25: r = sync_polarity | 0x3f; break;
        }
        return r;
    }
    void register_w8563(uint8_t d) {
        switch (register_address_latch) {
        case 0x00: horiz_char_total = d; break;
        case 0x01: horiz_disp = d; break;
        case 0x02: horiz_sync_pos = d; break;
        case 0x03: sync_width = d; break;
        case 0x04: vert_char_total = d; break;
        case 0x05: vert_total_adj = d & 0x1f; break;
        case 0x06: vert_disp = d; break;
        case 0x07: vert_sync_pos = d; break;
        case 0x08: mode_control = d & 0x03; break;
        case 0x09: max_ras_addr = d & 0x1f; break;
        case 0x0a: cursor_start_ras = d & 0x7f; break;
        case 0x0b: cursor_end_ras = d & 0x1f; break;
        case 0x0c: disp_start_addr = (d << 8) | (disp_start_addr & 0x00ff); break;
        case 0x0d: disp_start_addr = d | (disp_start_addr & 0xff00); break;
        case 0x0e: cursor_addr = (d << 8) | (cursor_addr & 0x00ff); break;
        case 0x0f: cursor_addr = d | (cursor_addr & 0xff00); break;
        case 0x12: update_addr = (d << 8) | (update_addr & 0x00ff); break;
        case 0x13: update_addr = d | (update_addr & 0xff00); break;
        case 0x14: attribute_addr = (d << 8) | (attribute_addr & 0x00ff); break;
        case 0x15: attribute_addr = d | (attribute_addr & 0xff00); break;
        case 0x16: horiz_char = d; break;
        case 0x17: vert_char_disp = d & 0x1f; break;
        case 0x18: vert_scroll = d; break;
        case 0x19: horiz_scroll = d; break;
        case 0x1a: color = d; break;
        case 0x1b: row_addr_incr = d; break;
        case 0x1c: char_base_addr = d & 0xf0; break;
        case 0x1d: underline_ras = d & 0x1f; break;
        case 0x1e: word_count = d; update_ready_bit = 0; block_left = 1; break;
        case 0x1f: data = d; write_videoram(update_addr, data); update_addr++; break;
        case 0x20: block_addr = (d << 8) | (block_addr & 0x00ff); break;
        case 0x21: block_addr = d | (block_addr & 0xff00); break;
        case 0x22: de_begin = d; break;
        case 0x23: de_end = d; break;
        case 0x24: dram_refresh = d & 0x0f; break;
        case 0x25: sync_polarity = d & 0xc0; break;
        }
    }
    void block_copy_tick() {
        uint8_t v = VSS_COPY() ? read_videoram(block_addr++) : data;
        write_videoram(update_addr++, v);
        if (--word_count) block_left = 1;
        else { update_ready_bit = 1; block_left = -1; }
    }

    void cursor_state_hook() override {
        if (kv.blink_fast) {
            uint8_t last = cursor_blink_count;
            cursor_blink_count++;
            switch (cursor_start_ras & 0x60) {
            case 0x00: cursor_state = true; break;
            case 0x20: cursor_state = false; break;
            case 0x40: if ((last & 0x08) != (cursor_blink_count & 0x08)) cursor_state = !cursor_state; break;
            default:   if ((last & 0x10) != (cursor_blink_count & 0x10)) cursor_state = !cursor_state; break;
            }
            uint8_t lc = char_blink_count;
            char_blink_count++;
            if (VSS_CBRATE()) { if ((lc & 0x10) != (char_blink_count & 0x10)) char_blink_state = !char_blink_state; }
            else { if ((lc & 0x08) != (char_blink_count & 0x08)) char_blink_state = !char_blink_state; }
            return;
        }
        update_cursor_state();
        uint8_t last = char_blink_count;
        char_blink_count++;
        if (VSS_CBRATE()) { if ((last & 0x20) != (char_blink_count & 0x20)) char_blink_state = !char_blink_state; }
        else { if ((last & 0x10) != (char_blink_count & 0x10)) char_blink_state = !char_blink_state; }
    }
    bool interlace_video() const { return (mode_control & 3) == 3; }
    void on_frame_start() override {
        frame_started = true;
        line_index = -1;
        frame_disp_addr = start_addr_latched ? latched_disp_addr : disp_start_addr;
        frame_attr_addr = start_addr_latched ? latched_attr_addr : attribute_addr;
        start_addr_latched = false;
    }
    void on_set_vsync(int state) override {
        vsync = state;
        if (!line_enable_ff && !start_addr_latched) {
            latched_disp_addr = disp_start_addr;
            latched_attr_addr = attribute_addr;
            start_addr_latched = true;
        }
        start_draw_line();
    }
    void reload_draw_counters() {
        int f = interlace_video() ? field : 0;
        draw_ra = ((vert_scroll & 0x1f) + f) & 0x1f;
        draw_row_ra = f;
        draw_row = 0;
        draw_addr = frame_disp_addr;
        if (!(f && HSS_BITMAP())) {
            if (interlace_video() && HSS_BITMAP())
                attr_row_addr = frame_attr_addr - (horiz_disp + row_addr_incr);
            else
                attr_row_addr = frame_attr_addr - ((vert_char_total == 0xff) ? horiz_disp : 0);
            bitmap_addr = draw_addr + (vert_scroll & 0x1f) * (horiz_disp + row_addr_incr);
        }
    }
    void advance_draw_line() {
        bool il = interlace_video();
        uint8_t ra = draw_ra;
        bitmap_addr = (bitmap_addr + horiz_disp + row_addr_incr) & 0xffff;
        if (il ? ((ra >= max_ras_addr) || ((ra + 1) == max_ras_addr)) : (ra == max_ras_addr)) {
            draw_ra = il ? (~(ra ^ max_ras_addr) & 1) : 0;
            draw_addr = (draw_addr + horiz_disp + row_addr_incr) & 0xffff;
            attr_row_addr = (attr_row_addr + horiz_disp + row_addr_incr) & 0xffff;
        } else
            draw_ra = (ra + (il ? 2 : 1)) & 0x1f;
        if (il ? ((draw_row_ra >= max_ras_addr) || ((draw_row_ra + 1) == max_ras_addr)) : (draw_row_ra == max_ras_addr)) {
            draw_row_ra = il ? (~(draw_row_ra ^ max_ras_addr) & 1) : 0;
            draw_row++;
        } else
            draw_row_ra = (draw_row_ra + (il ? 2 : 1)) & 0x1f;
    }
    uint64_t lines_started = 0;
    void start_draw_line() {
        lines_started++;
        line_index++;
        if (!line_index) reload_draw_counters();
        bool shown = draw_row < vert_disp;
        line_idx = line_index;
        line_shown = shown;
        line_addr_rec = draw_addr; line_bitmap_rec = bitmap_addr; line_attr_rec = attr_row_addr; line_ra_rec = draw_ra;
        render_line();
        if (shown) advance_draw_line();
        else {
            bool extra_row = interlace_video() && (vert_disp < vert_char_total) && (draw_row == vert_disp);
            bool row_last_line = (draw_row_ra >= max_ras_addr) || ((draw_row_ra + 1) == max_ras_addr);
            if (extra_row && !row_last_line) advance_draw_line();
        }
    }

    static int displayed_width(uint8_t r22) {
        int total = r22 >> 4, disp = r22 & 0x0f;
        if (total < 8) return (disp < total) ? (disp + 1) : (disp == total) ? 0 : (total + 1);
        else if (disp < 7) return std::min(8, disp + total - 6);
        else if (disp == 7) return 0;
        else return (disp <= total) ? (disp - 7) : 8;
    }
    static bool semigraphics_gap(uint8_t r22) {
        int total = r22 >> 4, disp = r22 & 0x0f;
        return (total >= 7) && (((disp < 8) && (disp + total <= 14)) || ((disp >= 8) && (disp <= total)));
    }
    int cth() const { return (horiz_char >> 4) + (HSS_DBL() ? 0 : 1); }
    // draw_line + draw_row for the line just started: fills line_pix, or leaves it empty when MAME paints border only
    void render_line() {
        line_pix.clear();
        if (!line_shown) return;
        bool blank = ((de_begin > horiz_char_total) || (de_begin == de_end)) && (de_end <= horiz_char_total);
        if (blank) return;
        uint16_t addr = line_addr_rec;
        uint8_t ra = line_ra_rec;
        bool cv;
        if (kv.cursor_vice) {
            uint8_t cs = cursor_start_ras & 0x1f, ce = cursor_end_ras;
            bool rows = (cs == ce) ? (ra == cs) : (cs < ce) ? (ra >= cs && ra < ce) : (ra >= cs || ra < ce);
            cv = cursor_state && !(cursor_addr < addr || cursor_addr >= addr + horiz_disp) && rows;
        } else
            cv = check_cursor_visible(ra, addr);
        int cursor_x = cv ? (int8_t)(cursor_addr - addr) : -1;
        uint16_t ma = HSS_BITMAP() ? line_bitmap_rec : addr;
        uint16_t attr_row = line_attr_rec;
        int x_count = horiz_disp;
        int c = cth();
        uint8_t cdv = vert_char_disp;
        if ((horiz_scroll & 0x0f) + HSS_DBL() > (horiz_char >> 4)) return;
        uint8_t r22 = horiz_char;
        if (HSS_DBL() && !((r22 >> 3) & 1) && (r22 >= 0x10)) r22 -= 0x10;
        int displayed = displayed_width(r22);
        uint8_t semi_test = 0, semi_type = 0;
        bool semi_forced = HSS_DBL() && ((horiz_char >> 4) == (horiz_char & 0x0f));
        if (HSS_SEMI() || semi_forced) {
            if (semi_forced) { if ((horiz_char & 0x0f) <= 8) displayed = 1; }
            else if (!displayed) displayed = 8;
            semi_test = 0x80 >> (displayed - 1);
            semi_type = semigraphics_gap(r22) ? 0xff : 0x00;
        }
        uint8_t dmask = ~(0xff >> std::min(displayed, 8));
        int gap_total = (horiz_char >> 4) - 6;
        uint8_t d2mask = (gap_total > (HSS_DBL() ? 2 : 1)) ? (uint8_t)~(0xff >> std::min(gap_total, 8)) : 0x00;
        line_pix.assign(x_count * c, color & 0x0f);
        for (int column = 0; column <= x_count; column++) {
            uint8_t code = read_videoram((ma + column) & 0xffff);
            uint8_t attr = 0;
            int fg = color >> 4, bg = color & 0x0f;
            if (HSS_ATTR()) attr = read_videoram((attr_row + column) & 0xffff);
            uint8_t d, gap = 0;
            if (HSS_BITMAP()) {
                if (HSS_ATTR()) { fg = attr & 0x0f; bg = attr >> 4; }
                d = (ra > cdv) ? 0 : code;
                d &= dmask;
                if (d & semi_test) { d |= semi_test - 1; gap = semi_type; }
            } else {
                if (HSS_ATTR()) fg = attr & 0x0f;
                uint32_t font_addr;
                int alt = (attr >> 7) & 1;
                if (max_ras_addr < 16) font_addr = ((char_base_addr & 0xe0) << 8) + (alt << 12) + (code << 4) + ra;
                else font_addr = ((char_base_addr & 0xc0) << 8) + (alt << 13) + (code << 5) + ra;
                d = (ra > cdv) ? 0 : read_videoram(font_addr);
                d &= dmask;
                if (((attr >> 5) & 1) && (ra == underline_ras)) { d = 0xff; gap = 0xff; }
                if (((attr >> 4) & 1) && !char_blink_state) { d = 0; gap = 0; }
                if (d & semi_test) { d |= semi_test - 1; gap = semi_type; }
                if ((attr >> 6) & 1) { d ^= 0xff; gap ^= 0xff; }
                if (column == cursor_x) { d ^= 0xff; gap ^= 0xff; }
            }
            if (VSS_RVS()) { d ^= 0xff; gap ^= 0xff; }
            gap &= d2mask;
            for (int bit = 0; bit < c; bit++) {
                int x = (horiz_scroll & 0x0f) - c + 1 + (column * c) + bit;
                int col = (((bit < 8) ? d : gap) >> (7 - (bit & 7))) & 1 ? fg : bg;
                if (x >= 0 && x < x_count * c) line_pix[x] = col;
            }
        }
    }
    // one character clock: block copy timer, then the base model's character step
    Out step_vdc() {
        Out o = step();
        if (block_left > 0 && --block_left == 0) block_copy_tick();
        return o;
    }
};
