// pit_ref.h — C++ transcription of MAME devices/machine/pit8253.cpp (pit_counter_device / pit8253_device /
// pit8254_device), license BSD-3-Clause, copyright-holders Wilbert Pol, Nathan Woods.
//
// Source md5s at transcription time (MAME src/devices/machine/):
//   pit8253.cpp 670d97ffb5302834e4cacdb85b41515a    pit8253.h c86d086159ce35d1d5a14ccbf2c13924
//
// What is transcribed: every function that touches counter state, line for line (adjusted_count,
// decrease_counter_value, load_counter_value, set_output, flush_output, simulate, masked_value, read, load_count,
// readback, readback_command, control_w / count_w / gate_w / set_clock_signal bodies, device_reset).
// What is not: the scheduler. MAME defers each bus / gate / clock event with machine().scheduler().synchronize();
// here the event body is called directly. The board clocks every counter through write_clkN (m_clockin == 0), so
// update() / adjust_timer() / the emu_timer / attotime are dead code (update() only sets m_last_updated) and are left
// out; the m_clockin tests stay in the transcribed code. The cycles_to_output bookkeeping in simulate() only feeds
// adjust_timer() and is dropped. Logging is dropped. The FE2010 branches are dropped (not part of this chip).
// Nothing here is shaped to agree with the RTL.
// DATASHEET deviation (Intel 8253 datasheet 231306-001, 2026-11-15; the RTL implements the same, see its header):
//   rule 2 here (m_cnt_wr): modes 2 / 3 start on a GATE rise only once a count was written since the mode word
//   (3-55: the output remains high until the count register is loaded). MAME starts from the stale count.
//   Rule 1 (a write on a CLK cycle reaches the counter after that cycle) is bench event ordering: tb_pit8253.cpp.
#pragma once
#include <cstdint>

enum class pit_type { I8254, I8253 };

#define CTRL_ACCESS(control)        (((control) >> 4) & 0x03)
#define CTRL_MODE(control)          (((control) >> 1) & (((control) & 0x04) ? 0x03 : 0x07))
#define CTRL_BCD(control)           (((control) >> 0) & 0x01)

struct pit_counter_ref
{
    pit_type m_type = pit_type::I8253;
    int      m_index = 0;
    double   m_clockin = 0;           // CLK driven through write_clkN
    int      m_clock_signal = 0;

    uint16_t m_value = 0, m_latch = 0, m_count = 0;
    uint8_t  m_control = 0x30, m_status = 0x30, m_lowcount = 0;
    bool     m_rmsb = false, m_wmsb = false;
    int      m_output = 0, m_output_pin = 0;
    int      m_gate = 1, m_gate_input = 1, m_gate_rose = 0;
    int      m_latched_count = 0, m_latched_status = 0, m_null_count = 1, m_phase = 0;
    int      m_cnt_wr = 0;            // DATASHEET rule 2: count written since the last mode word

    // device_start() zerofill + device_reset()
    void reset()
    {
        m_gate = 1; m_gate_input = 1; m_gate_rose = 0; m_phase = 0; m_clock_signal = 0; m_cnt_wr = 0;
        m_control = m_status = 0x30;
        m_rmsb = m_wmsb = false;
        m_count = m_value = m_latch = 0;
        m_lowcount = 0;
        m_output = 2; /* output is undetermined */
        m_output_pin = 2;
        m_latched_count = 0;
        m_latched_status = 0;
        m_null_count = 1;
    }

    inline uint32_t adjusted_count() const
    {
        uint16_t val = m_value;
        if (!CTRL_BCD(m_control))
            return (val == 0) ? 0x10000 : val;
        else if (val == 0)
            return 10000;
        return
            ((val>>12) & 0xF) *  1000 +
            ((val>> 8) & 0xF) *   100 +
            ((val>> 4) & 0xF) *    10 +
            ( val      & 0xF);
    }

    void decrease_counter_value(int64_t cycles)
    {
        if (CTRL_BCD(m_control) == 0)
        {
            m_value -= (cycles & 0xffff);
            return;
        }

        uint8_t units     =  m_value        & 0xf;
        uint8_t tens      = (m_value >>  4) & 0xf;
        uint8_t hundreds  = (m_value >>  8) & 0xf;
        uint8_t thousands = (m_value >> 12) & 0xf;

        if (cycles <= units)
        {
            units -= cycles;
        }
        else
        {
            cycles -= units;
            units = (10 - cycles % 10) % 10;

            cycles = (cycles + 9) / 10; /* the +9 is so we get a carry if cycles%10 wasn't 0 */
            if (cycles <= tens)
            {
                tens -= cycles;
            }
            else
            {
                cycles -= tens;
                tens = (10 - cycles % 10) % 10;

                cycles = (cycles + 9) / 10;
                if (cycles <= hundreds)
                {
                    hundreds -= cycles;
                }
                else
                {
                    cycles -= hundreds;
                    hundreds = (10 - cycles % 10) % 10;
                    cycles = (cycles + 9) / 10;
                    thousands = (10 + thousands - cycles % 10) % 10;
                }
            }
        }

        m_value = (thousands << 12) | (hundreds << 8) | (tens << 4) | units;
    }

