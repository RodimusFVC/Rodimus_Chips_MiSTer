// Minimal cycle-accurate C64 for the test suites (verification only).
// Timing follows C64_MiSTer fpga64_sid_iec: 32 clk32 phases per CPU cycle, VIC-II (GHDL conversion of
// C64_MiSTer video_vicII_656x, PAL 6569), two C64_MiSTer mos6526 CIAs (old 6526), real ROMs.
// `LOCKSTEP: GHDL T65 oracle drives the bus, t65sv_T65 runs beside it, all pins compared every clk32.
// otherwise: t65sv_6510 (core + I/O port wrapper) alone.
module c64_top (
  input  logic        clk32,
  input  logic        reset_n,
  input  logic        cia_new,        // 0: 6526 (old), 1: 8521 (new)
  output logic        cpu_edge,       // the CPU registers update at the end of this clk32
  output logic        cpu_sync,
  output logic [15:0] cpu_addr,
  output logic        cpu_we,
  output logic [7:0]  cpu_do,
  output logic [63:0] cpu_regs,
  output logic        dbg_wr,         // write to $D7FF (debug cartridge register) this clk32
  output logic [7:0]  dbg_val,
  output logic        mismatch,       // LOCKSTEP: any oracle/t65sv pin differs this clk32
  output logic [8:0]  dbg_rasterY     // VIC-II raster line (debug)
);
  // ------------------------------------------------------------- memories
  logic [7:0] ram [0:65535] /* verilator public_flat_rw */;
  logic [7:0] rom [0:16383];       // BASIC $A000 (A14=0) / KERNAL $E000 (A14=1)
  logic [7:0] chr [0:4095];
  logic [3:0] colram [0:1023];
  initial begin
    $readmemh("gen/basic_kernal.hex", rom);
    $readmemh("gen/chargen.hex", chr);
    for (int i = 0; i < 65536; i++) ram[i] = 8'h00;
    for (int i = 0; i < 1024; i++) colram[i] = 4'h0;
  end

  // ------------------------------------------------------------- sequencer (fpga64)
  logic [4:0] sysCycle;
  logic       reset, phi0_cpu, cpuHasBus, enableVic, enableCia_n, enableCia_p, enablePixel;
  logic [1:0] cpu_cyc_s;
  logic       enableCpu, pulseWr_io;
  logic       baLoc, irq_vic, irq_cia1, irq_cia2;
  logic [15:0] cpuAddr;
  logic [7:0]  cpuDo, cpuDi;
  logic        cpuWe;
  logic [2:0]  bankSwitch;

  always_ff @(posedge clk32) begin
    sysCycle <= sysCycle + 5'd1;
    if (sysCycle == 5'd31) reset <= ~reset_n;
    if (sysCycle == 5'd15) begin
      phi0_cpu <= 1'b1;
      if (baLoc || cpuWe) cpuHasBus <= 1'b1;
    end
    if (sysCycle == 5'd31) begin
      phi0_cpu  <= 1'b0;
      cpuHasBus <= 1'b0;
    end
    enableVic   <= (sysCycle == 5'd14) || (sysCycle == 5'd30);
    enableCia_n <= (sysCycle == 5'd28);
    enableCia_p <= (sysCycle == 5'd31);
    enablePixel <= (sysCycle[1:0] == 2'd2);
    cpu_cyc_s   <= {cpu_cyc_s[0], sysCycle == 5'd28};
    enableCpu   <= cpu_cyc_s[1];
    pulseWr_io  <= cpuWe && sysCycle == 5'd28;
  end
  initial begin sysCycle = 0; reset = 1; phi0_cpu = 0; cpuHasBus = 0; cpu_cyc_s = 0; enableCpu = 0; end

  // ------------------------------------------------------------- bus logic (fpga64_buslogic, no cartridge)
  logic cs_ramLoc, cs_romLoc, cs_charLoc, cs_vicLoc, cs_sidLoc, cs_colorLoc, cs_cia1Loc, cs_cia2Loc, cs_ioLoc;
  always_comb begin
    {cs_ramLoc, cs_romLoc, cs_charLoc, cs_vicLoc, cs_sidLoc, cs_colorLoc, cs_cia1Loc, cs_cia2Loc, cs_ioLoc} = '0;
    case (cpuAddr[15:12])
      4'hE, 4'hF: if (!cpuWe && bankSwitch[1]) cs_romLoc = 1'b1; else cs_ramLoc = 1'b1;
      4'hD: begin
        if (!bankSwitch[1] && !bankSwitch[0]) cs_ramLoc = 1'b1;
        else if (bankSwitch[2]) begin
          case (cpuAddr[11:8])
            4'h0, 4'h1, 4'h2, 4'h3: cs_vicLoc = 1'b1;
            4'h4, 4'h5, 4'h6, 4'h7: cs_sidLoc = 1'b1;
            4'h8, 4'h9, 4'hA, 4'hB: cs_colorLoc = 1'b1;
            4'hC: cs_cia1Loc = 1'b1;
            4'hD: cs_cia2Loc = 1'b1;
            default: cs_ioLoc = 1'b1;
          endcase
        end else if (!cpuWe) cs_charLoc = 1'b1;
        else cs_ramLoc = 1'b1;
      end
      4'hA, 4'hB: if (!cpuWe && bankSwitch[1] && bankSwitch[0]) cs_romLoc = 1'b1; else cs_ramLoc = 1'b1;
      default: cs_ramLoc = 1'b1;
    endcase
  end

  logic        cs_vic, cs_cia1, cs_cia2;
  logic [7:0]  vicData, cia1Do, cia2Do, lastVicDi, vicDi, vicBus;
  logic [15:0] vicAddr;
  logic [13:0] vicAddr14;
  logic        aec;
  logic [7:0]  cia1_pao, cia1_pbo, cia2_pao, cia2_pbo, cia2_pbe, cia1_pbe, cia1_pae, cia2_pae;

  assign cs_vic  = cs_vicLoc  & cpuHasBus;
  assign cs_cia1 = cs_cia1Loc & cpuHasBus;
  assign cs_cia2 = cs_cia2Loc & cpuHasBus;

  always_comb begin
    cpuDi = lastVicDi;                        // open bus: last byte the VIC fetched
    if (cs_charLoc)       cpuDi = chr[cpuAddr[11:0]];
    else if (cs_romLoc)   cpuDi = rom[{cpuAddr[14], cpuAddr[12:0]}];
    else if (cs_ramLoc)   cpuDi = ram[cpuAddr];
    else if (cs_vicLoc)   cpuDi = vicData;
    else if (cs_colorLoc) cpuDi = {lastVicDi[7:4], colram[cpuAddr[9:0]]};
    else if (cs_cia1Loc)  cpuDi = cia1Do;
    else if (cs_cia2Loc)  cpuDi = cia2Do;
  end

  // RAM / colour RAM / debug register writes happen with the CPU's edge
  always_ff @(posedge clk32) begin
    if (enableCpu && cpuWe && cpuHasBus) begin
      if (cs_ramLoc) ram[cpuAddr] <= cpuDo;
    end
    if (pulseWr_io && cs_colorLoc && cpuHasBus) colram[cpuAddr[9:0]] <= cpuDo[3:0];
  end
  assign dbg_wr  = pulseWr_io && cs_sidLoc && cpuHasBus && cpuAddr == 16'hD7FF;
  assign dbg_val = cpuDo;

  // ------------------------------------------------------------- VIC-II
  always_ff @(posedge clk32) begin
    if (phi0_cpu) vicBus <= (cpuWe && cs_vic) ? cpuDo : 8'hFF;
    if (sysCycle == 5'd15) lastVicDi <= vicDi;
  end
  assign vicAddr = {~cia2_pao[1:0], vicAddr14};
  assign vicDi   = (vicAddr[14:12] == 3'b001) ? chr[vicAddr[11:0]] : ram[vicAddr];

  logic [7:0] vic_di;
  logic [3:0] vic_dicolor;
  assign vic_di      = aec ? vicDi : vicBus;
  assign vic_dicolor = aec ? colram[vicAddr[9:0]] : cpuDi[3:0];

  video_vicii_656x u_vic (
    .clk(clk32), .phi(phi0_cpu), .enaData(enableVic), .enaPixel(enablePixel), .baSync(1'b0),
    .mode6569(1'b1), .mode6567old(1'b0), .mode6567R8(1'b0), .mode6572(1'b0),
    .turbo_en(1'b0), .variant(2'b00), .reset(reset), .cs(cs_vic), .we(cpuWe), .lp_n(1'b1),
    .aRegisters(cpuAddr[5:0]), .diRegisters(cpuDo), .di(vic_di), .diColor(vic_dicolor),
    .ba(baLoc), .ba_dma(), .turbo_state(), .do_o(vicData), .vicAddr(vicAddr14), .irq_n(irq_vic),
    .hSync(), .vSync(), .colorIndex(), .debugX(), .debugY(dbg_rasterY), .vicRefresh(), .addrValid(aec));

  // ------------------------------------------------------------- CIAs
  // port pins: driven bits read back what the CIA drives (incl. timer outputs on PB6/PB7), others pulled up
  logic todclk;
  logic [15:0] todcnt;
  always_ff @(posedge clk32) begin
    if (reset) begin todclk <= 1'b0; todcnt <= 16'd0; end
    else if (enableCpu) begin
      if (todcnt == 16'd9851) begin todcnt <= 16'd0; todclk <= ~todclk; end
      else todcnt <= todcnt + 16'd1;
    end
  end

  logic [7:0] cia2_pai;
  assign cia2_pai = {~cia2_pao[5], ~cia2_pao[4], 3'b111, 1'b1, 2'b11} & cia2_pao;

  mos6526 u_cia1 (
    .mode(cia_new), .clk(clk32), .phi2_p(enableCia_p), .phi2_n(enableCia_n), .res_n(~reset),
    .cs_n(~cs_cia1), .rw(~cpuWe), .rs(cpuAddr[3:0]), .db_in(cpuDo), .db_out(cia1Do),
    .pa_in(cia1_pao | ~cia1_pae), .pa_out(cia1_pao), .pa_oe(cia1_pae), .pb_in(cia1_pbo | ~cia1_pbe), .pb_out(cia1_pbo), .pb_oe(cia1_pbe),
    .flag_n(1'b1), .pc_n(), .tod(todclk), .sp_in(1'b1), .sp_out(), .cnt_in(1'b1), .cnt_out(),
    .irq_n(irq_cia1));

  mos6526 u_cia2 (
    .mode(cia_new), .clk(clk32), .phi2_p(enableCia_p), .phi2_n(enableCia_n), .res_n(~reset),
    .cs_n(~cs_cia2), .rw(~cpuWe), .rs(cpuAddr[3:0]), .db_in(cpuDo), .db_out(cia2Do),
    .pa_in(cia2_pai), .pa_out(cia2_pao), .pa_oe(cia2_pae), .pb_in(cia2_pbo | ~cia2_pbe), .pb_out(cia2_pbo), .pb_oe(cia2_pbe),
    .flag_n(1'b1), .pc_n(), .tod(todclk), .sp_in(1'b1), .sp_out(), .cnt_in(1'b1), .cnt_out(),
    .irq_n(irq_cia2));

  // ------------------------------------------------------------- CPU
  logic irq_n, nmi_n;
  assign irq_n = irq_cia1 & irq_vic;
  assign nmi_n = irq_cia2;

  // C64 board at the 6510 port: P0-P2, P4 pulled up, P5 (motor) reads 0, P3 (cassette write) floats
  logic [7:0] port_o, port_ddr, port_pi;
  logic       p3_hold;
  always_ff @(posedge clk32) p3_hold <= port_ddr[3] ? port_o[3] : p3_hold;
  assign port_pi    = {2'b11, 1'b0, 1'b1, p3_hold, 3'b111};
  assign bankSwitch = ((port_o & port_ddr) | (port_pi & ~port_ddr)) & 8'h07;

`ifdef LOCKSTEP
  logic [23:0] r_A, d_A;
  logic [7:0]  r_DO, d_DO, di_cpu, port_rd;
  logic        r_RW, d_RW, r_Sync, d_Sync, port_sel;
  logic [63:0] r_Regs, d_Regs;
  logic [47:0] d_DEBUG;
  logic [7:0]  r_dbg [0:5];
  logic        r_EF, r_MF, r_XF, r_ML, r_VP, r_VDA, r_VPA, r_NA;
  logic        d_EF, d_MF, d_XF, d_ML, d_VP, d_VDA, d_VPA, d_NA;

  assign di_cpu = !r_RW ? r_DO : port_sel ? port_rd : cpuDi;

  ref_T65 u_ref (
    .Mode(2'b00), .Res_n(~reset), .Enable(enableCpu), .Clk(clk32), .Rdy(baLoc), .Abort_n(1'b1),
    .IRQ_n(irq_n), .NMI_n(nmi_n), .SO_n(1'b1), .DI(di_cpu),
    .R_W_n(r_RW), .Sync(r_Sync), .EF(r_EF), .MF(r_MF), .XF(r_XF), .ML_n(r_ML), .VP_n(r_VP), .VDA(r_VDA),
    .VPA(r_VPA), .A(r_A), .DO(r_DO), .Regs(r_Regs),
    .DEBUG_I(r_dbg[0]), .DEBUG_A(r_dbg[1]), .DEBUG_X(r_dbg[2]), .DEBUG_Y(r_dbg[3]), .DEBUG_S(r_dbg[4]),
    .DEBUG_P(r_dbg[5]), .NMI_ack(r_NA));

  t65sv_T65 u_dut (
    .Mode(2'b00), .Res_n(~reset), .Enable(enableCpu), .Clk(clk32), .Rdy(baLoc), .Abort_n(1'b1),
    .IRQ_n(irq_n), .NMI_n(nmi_n), .SO_n(1'b1), .BCD_en(1'b1), .DI(di_cpu),
    .R_W_n(d_RW), .Sync(d_Sync), .EF(d_EF), .MF(d_MF), .XF(d_XF), .ML_n(d_ML), .VP_n(d_VP), .VDA(d_VDA),
    .VPA(d_VPA), .A(d_A), .DO(d_DO), .Regs(d_Regs), .DEBUG(d_DEBUG), .NMI_ack(d_NA));

  t65sv_ioport #(.PORT_BITS(6)) u_port (
    .Clk(clk32), .Res_n(~reset), .Enable(enableCpu), .A(r_A[15:0]), .R_W_n(r_RW), .DO(r_DO),
    .P_I(port_pi), .Sel(port_sel), .Rd(port_rd), .P_O(port_o), .P_DDR(port_ddr));

  assign cpuAddr  = r_A[15:0];
  assign cpuDo    = r_DO;
  assign cpuWe    = ~r_RW;
  assign cpu_sync = r_Sync;
  assign cpu_regs = r_Regs;
  assign mismatch = (r_A != d_A) || (r_DO != d_DO) || (r_RW != d_RW) || (r_Sync != d_Sync) ||
                    (r_Regs != d_Regs) || (r_EF != d_EF) || (r_MF != d_MF) || (r_XF != d_XF) ||
                    (r_ML != d_ML) || (r_VP != d_VP) || (r_VDA != d_VDA) || (r_VPA != d_VPA) ||
                    (r_NA != d_NA) ||
                    (d_DEBUG != {r_dbg[0], r_dbg[1], r_dbg[2], r_dbg[3], r_dbg[4], r_dbg[5]});
`else
  logic        s_RW, s_Sync;
  // the wrapper hides Regs; the C++ side only needs PC and A for traps
  t65sv_6510 #(.PORT_BITS(6)) u_cpu (
    .Clk(clk32), .Enable(enableCpu), .Res_n(~reset), .Rdy(baLoc), .AEC(aec), .IRQ_n(irq_n), .NMI_n(nmi_n),
    .R_W_n(s_RW), .Sync(s_Sync), .Bus_En(), .A(cpuAddr), .DI(cpuDi), .DO(cpuDo),
    .P_I(port_pi), .P_O(port_o), .P_DDR(port_ddr));
  assign cpuWe    = ~s_RW;
  assign cpu_sync = s_Sync;
  assign cpu_regs = {48'd0, u_cpu.u_core.ABC};
  assign mismatch = 1'b0;
`endif

  assign cpu_edge = enableCpu;
  assign cpu_addr = cpuAddr;
  assign cpu_we   = cpuWe;
  assign cpu_do   = cpuDo;
endmodule