    void load_counter_value()
    {
        m_value = m_count;
        m_null_count = 0;
    }

    void flush_output()
    {
        int new_output = m_output;
        if (m_clockin == 0)
        {
            const int mode = CTRL_MODE(m_control);
            if ((mode == 2 || mode == 3) && m_gate_input == 0)
                new_output = 1;
        }

        if (new_output != m_output_pin)
            m_output_pin = new_output;   // m_out_handler[m_index](new_output)
    }

    void set_output(int output)
    {
        if (output != m_output)
        {
            m_output = output;
            flush_output();
        }
    }

    void simulate(int64_t elapsed_cycles)
    {
        uint32_t adjusted_value;
        int mode = CTRL_MODE(m_control);

        switch (mode)
        {
        case 0:
            if (m_phase == 0)
            {
            }
            else
            {
                if (elapsed_cycles >= 0 && m_phase == 1)
                {
                    /* Counter load cycle */
                    if (elapsed_cycles > 0)
                    {
                        --elapsed_cycles;
                        m_phase = 2;
                    }
                    load_counter_value();
                }

                if (m_gate == 0)
                {
                }
                else
                {
                    if (m_phase == 2)
                    {
                        adjusted_value = adjusted_count();
                        if (elapsed_cycles >= adjusted_value)
                        {
                            /* Counter wrapped, output goes high */
                            elapsed_cycles -= adjusted_value;
                            m_phase = 3;
                            m_value = 0;
                            set_output(1);
                        }
                    }

                    decrease_counter_value(elapsed_cycles);
                }
            }
            break;

        case 1:
            if (elapsed_cycles >= 0 && m_phase == 1)
            {
                /* Counter load cycle, output goes low */
                if (elapsed_cycles > 0)
                {
                    --elapsed_cycles;
                    m_phase = 2;
                }
                load_counter_value();
                set_output(0);
            }

            if (m_phase == 2)
            {
                adjusted_value = adjusted_count();
                if (elapsed_cycles >= adjusted_value)
                {
                    /* Counter wrapped, output goes high */
                    m_phase = 3;
                    set_output(1);
                }
            }

            decrease_counter_value(elapsed_cycles);
            break;

        case 2:
            if (m_gate == 0 || m_phase == 0)
            {
                /* Gate low or mode control write forces output high */
                set_output(1);
            }
            else
            {
                if (elapsed_cycles >= 0 && m_phase == 1)
                {
                    if (elapsed_cycles > 0)
                    {
                        --elapsed_cycles;
                        m_phase = 2;
                    }
                    load_counter_value();
                }

                adjusted_value = adjusted_count();

                do
                {
                    if (m_phase == 2)
                    {
                        if (elapsed_cycles + 1 >= adjusted_value)
                        {
                            /* Counter hits 1, output goes low */
                            m_phase = 3;
                            set_output(0);
                        }
                    }

                    if (elapsed_cycles >= adjusted_value && m_phase == 3)
                    {
                        /* Reload counter, output goes high */
                        elapsed_cycles -= adjusted_value;
                        m_phase = 2;
                        load_counter_value();
                        adjusted_value = adjusted_count();
                        set_output(1);
                    }
                }
                while (elapsed_cycles >= adjusted_value);

                /* Calculate counter value */
                decrease_counter_value(elapsed_cycles);
            }
            break;

        case 3:
            if (m_gate == 0 || m_phase == 0)
            {
                /* Gate low or mode control write forces output high */
                set_output(1);
            }
            else
            {
                if (elapsed_cycles >= 0 && m_phase == 1)
                {
                    if (elapsed_cycles > 0)
                    {
                        --elapsed_cycles;
                        m_phase = 2;
                    }
                    load_counter_value();
                }

                if (elapsed_cycles > 0)
                {
                    adjusted_value = adjusted_count();

                    do
                    {
                        if (m_phase == 2 && elapsed_cycles >= ((adjusted_value + 1) >> 1))
                        {
                            /* High phase expired, output goes low */
                            elapsed_cycles -= ((adjusted_value + 1) >> 1);
                            m_phase = 3;
                            load_counter_value();
                            adjusted_value = adjusted_count();
                            set_output(0);
                        }

                        if (m_phase == 3 && elapsed_cycles >= (adjusted_value >> 1))
                        {
                            /* Low phase expired, output goes high */
                            elapsed_cycles -= (adjusted_value >> 1);
                            m_phase = 2;
                            load_counter_value();
                            adjusted_value = adjusted_count();
                            set_output(1);
                        }
                    }
                    while ((m_phase == 2 && elapsed_cycles >= ((adjusted_value + 1) >> 1)) ||
                            (m_phase == 3 && elapsed_cycles >= (adjusted_value >> 1)));

                    decrease_counter_value(elapsed_cycles * 2);
                }
            }
            break;

        case 4:
        case 5:
            if (m_gate == 0 && mode == 4)
            {
            }
            else
            {
                if (elapsed_cycles >= 0 && m_phase == 1)
                {
                    if (elapsed_cycles > 0)
                    {
                        --elapsed_cycles;
                        m_phase = 2;
                    }
                    load_counter_value();
                }

                if (m_value == 0 && m_phase == 2)
                    adjusted_value = 0;
                else
                    adjusted_value = adjusted_count();

                if (m_phase == 2 && elapsed_cycles >= adjusted_value)
                {
                    /* Counter has hit zero, set output to low */
                    elapsed_cycles -= adjusted_value;
                    m_phase = 3;
                    m_value = 0;
                    set_output(0);
                }

                if (elapsed_cycles > 0 && m_phase == 3)
                {
                    --elapsed_cycles;
                    m_phase = 0;
                    decrease_counter_value(1);
                    set_output(1);
                }

                decrease_counter_value(elapsed_cycles);
            }
            break;
        }
    }

    uint16_t masked_value() const
    {
        if (CTRL_MODE(m_control) == 3)
            return m_value & 0xfffe;
        return m_value;
    }

    // side_effects = false is MAME's machine().side_effects_disabled() (a peek)
    uint8_t read(bool side_effects = true)
    {
        uint8_t data;

        if (m_latched_status)
        {
            data = m_status;
            if (side_effects)
                m_latched_status = 0;
        }
        else
        {
            if (m_latched_count != 0)
            {
                data = (m_latch >> (m_rmsb ? 8 : 0)) & 0xff;
                if (side_effects)
                {
                    m_rmsb = !m_rmsb;
                    --m_latched_count;
                }
            }
            else
            {
                uint16_t value = masked_value();

                switch (CTRL_ACCESS(m_control))
                {
                case 0:
                default:
                    data = 0;
                    break;

                case 1:
                    data = (value >> 0) & 0xff;
                    break;

                case 2:
                    data = (value >> 8) & 0xff;
                    break;

                case 3:
                    if (m_wmsb)
                        data = ~m_lowcount;
                    else
                        data = value >> (m_rmsb ? 8 : 0);

                    if (side_effects)
                        m_rmsb = !m_rmsb;
                    break;
                }
            }
        }
        return data;
    }

    void load_count(uint16_t newcount)
    {
        int mode = CTRL_MODE(m_control);

        if (newcount == 1)
        {
            if (mode == 2)
                newcount = 2;
            if (mode == 3)
                newcount = 0;
        }

        m_count = newcount;
        m_cnt_wr = 1;                 // DATASHEET rule 2

        if (mode == 2 || mode == 3)
        {
            if (m_phase == 0)
                m_phase = 1;
        }
        else
        {
            if (mode == 0 || mode == 4)
                m_phase = 1;
        }
    }

    void readback(int command)
    {
        if ((command & 1) == 0)
        {
            /* readback status command */
            if (!m_latched_status)
            {
                m_status = (m_control & 0x3f) | ((m_output != 0) ? 0x80 : 0) | (m_null_count ? 0x40 : 0);
                m_latched_status = 1;
            }
        }

        if ((command & 2) == 0 && !m_rmsb)
        {
            /* readback count command */
            if (m_latched_count == 0)
            {
                uint16_t value = masked_value();
                switch (CTRL_ACCESS(m_control))
                {
                case 0:
                    break;

                case 1:
                    m_latch = ((value << 8) & 0xff00) | (value & 0xff);
                    m_latched_count = 1;
                    break;

                case 2:
                    m_latch = (value & 0xff00) | ((value >> 8) & 0xff);
                    m_latched_count = 1;
                    break;

                case 3:
                    m_latch = value;
                    m_latched_count = 2;
                    break;
                }
            }
        }
    }

    // control_w_deferred
    void control_w(uint8_t data)
    {
        if (CTRL_ACCESS(data) == 0)
        {
            readback(1);
        }
        else
        {
            m_control = (data & 0x3f);
            m_null_count = 1;
            m_wmsb = m_rmsb = false;
            m_cnt_wr = 0;             // DATASHEET rule 2
            /* Phase 0 is always the phase after a mode control write */
            m_phase = 0;
            set_output(CTRL_MODE(m_control) ? 1 : 0);
        }
    }

    // count_w_deferred (middle_of_a_cycle is false while m_clockin == 0)
    void count_w(uint8_t data)
    {
        switch (CTRL_ACCESS(m_control))
        {
        case 0:
            break;

        case 1:
            load_count(data);
            if (m_clockin != 0)
                simulate(0);

            if (CTRL_MODE(m_control) == 0)
                set_output(0);
            break;

        case 2:
            load_count(data << 8);
            if (m_clockin != 0)
                simulate(0);

            if (CTRL_MODE(m_control) == 0)
                set_output(0);
            break;

        case 3:
            if (m_wmsb)
            {
                load_count(m_lowcount | (data << 8));
                if (m_clockin != 0)
                    simulate(0);
            }
            else
            {
                m_lowcount = data;
                if (CTRL_MODE(m_control) == 0)
                {
                    m_phase = 0;
                    set_output(0);
                }
            }
            m_wmsb = !m_wmsb;
            break;
        }
    }

    bool edge_sensitive_gate() const
    {
        const int mode = CTRL_MODE(m_control);
        return mode == 1 || mode == 2 || (mode == 3 && m_clockin == 0) || mode == 5;
    }

    // gate_w_deferred
    void gate_w(int state)
    {
        if (state != m_gate_input)
        {
            m_gate_input = state;
            if (m_clockin != 0)
                m_gate = state;
            if (state != 0 && edge_sensitive_gate())
            {
                if (m_clockin != 0)
                    m_phase = 1;
                else
                    m_gate_rose = 1;
            }
            if (m_clockin == 0)
                flush_output();
        }
    }

    // set_clock_signal_deferred
    void set_clock_signal(int state)
    {
        /* Sample GATE and the GATE edge detection flipflop on low to high transition */
        if (!m_clock_signal && state)
        {
            m_gate = m_gate_input;
            if (m_gate_rose)
            {
                const int mode = CTRL_MODE(m_control);
                if (edge_sensitive_gate() && !((mode == 2 || mode == 3) && !m_cnt_wr))   // DATASHEET rule 2
                    m_phase = 1;
                m_gate_rose = 0;
            }
        }

        /* Trigger on high to low transition */
        if (m_clock_signal && !state)
            simulate(1);
        m_clock_signal = state;
    }
};

struct pit_ref
{
    pit_type m_type;
    pit_counter_ref m_counter[3];

    explicit pit_ref(pit_type t) : m_type(t) { for (int i = 0; i < 3; i++) { m_counter[i].m_index = i; m_counter[i].m_type = t; } }

    void reset() { for (auto &c : m_counter) c.reset(); }

    // pit8254_device::readback_command / pit8253_device::readback_command (does nothing)
    void readback_command(uint8_t data)
    {
        if (m_type != pit_type::I8254)
            return;
        int read_command = (data >> 4) & 3;
        for (int timer = 0; timer < 3; timer++)
            if (((data >> (timer + 1)) & 1) != 0)
                m_counter[timer].readback(read_command);
    }

    uint8_t read(unsigned offset, bool side_effects = true)
    {
        offset &= 3;
        if (offset == 3)
            return 0;
        return m_counter[offset].read(side_effects);
    }

    // one bus write as seen by counter n only (DATASHEET rule 1 holds writes per counter in the bench)
    void write_to(int n, unsigned offset, uint8_t data)
    {
        offset &= 3;
        if (offset == 3)
        {
            int timer = (data >> 6) & 3;
            if (timer == 3)
            {
                if (m_type == pit_type::I8254 && ((data >> (n + 1)) & 1) != 0)
                    m_counter[n].readback((data >> 4) & 3);
            }
            else if (timer == n)
                m_counter[n].control_w(data);
        }
        else if ((int)offset == n)
            m_counter[n].count_w(data);
    }

    void write(unsigned offset, uint8_t data)
    {
        offset &= 3;
        if (offset == 3)
        {
            int timer = (data >> 6) & 3;
            if (timer == 3)
                readback_command(data);
            else
                m_counter[timer].control_w(data);
        }
        else
            m_counter[offset].count_w(data);
    }

    void write_gate(int n, int state) { m_counter[n].gate_w(state); }
    void write_clk(int n, int state)  { m_counter[n].set_clock_signal(state); }
};
