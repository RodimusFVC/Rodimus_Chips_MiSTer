module mc6845_fixed
  (input  CLOCK,
   input  CLKEN,
   input  nRESET,
   input  ENABLE,
   input  R_nW,
   input  RS,
   input  [7:0] DI,
   input  LPSTB,
   output [7:0] DO,
   output VSYNC,
   output HSYNC,
   output VBLANK,
   output HBLANK,
   output DE,
   output CURSOR,
   output [13:0] MA,
   output [4:0] RA);
  wire [4:0] addr_reg;
  wire [7:0] r00_h_total;
  wire [7:0] r01_h_displayed;
  wire [7:0] r02_h_sync_pos;
  wire [3:0] r03_v_sync_width;
  wire [3:0] r03_h_sync_width;
  wire [6:0] r04_v_total;
  wire [4:0] r05_v_total_adj;
  wire [6:0] r06_v_displayed;
  wire [6:0] r07_v_sync_pos;
  wire [7:0] r08_interlace;
  wire [4:0] r09_max_scan_line_addr;
  wire [1:0] r10_cursor_mode;
  wire [4:0] r10_cursor_start;
  wire [4:0] r11_cursor_end;
  wire [5:0] r12_start_addr_h;
  wire [7:0] r13_start_addr_l;
  wire [5:0] r14_cursor_h;
  wire [7:0] r15_cursor_l;
  wire [5:0] r16_light_pen_h;
  wire [7:0] r17_light_pen_l;
  wire [7:0] h_counter;
  wire [3:0] h_sync_counter;
  wire [6:0] row_counter;
  wire [4:0] line_counter;
  wire [3:0] v_sync_counter;
  wire [4:0] field_counter;
  wire h_sync_start;
  wire v_sync_start;
  wire h_display;
  wire h_display_early;
  wire hs;
  wire v_display;
  wire v_display_early;
  wire in_adj_s;
  wire vs;
  wire odd_field;
  wire [13:0] ma_i;
  wire cursor_i;
  wire lpstb_i;
  wire de0;
  wire de1;
  wire de2;
  wire cursor0;
  wire cursor1;
  wire hblank0;
  wire hblank1;
  wire hblank2;
  wire n9_o;
  wire [1:0] n10_o;
  wire n12_o;
  wire n13_o;
  wire [1:0] n14_o;
  wire n16_o;
  wire n17_o;
  wire [1:0] n18_o;
  wire n20_o;
  wire n21_o;
  wire n23_o;
  wire [1:0] n24_o;
  wire n26_o;
  wire n27_o;
  wire n28_o;
  wire [1:0] n29_o;
  wire n31_o;
  wire n32_o;
  wire n33_o;
  wire [1:0] n34_o;
  wire n36_o;
  wire n37_o;
  wire n39_o;
  wire n41_o;
  wire n42_o;
  wire n45_o;
  wire n46_o;
  wire n47_o;
  wire n48_o;
  wire n50_o;
  wire n51_o;
  wire n52_o;
  wire n53_o;
  wire [1:0] n54_o;
  wire n56_o;
  wire n57_o;
  wire [1:0] n58_o;
  wire n60_o;
  wire n61_o;
  wire [1:0] n62_o;
  wire n64_o;
  wire n65_o;
  wire n69_o;
  wire [7:0] n72_o;
  wire n74_o;
  wire n76_o;
  wire [7:0] n78_o;
  wire n80_o;
  wire n82_o;
  wire [7:0] n84_o;
  wire n86_o;
  wire n88_o;
  wire [5:0] n89_o;
  reg [7:0] n91_o;
  wire n92_o;
  wire [4:0] n93_o;
  wire n95_o;
  wire n97_o;
  wire n99_o;
  wire [3:0] n100_o;
  wire [3:0] n101_o;
  wire n103_o;
  wire [6:0] n104_o;
  wire n106_o;
  wire [4:0] n107_o;
  wire n109_o;
  wire [6:0] n110_o;
  wire n112_o;
  wire [6:0] n113_o;
  wire n115_o;
  wire n117_o;
  wire [4:0] n118_o;
  wire n120_o;
  wire [1:0] n121_o;
  wire [4:0] n122_o;
  wire n124_o;
  wire [4:0] n125_o;
  wire n127_o;
  wire [5:0] n128_o;
  wire n130_o;
  wire n132_o;
  wire [5:0] n133_o;
  wire n135_o;
  wire n137_o;
  wire [15:0] n138_o;
  reg [7:0] n139_o;
  reg [7:0] n140_o;
  reg [7:0] n141_o;
  reg [3:0] n142_o;
  reg [3:0] n143_o;
  reg [6:0] n144_o;
  reg [4:0] n145_o;
  reg [6:0] n146_o;
  reg [6:0] n147_o;
  reg [7:0] n148_o;
  reg [4:0] n149_o;
  reg [1:0] n150_o;
  reg [4:0] n151_o;
  reg [4:0] n152_o;
  reg [5:0] n153_o;
  reg [7:0] n154_o;
  reg [5:0] n155_o;
  reg [7:0] n156_o;
  wire [4:0] n157_o;
  wire [7:0] n158_o;
  wire [7:0] n159_o;
  wire [7:0] n160_o;
  wire [3:0] n161_o;
  wire [3:0] n162_o;
  wire [6:0] n163_o;
  wire [4:0] n164_o;
  wire [6:0] n165_o;
  wire [6:0] n166_o;
  wire [7:0] n167_o;
  wire [4:0] n168_o;
  wire [1:0] n169_o;
  wire [4:0] n170_o;
  wire [4:0] n171_o;
  wire [5:0] n172_o;
  wire [7:0] n173_o;
  wire [5:0] n174_o;
  wire [7:0] n175_o;
  wire [4:0] n177_o;
  wire [7:0] n178_o;
  wire [7:0] n179_o;
  wire [7:0] n180_o;
  wire [3:0] n181_o;
  wire [3:0] n182_o;
  wire [6:0] n183_o;
  wire [4:0] n184_o;
  wire [6:0] n185_o;
  wire [6:0] n186_o;
  wire [7:0] n187_o;
  wire [4:0] n188_o;
  wire [1:0] n189_o;
  wire [4:0] n190_o;
  wire [4:0] n191_o;
  wire [5:0] n192_o;
  wire [7:0] n193_o;
  wire [5:0] n194_o;
  wire [7:0] n195_o;
  wire n196_o;
  reg [13:0] n277_ma_row_start;
  reg n277_in_adj;
  wire n284_o;
  wire n286_o;
  wire n288_o;
  wire n289_o;
  wire n292_o;
  wire n293_o;
  wire [4:0] n295_o;
  wire [1:0] n296_o;
  wire n298_o;
  wire [4:0] n300_o;
  wire [4:0] n302_o;
  wire [1:0] n306_o;
  wire n308_o;
  wire n310_o;
  wire n311_o;
  wire n312_o;
  wire n313_o;
  wire n314_o;
  wire n315_o;
  wire n316_o;
  wire n317_o;
  wire [3:0] n318_o;
  wire [3:0] n319_o;
  wire [3:0] n320_o;
  wire [3:0] n321_o;
  wire [3:0] n322_o;
  wire [3:0] n323_o;
  wire [3:0] n324_o;
  wire [4:0] n325_o;
  wire n326_o;
  wire n327_o;
  wire n328_o;
  wire n329_o;
  wire n330_o;
  wire n331_o;
  wire n332_o;
  wire n334_o;
  wire [13:0] n335_o;
  wire [4:0] n337_o;
  wire n338_o;
  wire [4:0] n339_o;
  wire n340_o;
  wire n341_o;
  wire [13:0] n342_o;
  wire [13:0] n343_o;
  wire [6:0] n345_o;
  wire n346_o;
  wire n347_o;
  wire n349_o;
  wire n351_o;
  wire [1:0] n352_o;
  wire n354_o;
  wire [4:0] n356_o;
  wire [3:0] n358_o;
  wire [4:0] n360_o;
  wire [4:0] n361_o;
  wire [4:0] n362_o;
  wire [6:0] n363_o;
  wire [4:0] n365_o;
  wire n366_o;
  wire [13:0] n367_o;
  wire n368_o;
  wire [6:0] n370_o;
  wire [4:0] n372_o;
  wire n375_o;
  wire [13:0] n377_o;
  wire n379_o;
  wire [7:0] n381_o;
  wire [13:0] n383_o;
  wire [7:0] n385_o;
  wire n388_o;
  wire n390_o;
  wire [13:0] n391_o;
  wire n398_o;
  wire n399_o;
  wire n400_o;
  wire n401_o;
  wire n402_o;
  wire n404_o;
  wire n406_o;
  wire [13:0] n440_o;
  reg [13:0] n441_q;
  wire n446_o;
  reg n447_q;
  wire n454_o;
  wire n457_o;
  wire n459_o;
  wire n462_o;
  wire n466_o;
  wire n467_o;
  wire n470_o;
  wire n471_o;
  wire n472_o;
  wire n473_o;
  wire n477_o;
  wire n479_o;
  wire [3:0] n481_o;
  wire [3:0] n483_o;
  wire n485_o;
  wire n486_o;
  wire n488_o;
  wire n489_o;
  wire n491_o;
  wire n492_o;
  wire n493_o;
  wire [3:0] n495_o;
  wire [3:0] n497_o;
  wire n499_o;
  wire n500_o;
  wire n501_o;
  wire n503_o;
  wire n507_o;
  wire n511_o;
  wire n534_o;
  wire [1:0] n536_o;
  wire n538_o;
  wire [3:0] n539_o;
  wire n540_o;
  wire n541_o;
  wire [4:0] n542_o;
  wire [4:0] n543_o;
  reg n560_cursor_line;
  wire n563_o;
  wire n565_o;
  wire [13:0] n566_o;
  wire n567_o;
  wire n568_o;
  wire n570_o;
  wire n572_o;
  wire n573_o;
  wire n575_o;
  wire n576_o;
  wire n578_o;
  wire n580_o;
  wire n583_o;
  wire n591_o;
  reg n592_q;
  wire n595_o;
  wire n597_o;
  wire n598_o;
  wire [5:0] n599_o;
  wire [7:0] n600_o;
  wire n603_o;
  wire n604_o;
  wire [4:0] n630_o;
  reg [4:0] n631_q;
  wire [7:0] n632_o;
  reg [7:0] n633_q;
  wire [7:0] n634_o;
  reg [7:0] n635_q;
  wire [7:0] n636_o;
  reg [7:0] n637_q;
  wire [3:0] n638_o;
  reg [3:0] n639_q;
  wire [3:0] n640_o;
  reg [3:0] n641_q;
  wire [6:0] n642_o;
  reg [6:0] n643_q;
  wire [4:0] n644_o;
  reg [4:0] n645_q;
  wire [6:0] n646_o;
  reg [6:0] n647_q;
  wire [6:0] n648_o;
  reg [6:0] n649_q;
  wire [7:0] n650_o;
  reg [7:0] n651_q;
  wire [4:0] n652_o;
  reg [4:0] n653_q;
  wire [1:0] n654_o;
  reg [1:0] n655_q;
  wire [4:0] n656_o;
  reg [4:0] n657_q;
  wire [4:0] n658_o;
  reg [4:0] n659_q;
  wire [5:0] n660_o;
  reg [5:0] n661_q;
  wire [7:0] n662_o;
  reg [7:0] n663_q;
  wire [5:0] n664_o;
  reg [5:0] n665_q;
  wire [7:0] n666_o;
  reg [7:0] n667_q;
  wire [5:0] n668_o;
  reg [5:0] n669_q;
  wire [7:0] n670_o;
  reg [7:0] n671_q;
  wire [7:0] n672_o;
  reg [7:0] n673_q;
  wire [3:0] n674_o;
  reg [3:0] n675_q;
  wire [6:0] n676_o;
  reg [6:0] n677_q;
  wire [4:0] n678_o;
  reg [4:0] n679_q;
  wire [3:0] n680_o;
  reg [3:0] n681_q;
  wire [4:0] n682_o;
  reg [4:0] n683_q;
  wire n684_o;
  reg n685_q;
  wire n686_o;
  reg n687_q;
  wire n688_o;
  reg n689_q;
  wire n690_o;
  reg n691_q;
  wire n692_o;
  reg n693_q;
  wire n694_o;
  reg n695_q;
  wire [13:0] n696_o;
  reg [13:0] n697_q;
  wire n699_o;
  reg n700_q;
  wire n701_o;
  reg n702_q;
  wire n703_o;
  reg n704_q;
  wire n705_o;
  reg n706_q;
  wire n707_o;
  reg n708_q;
  wire n710_o;
  reg n711_q;
  wire n712_o;
  reg n713_q;
  wire [7:0] n714_o;
  reg [7:0] n715_q;
  wire [13:0] n716_o;
  reg [13:0] n717_q;
  wire [4:0] n718_o;
  reg [4:0] n719_q;
  assign DO = n715_q;
  assign VSYNC = vs;
  assign HSYNC = hs;
  assign VBLANK = n39_o;
  assign HBLANK = n27_o;
  assign DE = n13_o;
  assign CURSOR = n57_o;
  assign MA = n717_q;
  assign RA = n719_q;
  /* mc6845_fixed.vhd:87:8  */
  assign addr_reg = n631_q; // (signal)
  /* mc6845_fixed.vhd:89:8  */
  assign r00_h_total = n633_q; // (signal)
  /* mc6845_fixed.vhd:90:8  */
  assign r01_h_displayed = n635_q; // (signal)
  /* mc6845_fixed.vhd:91:8  */
  assign r02_h_sync_pos = n637_q; // (signal)
  /* mc6845_fixed.vhd:92:8  */
  assign r03_v_sync_width = n639_q; // (signal)
  /* mc6845_fixed.vhd:93:8  */
  assign r03_h_sync_width = n641_q; // (signal)
  /* mc6845_fixed.vhd:94:8  */
  assign r04_v_total = n643_q; // (signal)
  /* mc6845_fixed.vhd:95:8  */
  assign r05_v_total_adj = n645_q; // (signal)
  /* mc6845_fixed.vhd:96:8  */
  assign r06_v_displayed = n647_q; // (signal)
  /* mc6845_fixed.vhd:97:8  */
  assign r07_v_sync_pos = n649_q; // (signal)
  /* mc6845_fixed.vhd:98:8  */
  assign r08_interlace = n651_q; // (signal)
  /* mc6845_fixed.vhd:99:8  */
  assign r09_max_scan_line_addr = n653_q; // (signal)
  /* mc6845_fixed.vhd:100:8  */
  assign r10_cursor_mode = n655_q; // (signal)
  /* mc6845_fixed.vhd:101:8  */
  assign r10_cursor_start = n657_q; // (signal)
  /* mc6845_fixed.vhd:102:8  */
  assign r11_cursor_end = n659_q; // (signal)
  /* mc6845_fixed.vhd:103:8  */
  assign r12_start_addr_h = n661_q; // (signal)
  /* mc6845_fixed.vhd:104:8  */
  assign r13_start_addr_l = n663_q; // (signal)
  /* mc6845_fixed.vhd:106:8  */
  assign r14_cursor_h = n665_q; // (signal)
  /* mc6845_fixed.vhd:107:8  */
  assign r15_cursor_l = n667_q; // (signal)
  /* mc6845_fixed.vhd:109:8  */
  assign r16_light_pen_h = n669_q; // (signal)
  /* mc6845_fixed.vhd:110:8  */
  assign r17_light_pen_l = n671_q; // (signal)
  /* mc6845_fixed.vhd:115:8  */
  assign h_counter = n673_q; // (signal)
  /* mc6845_fixed.vhd:117:8  */
  assign h_sync_counter = n675_q; // (signal)
  /* mc6845_fixed.vhd:119:8  */
  assign row_counter = n677_q; // (signal)
  /* mc6845_fixed.vhd:121:8  */
  assign line_counter = n679_q; // (signal)
  /* mc6845_fixed.vhd:123:8  */
  assign v_sync_counter = n681_q; // (signal)
  /* mc6845_fixed.vhd:125:8  */
  assign field_counter = n683_q; // (signal)
  /* mc6845_fixed.vhd:128:8  */
  assign h_sync_start = n457_o; // (signal)
  /* mc6845_fixed.vhd:129:8  */
  assign v_sync_start = n462_o; // (signal)
  /* mc6845_fixed.vhd:130:8  */
  assign h_display = n685_q; // (signal)
  /* mc6845_fixed.vhd:131:8  */
  assign h_display_early = n467_o; // (signal)
  /* mc6845_fixed.vhd:132:8  */
  assign hs = n687_q; // (signal)
  /* mc6845_fixed.vhd:133:8  */
  assign v_display = n689_q; // (signal)
  /* mc6845_fixed.vhd:134:8  */
  assign v_display_early = n473_o; // (signal)
  /* mc6845_fixed.vhd:135:8  */
  assign in_adj_s = n691_q; // (signal)
  /* mc6845_fixed.vhd:136:8  */
  assign vs = n693_q; // (signal)
  /* mc6845_fixed.vhd:137:8  */
  assign odd_field = n695_q; // (signal)
  /* mc6845_fixed.vhd:138:8  */
  assign ma_i = n697_q; // (signal)
  /* mc6845_fixed.vhd:140:8  */
  assign cursor_i = n700_q; // (signal)
  /* mc6845_fixed.vhd:141:8  */
  assign lpstb_i = n702_q; // (signal)
  /* mc6845_fixed.vhd:142:8  */
  assign de0 = n9_o; // (signal)
  /* mc6845_fixed.vhd:143:8  */
  assign de1 = n704_q; // (signal)
  /* mc6845_fixed.vhd:144:8  */
  assign de2 = n706_q; // (signal)
  /* mc6845_fixed.vhd:145:8  */
  assign cursor0 = n42_o; // (signal)
  /* mc6845_fixed.vhd:146:8  */
  assign cursor1 = n708_q; // (signal)
  /* mc6845_fixed.vhd:149:8  */
  assign hblank0 = h_display; // (signal)
  /* mc6845_fixed.vhd:150:8  */
  assign hblank1 = n711_q; // (signal)
  /* mc6845_fixed.vhd:151:8  */
  assign hblank2 = n713_q; // (signal)
  /* mc6845_fixed.vhd:159:26  */
  assign n9_o = h_display & v_display;
  /* mc6845_fixed.vhd:164:37  */
  assign n10_o = r08_interlace[5:4];
  /* mc6845_fixed.vhd:164:50  */
  assign n12_o = n10_o == 2'b00;
  /* mc6845_fixed.vhd:164:19  */
  assign n13_o = n12_o ? de0 : n17_o;
  /* mc6845_fixed.vhd:165:41  */
  assign n14_o = r08_interlace[5:4];
  /* mc6845_fixed.vhd:165:54  */
  assign n16_o = n14_o == 2'b01;
  /* mc6845_fixed.vhd:164:57  */
  assign n17_o = n16_o ? de0 : n21_o;
  /* mc6845_fixed.vhd:166:41  */
  assign n18_o = r08_interlace[5:4];
  /* mc6845_fixed.vhd:166:54  */
  assign n20_o = n18_o == 2'b10;
  /* mc6845_fixed.vhd:165:61  */
  assign n21_o = n20_o ? de2 : 1'b0;
  /* mc6845_fixed.vhd:169:19  */
  assign n23_o = ~hblank0;
  /* mc6845_fixed.vhd:169:49  */
  assign n24_o = r08_interlace[5:4];
  /* mc6845_fixed.vhd:169:62  */
  assign n26_o = n24_o == 2'b00;
  /* mc6845_fixed.vhd:169:31  */
  assign n27_o = n26_o ? n23_o : n32_o;
  /* mc6845_fixed.vhd:170:19  */
  assign n28_o = ~hblank0;
  /* mc6845_fixed.vhd:170:49  */
  assign n29_o = r08_interlace[5:4];
  /* mc6845_fixed.vhd:170:62  */
  assign n31_o = n29_o == 2'b01;
  /* mc6845_fixed.vhd:169:69  */
  assign n32_o = n31_o ? n28_o : n37_o;
  /* mc6845_fixed.vhd:171:19  */
  assign n33_o = ~hblank2;
  /* mc6845_fixed.vhd:171:49  */
  assign n34_o = r08_interlace[5:4];
  /* mc6845_fixed.vhd:171:62  */
  assign n36_o = n34_o == 2'b10;
  /* mc6845_fixed.vhd:170:69  */
  assign n37_o = n36_o ? n33_o : 1'b1;
  /* mc6845_fixed.vhd:174:19  */
  assign n39_o = ~v_display;
  /* mc6845_fixed.vhd:178:102  */
  assign n41_o = r10_cursor_mode == 2'b00;
  /* mc6845_fixed.vhd:178:81  */
  assign n42_o = n41_o ? cursor_i : n46_o;
  /* mc6845_fixed.vhd:179:118  */
  assign n45_o = r10_cursor_mode == 2'b01;
  /* mc6845_fixed.vhd:178:109  */
  assign n46_o = n45_o ? 1'b0 : n51_o;
  /* mc6845_fixed.vhd:180:60  */
  assign n47_o = field_counter[3];
  /* mc6845_fixed.vhd:180:43  */
  assign n48_o = cursor_i & n47_o;
  /* mc6845_fixed.vhd:180:94  */
  assign n50_o = r10_cursor_mode == 2'b10;
  /* mc6845_fixed.vhd:179:125  */
  assign n51_o = n50_o ? n48_o : n53_o;
  /* mc6845_fixed.vhd:181:60  */
  assign n52_o = field_counter[4];
  /* mc6845_fixed.vhd:181:43  */
  assign n53_o = cursor_i & n52_o;
  /* mc6845_fixed.vhd:185:47  */
  assign n54_o = r08_interlace[7:6];
  /* mc6845_fixed.vhd:185:60  */
  assign n56_o = n54_o == 2'b00;
  /* mc6845_fixed.vhd:185:29  */
  assign n57_o = n56_o ? cursor0 : n61_o;
  /* mc6845_fixed.vhd:186:59  */
  assign n58_o = r08_interlace[7:6];
  /* mc6845_fixed.vhd:186:72  */
  assign n60_o = n58_o == 2'b01;
  /* mc6845_fixed.vhd:185:67  */
  assign n61_o = n60_o ? cursor1 : n65_o;
  /* mc6845_fixed.vhd:187:59  */
  assign n62_o = r08_interlace[7:6];
  /* mc6845_fixed.vhd:187:72  */
  assign n64_o = n62_o == 2'b10;
  /* mc6845_fixed.vhd:186:79  */
  assign n65_o = n64_o ? cursor1 : 1'b0;
  /* mc6845_fixed.vhd:193:19  */
  assign n69_o = ~nRESET;
  /* mc6845_fixed.vhd:220:60  */
  assign n72_o = {2'b00, r12_start_addr_h};
  /* mc6845_fixed.vhd:219:41  */
  assign n74_o = addr_reg == 5'b01100;
  /* mc6845_fixed.vhd:221:41  */
  assign n76_o = addr_reg == 5'b01101;
  /* mc6845_fixed.vhd:224:60  */
  assign n78_o = {2'b00, r14_cursor_h};
  /* mc6845_fixed.vhd:223:41  */
  assign n80_o = addr_reg == 5'b01110;
  /* mc6845_fixed.vhd:225:41  */
  assign n82_o = addr_reg == 5'b01111;
  /* mc6845_fixed.vhd:228:60  */
  assign n84_o = {2'b00, r16_light_pen_h};
  /* mc6845_fixed.vhd:227:41  */
  assign n86_o = addr_reg == 5'b10000;
  /* mc6845_fixed.vhd:229:41  */
  assign n88_o = addr_reg == 5'b10001;
  assign n89_o = {n88_o, n86_o, n82_o, n80_o, n76_o, n74_o};
  /* mc6845_fixed.vhd:218:41  */
  always @*
    case (n89_o)
      6'b100000: n91_o = r17_light_pen_l;
      6'b010000: n91_o = n84_o;
      6'b001000: n91_o = r15_cursor_l;
      6'b000100: n91_o = n78_o;
      6'b000010: n91_o = r13_start_addr_l;
      6'b000001: n91_o = n72_o;
      default: n91_o = 8'b00000000;
    endcase
  /* mc6845_fixed.vhd:236:47  */
  assign n92_o = ~RS;
  /* mc6845_fixed.vhd:237:63  */
  assign n93_o = DI[4:0];
  /* mc6845_fixed.vhd:240:49  */
  assign n95_o = addr_reg == 5'b00000;
  /* mc6845_fixed.vhd:242:49  */
  assign n97_o = addr_reg == 5'b00001;
  /* mc6845_fixed.vhd:244:49  */
  assign n99_o = addr_reg == 5'b00010;
  /* mc6845_fixed.vhd:247:88  */
  assign n100_o = DI[7:4];
  /* mc6845_fixed.vhd:248:88  */
  assign n101_o = DI[3:0];
  /* mc6845_fixed.vhd:246:49  */
  assign n103_o = addr_reg == 5'b00011;
  /* mc6845_fixed.vhd:250:83  */
  assign n104_o = DI[6:0];
  /* mc6845_fixed.vhd:249:49  */
  assign n106_o = addr_reg == 5'b00100;
  /* mc6845_fixed.vhd:252:87  */
  assign n107_o = DI[4:0];
  /* mc6845_fixed.vhd:251:49  */
  assign n109_o = addr_reg == 5'b00101;
  /* mc6845_fixed.vhd:254:87  */
  assign n110_o = DI[6:0];
  /* mc6845_fixed.vhd:253:49  */
  assign n112_o = addr_reg == 5'b00110;
  /* mc6845_fixed.vhd:256:86  */
  assign n113_o = DI[6:0];
  /* mc6845_fixed.vhd:255:49  */
  assign n115_o = addr_reg == 5'b00111;
  /* mc6845_fixed.vhd:257:49  */
  assign n117_o = addr_reg == 5'b01000;
  /* mc6845_fixed.vhd:260:94  */
  assign n118_o = DI[4:0];
  /* mc6845_fixed.vhd:259:49  */
  assign n120_o = addr_reg == 5'b01001;
  /* mc6845_fixed.vhd:262:78  */
  assign n121_o = DI[6:5];
  /* mc6845_fixed.vhd:263:88  */
  assign n122_o = DI[4:0];
  /* mc6845_fixed.vhd:261:49  */
  assign n124_o = addr_reg == 5'b01010;
  /* mc6845_fixed.vhd:265:86  */
  assign n125_o = DI[4:0];
  /* mc6845_fixed.vhd:264:49  */
  assign n127_o = addr_reg == 5'b01011;
  /* mc6845_fixed.vhd:267:88  */
  assign n128_o = DI[5:0];
  /* mc6845_fixed.vhd:266:49  */
  assign n130_o = addr_reg == 5'b01100;
  /* mc6845_fixed.vhd:268:49  */
  assign n132_o = addr_reg == 5'b01101;
  /* mc6845_fixed.vhd:271:84  */
  assign n133_o = DI[5:0];
  /* mc6845_fixed.vhd:270:49  */
  assign n135_o = addr_reg == 5'b01110;
  /* mc6845_fixed.vhd:272:49  */
  assign n137_o = addr_reg == 5'b01111;
  assign n138_o = {n137_o, n135_o, n132_o, n130_o, n127_o, n124_o, n120_o, n117_o, n115_o, n112_o, n109_o, n106_o, n103_o, n99_o, n97_o, n95_o};
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n139_o = r00_h_total;
      16'b0100000000000000: n139_o = r00_h_total;
      16'b0010000000000000: n139_o = r00_h_total;
      16'b0001000000000000: n139_o = r00_h_total;
      16'b0000100000000000: n139_o = r00_h_total;
      16'b0000010000000000: n139_o = r00_h_total;
      16'b0000001000000000: n139_o = r00_h_total;
      16'b0000000100000000: n139_o = r00_h_total;
      16'b0000000010000000: n139_o = r00_h_total;
      16'b0000000001000000: n139_o = r00_h_total;
      16'b0000000000100000: n139_o = r00_h_total;
      16'b0000000000010000: n139_o = r00_h_total;
      16'b0000000000001000: n139_o = r00_h_total;
      16'b0000000000000100: n139_o = r00_h_total;
      16'b0000000000000010: n139_o = r00_h_total;
      16'b0000000000000001: n139_o = DI;
      default: n139_o = r00_h_total;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n140_o = r01_h_displayed;
      16'b0100000000000000: n140_o = r01_h_displayed;
      16'b0010000000000000: n140_o = r01_h_displayed;
      16'b0001000000000000: n140_o = r01_h_displayed;
      16'b0000100000000000: n140_o = r01_h_displayed;
      16'b0000010000000000: n140_o = r01_h_displayed;
      16'b0000001000000000: n140_o = r01_h_displayed;
      16'b0000000100000000: n140_o = r01_h_displayed;
      16'b0000000010000000: n140_o = r01_h_displayed;
      16'b0000000001000000: n140_o = r01_h_displayed;
      16'b0000000000100000: n140_o = r01_h_displayed;
      16'b0000000000010000: n140_o = r01_h_displayed;
      16'b0000000000001000: n140_o = r01_h_displayed;
      16'b0000000000000100: n140_o = r01_h_displayed;
      16'b0000000000000010: n140_o = DI;
      16'b0000000000000001: n140_o = r01_h_displayed;
      default: n140_o = r01_h_displayed;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n141_o = r02_h_sync_pos;
      16'b0100000000000000: n141_o = r02_h_sync_pos;
      16'b0010000000000000: n141_o = r02_h_sync_pos;
      16'b0001000000000000: n141_o = r02_h_sync_pos;
      16'b0000100000000000: n141_o = r02_h_sync_pos;
      16'b0000010000000000: n141_o = r02_h_sync_pos;
      16'b0000001000000000: n141_o = r02_h_sync_pos;
      16'b0000000100000000: n141_o = r02_h_sync_pos;
      16'b0000000010000000: n141_o = r02_h_sync_pos;
      16'b0000000001000000: n141_o = r02_h_sync_pos;
      16'b0000000000100000: n141_o = r02_h_sync_pos;
      16'b0000000000010000: n141_o = r02_h_sync_pos;
      16'b0000000000001000: n141_o = r02_h_sync_pos;
      16'b0000000000000100: n141_o = DI;
      16'b0000000000000010: n141_o = r02_h_sync_pos;
      16'b0000000000000001: n141_o = r02_h_sync_pos;
      default: n141_o = r02_h_sync_pos;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n142_o = r03_v_sync_width;
      16'b0100000000000000: n142_o = r03_v_sync_width;
      16'b0010000000000000: n142_o = r03_v_sync_width;
      16'b0001000000000000: n142_o = r03_v_sync_width;
      16'b0000100000000000: n142_o = r03_v_sync_width;
      16'b0000010000000000: n142_o = r03_v_sync_width;
      16'b0000001000000000: n142_o = r03_v_sync_width;
      16'b0000000100000000: n142_o = r03_v_sync_width;
      16'b0000000010000000: n142_o = r03_v_sync_width;
      16'b0000000001000000: n142_o = r03_v_sync_width;
      16'b0000000000100000: n142_o = r03_v_sync_width;
      16'b0000000000010000: n142_o = r03_v_sync_width;
      16'b0000000000001000: n142_o = n100_o;
      16'b0000000000000100: n142_o = r03_v_sync_width;
      16'b0000000000000010: n142_o = r03_v_sync_width;
      16'b0000000000000001: n142_o = r03_v_sync_width;
      default: n142_o = r03_v_sync_width;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n143_o = r03_h_sync_width;
      16'b0100000000000000: n143_o = r03_h_sync_width;
      16'b0010000000000000: n143_o = r03_h_sync_width;
      16'b0001000000000000: n143_o = r03_h_sync_width;
      16'b0000100000000000: n143_o = r03_h_sync_width;
      16'b0000010000000000: n143_o = r03_h_sync_width;
      16'b0000001000000000: n143_o = r03_h_sync_width;
      16'b0000000100000000: n143_o = r03_h_sync_width;
      16'b0000000010000000: n143_o = r03_h_sync_width;
      16'b0000000001000000: n143_o = r03_h_sync_width;
      16'b0000000000100000: n143_o = r03_h_sync_width;
      16'b0000000000010000: n143_o = r03_h_sync_width;
      16'b0000000000001000: n143_o = n101_o;
      16'b0000000000000100: n143_o = r03_h_sync_width;
      16'b0000000000000010: n143_o = r03_h_sync_width;
      16'b0000000000000001: n143_o = r03_h_sync_width;
      default: n143_o = r03_h_sync_width;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n144_o = r04_v_total;
      16'b0100000000000000: n144_o = r04_v_total;
      16'b0010000000000000: n144_o = r04_v_total;
      16'b0001000000000000: n144_o = r04_v_total;
      16'b0000100000000000: n144_o = r04_v_total;
      16'b0000010000000000: n144_o = r04_v_total;
      16'b0000001000000000: n144_o = r04_v_total;
      16'b0000000100000000: n144_o = r04_v_total;
      16'b0000000010000000: n144_o = r04_v_total;
      16'b0000000001000000: n144_o = r04_v_total;
      16'b0000000000100000: n144_o = r04_v_total;
      16'b0000000000010000: n144_o = n104_o;
      16'b0000000000001000: n144_o = r04_v_total;
      16'b0000000000000100: n144_o = r04_v_total;
      16'b0000000000000010: n144_o = r04_v_total;
      16'b0000000000000001: n144_o = r04_v_total;
      default: n144_o = r04_v_total;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n145_o = r05_v_total_adj;
      16'b0100000000000000: n145_o = r05_v_total_adj;
      16'b0010000000000000: n145_o = r05_v_total_adj;
      16'b0001000000000000: n145_o = r05_v_total_adj;
      16'b0000100000000000: n145_o = r05_v_total_adj;
      16'b0000010000000000: n145_o = r05_v_total_adj;
      16'b0000001000000000: n145_o = r05_v_total_adj;
      16'b0000000100000000: n145_o = r05_v_total_adj;
      16'b0000000010000000: n145_o = r05_v_total_adj;
      16'b0000000001000000: n145_o = r05_v_total_adj;
      16'b0000000000100000: n145_o = n107_o;
      16'b0000000000010000: n145_o = r05_v_total_adj;
      16'b0000000000001000: n145_o = r05_v_total_adj;
      16'b0000000000000100: n145_o = r05_v_total_adj;
      16'b0000000000000010: n145_o = r05_v_total_adj;
      16'b0000000000000001: n145_o = r05_v_total_adj;
      default: n145_o = r05_v_total_adj;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n146_o = r06_v_displayed;
      16'b0100000000000000: n146_o = r06_v_displayed;
      16'b0010000000000000: n146_o = r06_v_displayed;
      16'b0001000000000000: n146_o = r06_v_displayed;
      16'b0000100000000000: n146_o = r06_v_displayed;
      16'b0000010000000000: n146_o = r06_v_displayed;
      16'b0000001000000000: n146_o = r06_v_displayed;
      16'b0000000100000000: n146_o = r06_v_displayed;
      16'b0000000010000000: n146_o = r06_v_displayed;
      16'b0000000001000000: n146_o = n110_o;
      16'b0000000000100000: n146_o = r06_v_displayed;
      16'b0000000000010000: n146_o = r06_v_displayed;
      16'b0000000000001000: n146_o = r06_v_displayed;
      16'b0000000000000100: n146_o = r06_v_displayed;
      16'b0000000000000010: n146_o = r06_v_displayed;
      16'b0000000000000001: n146_o = r06_v_displayed;
      default: n146_o = r06_v_displayed;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n147_o = r07_v_sync_pos;
      16'b0100000000000000: n147_o = r07_v_sync_pos;
      16'b0010000000000000: n147_o = r07_v_sync_pos;
      16'b0001000000000000: n147_o = r07_v_sync_pos;
      16'b0000100000000000: n147_o = r07_v_sync_pos;
      16'b0000010000000000: n147_o = r07_v_sync_pos;
      16'b0000001000000000: n147_o = r07_v_sync_pos;
      16'b0000000100000000: n147_o = r07_v_sync_pos;
      16'b0000000010000000: n147_o = n113_o;
      16'b0000000001000000: n147_o = r07_v_sync_pos;
      16'b0000000000100000: n147_o = r07_v_sync_pos;
      16'b0000000000010000: n147_o = r07_v_sync_pos;
      16'b0000000000001000: n147_o = r07_v_sync_pos;
      16'b0000000000000100: n147_o = r07_v_sync_pos;
      16'b0000000000000010: n147_o = r07_v_sync_pos;
      16'b0000000000000001: n147_o = r07_v_sync_pos;
      default: n147_o = r07_v_sync_pos;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n148_o = r08_interlace;
      16'b0100000000000000: n148_o = r08_interlace;
      16'b0010000000000000: n148_o = r08_interlace;
      16'b0001000000000000: n148_o = r08_interlace;
      16'b0000100000000000: n148_o = r08_interlace;
      16'b0000010000000000: n148_o = r08_interlace;
      16'b0000001000000000: n148_o = r08_interlace;
      16'b0000000100000000: n148_o = DI;
      16'b0000000010000000: n148_o = r08_interlace;
      16'b0000000001000000: n148_o = r08_interlace;
      16'b0000000000100000: n148_o = r08_interlace;
      16'b0000000000010000: n148_o = r08_interlace;
      16'b0000000000001000: n148_o = r08_interlace;
      16'b0000000000000100: n148_o = r08_interlace;
      16'b0000000000000010: n148_o = r08_interlace;
      16'b0000000000000001: n148_o = r08_interlace;
      default: n148_o = r08_interlace;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n149_o = r09_max_scan_line_addr;
      16'b0100000000000000: n149_o = r09_max_scan_line_addr;
      16'b0010000000000000: n149_o = r09_max_scan_line_addr;
      16'b0001000000000000: n149_o = r09_max_scan_line_addr;
      16'b0000100000000000: n149_o = r09_max_scan_line_addr;
      16'b0000010000000000: n149_o = r09_max_scan_line_addr;
      16'b0000001000000000: n149_o = n118_o;
      16'b0000000100000000: n149_o = r09_max_scan_line_addr;
      16'b0000000010000000: n149_o = r09_max_scan_line_addr;
      16'b0000000001000000: n149_o = r09_max_scan_line_addr;
      16'b0000000000100000: n149_o = r09_max_scan_line_addr;
      16'b0000000000010000: n149_o = r09_max_scan_line_addr;
      16'b0000000000001000: n149_o = r09_max_scan_line_addr;
      16'b0000000000000100: n149_o = r09_max_scan_line_addr;
      16'b0000000000000010: n149_o = r09_max_scan_line_addr;
      16'b0000000000000001: n149_o = r09_max_scan_line_addr;
      default: n149_o = r09_max_scan_line_addr;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n150_o = r10_cursor_mode;
      16'b0100000000000000: n150_o = r10_cursor_mode;
      16'b0010000000000000: n150_o = r10_cursor_mode;
      16'b0001000000000000: n150_o = r10_cursor_mode;
      16'b0000100000000000: n150_o = r10_cursor_mode;
      16'b0000010000000000: n150_o = n121_o;
      16'b0000001000000000: n150_o = r10_cursor_mode;
      16'b0000000100000000: n150_o = r10_cursor_mode;
      16'b0000000010000000: n150_o = r10_cursor_mode;
      16'b0000000001000000: n150_o = r10_cursor_mode;
      16'b0000000000100000: n150_o = r10_cursor_mode;
      16'b0000000000010000: n150_o = r10_cursor_mode;
      16'b0000000000001000: n150_o = r10_cursor_mode;
      16'b0000000000000100: n150_o = r10_cursor_mode;
      16'b0000000000000010: n150_o = r10_cursor_mode;
      16'b0000000000000001: n150_o = r10_cursor_mode;
      default: n150_o = r10_cursor_mode;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n151_o = r10_cursor_start;
      16'b0100000000000000: n151_o = r10_cursor_start;
      16'b0010000000000000: n151_o = r10_cursor_start;
      16'b0001000000000000: n151_o = r10_cursor_start;
      16'b0000100000000000: n151_o = r10_cursor_start;
      16'b0000010000000000: n151_o = n122_o;
      16'b0000001000000000: n151_o = r10_cursor_start;
      16'b0000000100000000: n151_o = r10_cursor_start;
      16'b0000000010000000: n151_o = r10_cursor_start;
      16'b0000000001000000: n151_o = r10_cursor_start;
      16'b0000000000100000: n151_o = r10_cursor_start;
      16'b0000000000010000: n151_o = r10_cursor_start;
      16'b0000000000001000: n151_o = r10_cursor_start;
      16'b0000000000000100: n151_o = r10_cursor_start;
      16'b0000000000000010: n151_o = r10_cursor_start;
      16'b0000000000000001: n151_o = r10_cursor_start;
      default: n151_o = r10_cursor_start;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n152_o = r11_cursor_end;
      16'b0100000000000000: n152_o = r11_cursor_end;
      16'b0010000000000000: n152_o = r11_cursor_end;
      16'b0001000000000000: n152_o = r11_cursor_end;
      16'b0000100000000000: n152_o = n125_o;
      16'b0000010000000000: n152_o = r11_cursor_end;
      16'b0000001000000000: n152_o = r11_cursor_end;
      16'b0000000100000000: n152_o = r11_cursor_end;
      16'b0000000010000000: n152_o = r11_cursor_end;
      16'b0000000001000000: n152_o = r11_cursor_end;
      16'b0000000000100000: n152_o = r11_cursor_end;
      16'b0000000000010000: n152_o = r11_cursor_end;
      16'b0000000000001000: n152_o = r11_cursor_end;
      16'b0000000000000100: n152_o = r11_cursor_end;
      16'b0000000000000010: n152_o = r11_cursor_end;
      16'b0000000000000001: n152_o = r11_cursor_end;
      default: n152_o = r11_cursor_end;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n153_o = r12_start_addr_h;
      16'b0100000000000000: n153_o = r12_start_addr_h;
      16'b0010000000000000: n153_o = r12_start_addr_h;
      16'b0001000000000000: n153_o = n128_o;
      16'b0000100000000000: n153_o = r12_start_addr_h;
      16'b0000010000000000: n153_o = r12_start_addr_h;
      16'b0000001000000000: n153_o = r12_start_addr_h;
      16'b0000000100000000: n153_o = r12_start_addr_h;
      16'b0000000010000000: n153_o = r12_start_addr_h;
      16'b0000000001000000: n153_o = r12_start_addr_h;
      16'b0000000000100000: n153_o = r12_start_addr_h;
      16'b0000000000010000: n153_o = r12_start_addr_h;
      16'b0000000000001000: n153_o = r12_start_addr_h;
      16'b0000000000000100: n153_o = r12_start_addr_h;
      16'b0000000000000010: n153_o = r12_start_addr_h;
      16'b0000000000000001: n153_o = r12_start_addr_h;
      default: n153_o = r12_start_addr_h;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n154_o = r13_start_addr_l;
      16'b0100000000000000: n154_o = r13_start_addr_l;
      16'b0010000000000000: n154_o = DI;
      16'b0001000000000000: n154_o = r13_start_addr_l;
      16'b0000100000000000: n154_o = r13_start_addr_l;
      16'b0000010000000000: n154_o = r13_start_addr_l;
      16'b0000001000000000: n154_o = r13_start_addr_l;
      16'b0000000100000000: n154_o = r13_start_addr_l;
      16'b0000000010000000: n154_o = r13_start_addr_l;
      16'b0000000001000000: n154_o = r13_start_addr_l;
      16'b0000000000100000: n154_o = r13_start_addr_l;
      16'b0000000000010000: n154_o = r13_start_addr_l;
      16'b0000000000001000: n154_o = r13_start_addr_l;
      16'b0000000000000100: n154_o = r13_start_addr_l;
      16'b0000000000000010: n154_o = r13_start_addr_l;
      16'b0000000000000001: n154_o = r13_start_addr_l;
      default: n154_o = r13_start_addr_l;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n155_o = r14_cursor_h;
      16'b0100000000000000: n155_o = n133_o;
      16'b0010000000000000: n155_o = r14_cursor_h;
      16'b0001000000000000: n155_o = r14_cursor_h;
      16'b0000100000000000: n155_o = r14_cursor_h;
      16'b0000010000000000: n155_o = r14_cursor_h;
      16'b0000001000000000: n155_o = r14_cursor_h;
      16'b0000000100000000: n155_o = r14_cursor_h;
      16'b0000000010000000: n155_o = r14_cursor_h;
      16'b0000000001000000: n155_o = r14_cursor_h;
      16'b0000000000100000: n155_o = r14_cursor_h;
      16'b0000000000010000: n155_o = r14_cursor_h;
      16'b0000000000001000: n155_o = r14_cursor_h;
      16'b0000000000000100: n155_o = r14_cursor_h;
      16'b0000000000000010: n155_o = r14_cursor_h;
      16'b0000000000000001: n155_o = r14_cursor_h;
      default: n155_o = r14_cursor_h;
    endcase
  /* mc6845_fixed.vhd:239:49  */
  always @*
    case (n138_o)
      16'b1000000000000000: n156_o = DI;
      16'b0100000000000000: n156_o = r15_cursor_l;
      16'b0010000000000000: n156_o = r15_cursor_l;
      16'b0001000000000000: n156_o = r15_cursor_l;
      16'b0000100000000000: n156_o = r15_cursor_l;
      16'b0000010000000000: n156_o = r15_cursor_l;
      16'b0000001000000000: n156_o = r15_cursor_l;
      16'b0000000100000000: n156_o = r15_cursor_l;
      16'b0000000010000000: n156_o = r15_cursor_l;
      16'b0000000001000000: n156_o = r15_cursor_l;
      16'b0000000000100000: n156_o = r15_cursor_l;
      16'b0000000000010000: n156_o = r15_cursor_l;
      16'b0000000000001000: n156_o = r15_cursor_l;
      16'b0000000000000100: n156_o = r15_cursor_l;
      16'b0000000000000010: n156_o = r15_cursor_l;
      16'b0000000000000001: n156_o = r15_cursor_l;
      default: n156_o = r15_cursor_l;
    endcase
  /* mc6845_fixed.vhd:236:41  */
  assign n157_o = n92_o ? n93_o : addr_reg;
  /* mc6845_fixed.vhd:236:41  */
  assign n158_o = n92_o ? r00_h_total : n139_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n159_o = n92_o ? r01_h_displayed : n140_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n160_o = n92_o ? r02_h_sync_pos : n141_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n161_o = n92_o ? r03_v_sync_width : n142_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n162_o = n92_o ? r03_h_sync_width : n143_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n163_o = n92_o ? r04_v_total : n144_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n164_o = n92_o ? r05_v_total_adj : n145_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n165_o = n92_o ? r06_v_displayed : n146_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n166_o = n92_o ? r07_v_sync_pos : n147_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n167_o = n92_o ? r08_interlace : n148_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n168_o = n92_o ? r09_max_scan_line_addr : n149_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n169_o = n92_o ? r10_cursor_mode : n150_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n170_o = n92_o ? r10_cursor_start : n151_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n171_o = n92_o ? r11_cursor_end : n152_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n172_o = n92_o ? r12_start_addr_h : n153_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n173_o = n92_o ? r13_start_addr_l : n154_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n174_o = n92_o ? r14_cursor_h : n155_o;
  /* mc6845_fixed.vhd:236:41  */
  assign n175_o = n92_o ? r15_cursor_l : n156_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n177_o = R_nW ? addr_reg : n157_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n178_o = R_nW ? r00_h_total : n158_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n179_o = R_nW ? r01_h_displayed : n159_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n180_o = R_nW ? r02_h_sync_pos : n160_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n181_o = R_nW ? r03_v_sync_width : n161_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n182_o = R_nW ? r03_h_sync_width : n162_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n183_o = R_nW ? r04_v_total : n163_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n184_o = R_nW ? r05_v_total_adj : n164_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n185_o = R_nW ? r06_v_displayed : n165_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n186_o = R_nW ? r07_v_sync_pos : n166_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n187_o = R_nW ? r08_interlace : n167_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n188_o = R_nW ? r09_max_scan_line_addr : n168_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n189_o = R_nW ? r10_cursor_mode : n169_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n190_o = R_nW ? r10_cursor_start : n170_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n191_o = R_nW ? r11_cursor_end : n171_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n192_o = R_nW ? r12_start_addr_h : n172_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n193_o = R_nW ? r13_start_addr_l : n173_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n194_o = R_nW ? r14_cursor_h : n174_o;
  /* mc6845_fixed.vhd:216:33  */
  assign n195_o = R_nW ? r15_cursor_l : n175_o;
  /* mc6845_fixed.vhd:215:25  */
  assign n196_o = R_nW & ENABLE;
  /* mc6845_fixed.vhd:285:18  */
  always @*
    n277_ma_row_start = n441_q; // (isignal)
  initial
    n277_ma_row_start = 14'bX;
  /* mc6845_fixed.vhd:288:18  */
  always @*
    n277_in_adj = n447_q; // (isignal)
  initial
    n277_in_adj = 1'bX;
  /* mc6845_fixed.vhd:291:27  */
  assign n284_o = ~nRESET;
  /* mc6845_fixed.vhd:314:46  */
  assign n286_o = h_counter == r00_h_total;
  /* mc6845_fixed.vhd:319:60  */
  assign n288_o = r05_v_total_adj != 5'b00000;
  /* mc6845_fixed.vhd:319:65  */
  assign n289_o = n288_o | odd_field;
  /* mc6845_fixed.vhd:319:41  */
  assign n292_o = n289_o ? 1'b1 : 1'b0;
  /* mc6845_fixed.vhd:326:51  */
  assign n293_o = ~n277_in_adj;
  /* mc6845_fixed.vhd:331:82  */
  assign n295_o = r05_v_total_adj - 5'b00001;
  /* mc6845_fixed.vhd:334:73  */
  assign n296_o = r08_interlace[1:0];
  /* mc6845_fixed.vhd:334:86  */
  assign n298_o = n296_o == 2'b11;
  /* mc6845_fixed.vhd:335:96  */
  assign n300_o = n295_o + 5'b00010;
  /* mc6845_fixed.vhd:337:96  */
  assign n302_o = n295_o + 5'b00001;
  /* mc6845_fixed.vhd:344:57  */
  assign n306_o = r08_interlace[1:0];
  /* mc6845_fixed.vhd:344:70  */
  assign n308_o = n306_o == 2'b11;
  assign n310_o = r09_max_scan_line_addr[0];
  assign n311_o = n300_o[0];
  assign n312_o = n302_o[0];
  /* mc6845_fixed.vhd:334:57  */
  assign n313_o = n298_o ? n311_o : n312_o;
  assign n314_o = n295_o[0];
  /* mc6845_fixed.vhd:333:49  */
  assign n315_o = odd_field ? n313_o : n314_o;
  /* mc6845_fixed.vhd:326:41  */
  assign n316_o = n293_o ? n310_o : n315_o;
  /* mc6845_fixed.vhd:344:41  */
  assign n317_o = n308_o ? 1'b0 : n316_o;
  assign n318_o = r09_max_scan_line_addr[4:1];
  assign n319_o = n300_o[4:1];
  assign n320_o = n302_o[4:1];
  /* mc6845_fixed.vhd:334:57  */
  assign n321_o = n298_o ? n319_o : n320_o;
  assign n322_o = n295_o[4:1];
  /* mc6845_fixed.vhd:333:49  */
  assign n323_o = odd_field ? n321_o : n322_o;
  /* mc6845_fixed.vhd:326:41  */
  assign n324_o = n293_o ? n318_o : n323_o;
  assign n325_o = {n324_o, n317_o};
  /* mc6845_fixed.vhd:348:57  */
  assign n326_o = line_counter == n325_o;
  /* mc6845_fixed.vhd:348:88  */
  assign n327_o = ~n292_o;
  /* mc6845_fixed.vhd:348:110  */
  assign n328_o = row_counter == r04_v_total;
  /* mc6845_fixed.vhd:348:94  */
  assign n329_o = n328_o & n327_o;
  /* mc6845_fixed.vhd:348:125  */
  assign n330_o = n329_o | n277_in_adj;
  /* mc6845_fixed.vhd:348:73  */
  assign n331_o = n330_o & n326_o;
  /* mc6845_fixed.vhd:356:65  */
  assign n332_o = r08_interlace[0];
  /* mc6845_fixed.vhd:356:49  */
  assign n334_o = n332_o ? odd_field : 1'b0;
  /* mc6845_fixed.vhd:364:82  */
  assign n335_o = {r12_start_addr_h, r13_start_addr_l};
  /* mc6845_fixed.vhd:368:80  */
  assign n337_o = field_counter + 5'b00001;
  /* mc6845_fixed.vhd:374:54  */
  assign n338_o = ~n277_in_adj;
  assign n339_o = {n324_o, n317_o};
  /* mc6845_fixed.vhd:374:77  */
  assign n340_o = line_counter == n339_o;
  /* mc6845_fixed.vhd:374:60  */
  assign n341_o = n340_o & n338_o;
  /* mc6845_fixed.vhd:380:78  */
  assign n342_o = {6'b0, r01_h_displayed};  //  uext
  /* mc6845_fixed.vhd:380:78  */
  assign n343_o = n277_ma_row_start + n342_o;
  /* mc6845_fixed.vhd:381:76  */
  assign n345_o = row_counter + 7'b0000001;
  /* mc6845_fixed.vhd:384:64  */
  assign n346_o = row_counter == r04_v_total;
  /* mc6845_fixed.vhd:384:78  */
  assign n347_o = n292_o & n346_o;
  /* mc6845_fixed.vhd:374:41  */
  assign n349_o = n366_o ? 1'b1 : in_adj_s;
  /* mc6845_fixed.vhd:374:41  */
  assign n351_o = n368_o ? 1'b1 : n277_in_adj;
  /* mc6845_fixed.vhd:390:65  */
  assign n352_o = r08_interlace[1:0];
  /* mc6845_fixed.vhd:390:78  */
  assign n354_o = n352_o == 2'b11;
  /* mc6845_fixed.vhd:391:86  */
  assign n356_o = line_counter + 5'b00010;
  assign n358_o = n356_o[4:1];
  /* mc6845_fixed.vhd:394:86  */
  assign n360_o = line_counter + 5'b00001;
  assign n361_o = {n358_o, 1'b0};
  /* mc6845_fixed.vhd:390:49  */
  assign n362_o = n354_o ? n361_o : n360_o;
  /* mc6845_fixed.vhd:374:41  */
  assign n363_o = n341_o ? n345_o : row_counter;
  /* mc6845_fixed.vhd:374:41  */
  assign n365_o = n341_o ? 5'b00000 : n362_o;
  /* mc6845_fixed.vhd:374:41  */
  assign n366_o = n347_o & n341_o;
  /* mc6845_fixed.vhd:374:41  */
  assign n367_o = n341_o ? n343_o : n277_ma_row_start;
  /* mc6845_fixed.vhd:374:41  */
  assign n368_o = n347_o & n341_o;
  /* mc6845_fixed.vhd:348:41  */
  assign n370_o = n331_o ? 7'b0000000 : n363_o;
  /* mc6845_fixed.vhd:348:41  */
  assign n372_o = n331_o ? 5'b00000 : n365_o;
  /* mc6845_fixed.vhd:348:41  */
  assign n375_o = n331_o ? 1'b0 : n349_o;
  /* mc6845_fixed.vhd:348:41  */
  assign n377_o = n331_o ? n335_o : n367_o;
  /* mc6845_fixed.vhd:348:41  */
  assign n379_o = n331_o ? 1'b0 : n351_o;
  /* mc6845_fixed.vhd:403:64  */
  assign n381_o = h_counter + 8'b00000001;
  /* mc6845_fixed.vhd:405:54  */
  assign n383_o = ma_i + 14'b00000000000001;
  /* mc6845_fixed.vhd:314:33  */
  assign n385_o = n286_o ? 8'b00000000 : n381_o;
  /* mc6845_fixed.vhd:314:33  */
  assign n388_o = n331_o & n286_o;
  /* mc6845_fixed.vhd:314:33  */
  assign n390_o = n331_o & n286_o;
  /* mc6845_fixed.vhd:314:33  */
  assign n391_o = n286_o ? n377_o : n383_o;
  /* mc6845_fixed.vhd:311:25  */
  assign n398_o = n286_o & CLKEN;
  /* mc6845_fixed.vhd:311:25  */
  assign n399_o = n286_o & CLKEN;
  /* mc6845_fixed.vhd:311:25  */
  assign n400_o = n388_o & CLKEN;
  /* mc6845_fixed.vhd:311:25  */
  assign n401_o = n286_o & CLKEN;
  /* mc6845_fixed.vhd:311:25  */
  assign n402_o = n390_o & CLKEN;
  /* mc6845_fixed.vhd:311:25  */
  assign n404_o = n286_o & CLKEN;
  /* mc6845_fixed.vhd:311:25  */
  assign n406_o = n286_o & CLKEN;
  /* mc6845_fixed.vhd:310:17  */
  assign n440_o = n404_o ? n377_o : n277_ma_row_start;
  /* mc6845_fixed.vhd:310:17  */
  always @(posedge CLOCK or posedge n284_o)
    if (n284_o)
      n441_q <= 14'b00000000000000;
    else
      n441_q <= n440_o;
  /* mc6845_fixed.vhd:310:17  */
  assign n446_o = n406_o ? n379_o : n277_in_adj;
  /* mc6845_fixed.vhd:310:17  */
  always @(posedge CLOCK or posedge n284_o)
    if (n284_o)
      n447_q <= 1'b0;
    else
      n447_q <= n446_o;
  /* mc6845_fixed.vhd:417:30  */
  assign n454_o = h_counter == r02_h_sync_pos;
  /* mc6845_fixed.vhd:417:17  */
  assign n457_o = n454_o ? 1'b1 : 1'b0;
  /* mc6845_fixed.vhd:426:30  */
  assign n459_o = h_counter == r02_h_sync_pos;
  /* mc6845_fixed.vhd:426:17  */
  assign n462_o = n459_o ? 1'b1 : 1'b0;
  /* mc6845_fixed.vhd:431:49  */
  assign n466_o = $unsigned(h_counter) < $unsigned(r01_h_displayed);
  /* mc6845_fixed.vhd:431:32  */
  assign n467_o = n466_o ? 1'b1 : 1'b0;
  /* mc6845_fixed.vhd:435:49  */
  assign n470_o = $unsigned(row_counter) < $unsigned(r06_v_displayed);
  /* mc6845_fixed.vhd:435:80  */
  assign n471_o = ~in_adj_s;
  /* mc6845_fixed.vhd:435:67  */
  assign n472_o = n471_o & n470_o;
  /* mc6845_fixed.vhd:435:32  */
  assign n473_o = n472_o ? 1'b1 : 1'b0;
  /* mc6845_fixed.vhd:440:27  */
  assign n477_o = ~nRESET;
  /* mc6845_fixed.vhd:456:55  */
  assign n479_o = h_sync_start | hs;
  /* mc6845_fixed.vhd:459:74  */
  assign n481_o = h_sync_counter + 4'b0001;
  /* mc6845_fixed.vhd:456:33  */
  assign n483_o = n479_o ? n481_o : 4'b0000;
  /* mc6845_fixed.vhd:456:33  */
  assign n485_o = n479_o ? 1'b1 : hs;
  /* mc6845_fixed.vhd:463:51  */
  assign n486_o = h_sync_counter == r03_h_sync_width;
  /* mc6845_fixed.vhd:463:33  */
  assign n488_o = n486_o ? 1'b0 : n485_o;
  /* mc6845_fixed.vhd:475:57  */
  assign n489_o = row_counter == r07_v_sync_pos;
  /* mc6845_fixed.vhd:475:91  */
  assign n491_o = line_counter == 5'b00000;
  /* mc6845_fixed.vhd:475:74  */
  assign n492_o = n491_o & n489_o;
  /* mc6845_fixed.vhd:475:96  */
  assign n493_o = n492_o | vs;
  /* mc6845_fixed.vhd:478:82  */
  assign n495_o = v_sync_counter + 4'b0001;
  /* mc6845_fixed.vhd:475:41  */
  assign n497_o = n493_o ? n495_o : 4'b0000;
  /* mc6845_fixed.vhd:475:41  */
  assign n499_o = n493_o ? 1'b1 : vs;
  /* mc6845_fixed.vhd:482:59  */
  assign n500_o = v_sync_counter == r03_v_sync_width;
  /* mc6845_fixed.vhd:482:78  */
  assign n501_o = vs & n500_o;
  /* mc6845_fixed.vhd:482:41  */
  assign n503_o = n501_o ? 1'b0 : n499_o;
  /* mc6845_fixed.vhd:451:25  */
  assign n507_o = v_sync_start & CLKEN;
  /* mc6845_fixed.vhd:451:25  */
  assign n511_o = v_sync_start & CLKEN;
  /* mc6845_fixed.vhd:496:27  */
  assign n534_o = ~nRESET;
  /* mc6845_fixed.vhd:505:49  */
  assign n536_o = r08_interlace[1:0];
  /* mc6845_fixed.vhd:505:62  */
  assign n538_o = n536_o == 2'b11;
  /* mc6845_fixed.vhd:508:55  */
  assign n539_o = line_counter[4:1];
  /* mc6845_fixed.vhd:508:79  */
  assign n540_o = line_counter[0];
  /* mc6845_fixed.vhd:508:83  */
  assign n541_o = n540_o | odd_field;
  /* mc6845_fixed.vhd:508:68  */
  assign n542_o = {n539_o, n541_o};
  /* mc6845_fixed.vhd:505:33  */
  assign n543_o = n538_o ? n542_o : line_counter;
  /* mc6845_fixed.vhd:520:18  */
  always @*
    n560_cursor_line = n592_q; // (isignal)
  initial
    n560_cursor_line = 1'bX;
  /* mc6845_fixed.vhd:524:27  */
  assign n563_o = ~nRESET;
  /* mc6845_fixed.vhd:529:58  */
  assign n565_o = v_display_early & h_display_early;
  /* mc6845_fixed.vhd:529:108  */
  assign n566_o = {r14_cursor_h, r15_cursor_l};
  /* mc6845_fixed.vhd:529:93  */
  assign n567_o = ma_i == n566_o;
  /* mc6845_fixed.vhd:529:84  */
  assign n568_o = n567_o & n565_o;
  /* mc6845_fixed.vhd:530:57  */
  assign n570_o = line_counter == 5'b00000;
  /* mc6845_fixed.vhd:530:41  */
  assign n572_o = n570_o ? 1'b0 : n560_cursor_line;
  /* mc6845_fixed.vhd:534:57  */
  assign n573_o = line_counter == r10_cursor_start;
  /* mc6845_fixed.vhd:534:41  */
  assign n575_o = n573_o ? 1'b1 : n572_o;
  /* mc6845_fixed.vhd:543:57  */
  assign n576_o = line_counter == r11_cursor_end;
  /* mc6845_fixed.vhd:543:41  */
  assign n578_o = n576_o ? 1'b0 : n575_o;
  /* mc6845_fixed.vhd:529:33  */
  assign n580_o = n568_o ? n575_o : 1'b0;
  /* mc6845_fixed.vhd:528:25  */
  assign n583_o = n568_o & CLKEN;
  /* mc6845_fixed.vhd:527:17  */
  assign n591_o = n583_o ? n578_o : n560_cursor_line;
  /* mc6845_fixed.vhd:527:17  */
  always @(posedge CLOCK or posedge n563_o)
    if (n563_o)
      n592_q <= 1'b0;
    else
      n592_q <= n591_o;
  /* mc6845_fixed.vhd:559:27  */
  assign n595_o = ~nRESET;
  /* mc6845_fixed.vhd:568:60  */
  assign n597_o = ~lpstb_i;
  /* mc6845_fixed.vhd:568:48  */
  assign n598_o = n597_o & LPSTB;
  /* mc6845_fixed.vhd:570:64  */
  assign n599_o = ma_i[13:8];
  /* mc6845_fixed.vhd:571:64  */
  assign n600_o = ma_i[7:0];
  /* mc6845_fixed.vhd:564:25  */
  assign n603_o = n598_o & CLKEN;
  /* mc6845_fixed.vhd:564:25  */
  assign n604_o = n598_o & CLKEN;
  /* mc6845_fixed.vhd:214:17  */
  assign n630_o = ENABLE ? n177_o : addr_reg;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n631_q <= 5'b00000;
    else
      n631_q <= n630_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n632_o = ENABLE ? n178_o : r00_h_total;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n633_q <= 8'b00000000;
    else
      n633_q <= n632_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n634_o = ENABLE ? n179_o : r01_h_displayed;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n635_q <= 8'b00000000;
    else
      n635_q <= n634_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n636_o = ENABLE ? n180_o : r02_h_sync_pos;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n637_q <= 8'b00000000;
    else
      n637_q <= n636_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n638_o = ENABLE ? n181_o : r03_v_sync_width;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n639_q <= 4'b0000;
    else
      n639_q <= n638_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n640_o = ENABLE ? n182_o : r03_h_sync_width;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n641_q <= 4'b0000;
    else
      n641_q <= n640_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n642_o = ENABLE ? n183_o : r04_v_total;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n643_q <= 7'b0000000;
    else
      n643_q <= n642_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n644_o = ENABLE ? n184_o : r05_v_total_adj;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n645_q <= 5'b00000;
    else
      n645_q <= n644_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n646_o = ENABLE ? n185_o : r06_v_displayed;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n647_q <= 7'b0000000;
    else
      n647_q <= n646_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n648_o = ENABLE ? n186_o : r07_v_sync_pos;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n649_q <= 7'b0000000;
    else
      n649_q <= n648_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n650_o = ENABLE ? n187_o : r08_interlace;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n651_q <= 8'b00000000;
    else
      n651_q <= n650_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n652_o = ENABLE ? n188_o : r09_max_scan_line_addr;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n653_q <= 5'b00000;
    else
      n653_q <= n652_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n654_o = ENABLE ? n189_o : r10_cursor_mode;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n655_q <= 2'b00;
    else
      n655_q <= n654_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n656_o = ENABLE ? n190_o : r10_cursor_start;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n657_q <= 5'b00000;
    else
      n657_q <= n656_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n658_o = ENABLE ? n191_o : r11_cursor_end;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n659_q <= 5'b00000;
    else
      n659_q <= n658_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n660_o = ENABLE ? n192_o : r12_start_addr_h;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n661_q <= 6'b000000;
    else
      n661_q <= n660_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n662_o = ENABLE ? n193_o : r13_start_addr_l;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n663_q <= 8'b00000000;
    else
      n663_q <= n662_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n664_o = ENABLE ? n194_o : r14_cursor_h;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n665_q <= 6'b000000;
    else
      n665_q <= n664_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n666_o = ENABLE ? n195_o : r15_cursor_l;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n667_q <= 8'b00000000;
    else
      n667_q <= n666_o;
  /* mc6845_fixed.vhd:563:17  */
  assign n668_o = n603_o ? n599_o : r16_light_pen_h;
  /* mc6845_fixed.vhd:563:17  */
  always @(posedge CLOCK or posedge n595_o)
    if (n595_o)
      n669_q <= 6'b000000;
    else
      n669_q <= n668_o;
  /* mc6845_fixed.vhd:563:17  */
  assign n670_o = n604_o ? n600_o : r17_light_pen_l;
  /* mc6845_fixed.vhd:563:17  */
  always @(posedge CLOCK or posedge n595_o)
    if (n595_o)
      n671_q <= 8'b00000000;
    else
      n671_q <= n670_o;
  /* mc6845_fixed.vhd:310:17  */
  assign n672_o = CLKEN ? n385_o : h_counter;
  /* mc6845_fixed.vhd:310:17  */
  always @(posedge CLOCK or posedge n284_o)
    if (n284_o)
      n673_q <= 8'b00000000;
    else
      n673_q <= n672_o;
  /* mc6845_fixed.vhd:450:17  */
  assign n674_o = CLKEN ? n483_o : h_sync_counter;
  /* mc6845_fixed.vhd:450:17  */
  always @(posedge CLOCK or posedge n477_o)
    if (n477_o)
      n675_q <= 4'b0000;
    else
      n675_q <= n674_o;
  /* mc6845_fixed.vhd:310:17  */
  assign n676_o = n398_o ? n370_o : row_counter;
  /* mc6845_fixed.vhd:310:17  */
  always @(posedge CLOCK or posedge n284_o)
    if (n284_o)
      n677_q <= 7'b0000000;
    else
      n677_q <= n676_o;
  /* mc6845_fixed.vhd:310:17  */
  assign n678_o = n399_o ? n372_o : line_counter;
  /* mc6845_fixed.vhd:310:17  */
  always @(posedge CLOCK or posedge n284_o)
    if (n284_o)
      n679_q <= 5'b00000;
    else
      n679_q <= n678_o;
  /* mc6845_fixed.vhd:450:17  */
  assign n680_o = n507_o ? n497_o : v_sync_counter;
  /* mc6845_fixed.vhd:450:17  */
  always @(posedge CLOCK or posedge n477_o)
    if (n477_o)
      n681_q <= 4'b0000;
    else
      n681_q <= n680_o;
  /* mc6845_fixed.vhd:310:17  */
  assign n682_o = n400_o ? n337_o : field_counter;
  /* mc6845_fixed.vhd:310:17  */
  always @(posedge CLOCK or posedge n284_o)
    if (n284_o)
      n683_q <= 5'b00000;
    else
      n683_q <= n682_o;
  /* mc6845_fixed.vhd:450:17  */
  assign n684_o = CLKEN ? h_display_early : h_display;
  /* mc6845_fixed.vhd:450:17  */
  always @(posedge CLOCK or posedge n477_o)
    if (n477_o)
      n685_q <= 1'b0;
    else
      n685_q <= n684_o;
  /* mc6845_fixed.vhd:450:17  */
  assign n686_o = CLKEN ? n488_o : hs;
  /* mc6845_fixed.vhd:450:17  */
  always @(posedge CLOCK or posedge n477_o)
    if (n477_o)
      n687_q <= 1'b0;
    else
      n687_q <= n686_o;
  /* mc6845_fixed.vhd:450:17  */
  assign n688_o = CLKEN ? v_display_early : v_display;
  /* mc6845_fixed.vhd:450:17  */
  always @(posedge CLOCK or posedge n477_o)
    if (n477_o)
      n689_q <= 1'b0;
    else
      n689_q <= n688_o;
  /* mc6845_fixed.vhd:310:17  */
  assign n690_o = n401_o ? n375_o : in_adj_s;
  /* mc6845_fixed.vhd:310:17  */
  always @(posedge CLOCK or posedge n284_o)
    if (n284_o)
      n691_q <= 1'b0;
    else
      n691_q <= n690_o;
  /* mc6845_fixed.vhd:450:17  */
  assign n692_o = n511_o ? n503_o : vs;
  /* mc6845_fixed.vhd:450:17  */
  always @(posedge CLOCK or posedge n477_o)
    if (n477_o)
      n693_q <= 1'b0;
    else
      n693_q <= n692_o;
  /* mc6845_fixed.vhd:310:17  */
  assign n694_o = n402_o ? n334_o : odd_field;
  /* mc6845_fixed.vhd:310:17  */
  always @(posedge CLOCK or posedge n284_o)
    if (n284_o)
      n695_q <= 1'b0;
    else
      n695_q <= n694_o;
  /* mc6845_fixed.vhd:310:17  */
  assign n696_o = CLKEN ? n391_o : ma_i;
  /* mc6845_fixed.vhd:310:17  */
  always @(posedge CLOCK or posedge n284_o)
    if (n284_o)
      n697_q <= 14'b00000000000000;
    else
      n697_q <= n696_o;
  /* mc6845_fixed.vhd:527:17  */
  assign n699_o = CLKEN ? n580_o : cursor_i;
  /* mc6845_fixed.vhd:527:17  */
  always @(posedge CLOCK or posedge n563_o)
    if (n563_o)
      n700_q <= 1'b0;
    else
      n700_q <= n699_o;
  /* mc6845_fixed.vhd:563:17  */
  assign n701_o = CLKEN ? LPSTB : lpstb_i;
  /* mc6845_fixed.vhd:563:17  */
  always @(posedge CLOCK or posedge n595_o)
    if (n595_o)
      n702_q <= 1'b0;
    else
      n702_q <= n701_o;
  /* mc6845_fixed.vhd:580:17  */
  assign n703_o = CLKEN ? de0 : de1;
  /* mc6845_fixed.vhd:580:17  */
  always @(posedge CLOCK)
    n704_q <= n703_o;
  /* mc6845_fixed.vhd:580:17  */
  assign n705_o = CLKEN ? de1 : de2;
  /* mc6845_fixed.vhd:580:17  */
  always @(posedge CLOCK)
    n706_q <= n705_o;
  /* mc6845_fixed.vhd:580:17  */
  assign n707_o = CLKEN ? cursor0 : cursor1;
  /* mc6845_fixed.vhd:580:17  */
  always @(posedge CLOCK)
    n708_q <= n707_o;
  /* mc6845_fixed.vhd:580:17  */
  assign n710_o = CLKEN ? hblank0 : hblank1;
  /* mc6845_fixed.vhd:580:17  */
  always @(posedge CLOCK)
    n711_q <= n710_o;
  /* mc6845_fixed.vhd:580:17  */
  assign n712_o = CLKEN ? hblank1 : hblank2;
  /* mc6845_fixed.vhd:580:17  */
  always @(posedge CLOCK)
    n713_q <= n712_o;
  /* mc6845_fixed.vhd:214:17  */
  assign n714_o = n196_o ? n91_o : n715_q;
  /* mc6845_fixed.vhd:214:17  */
  always @(posedge CLOCK or posedge n69_o)
    if (n69_o)
      n715_q <= 8'b00000000;
    else
      n715_q <= n714_o;
  /* mc6845_fixed.vhd:499:17  */
  assign n716_o = CLKEN ? ma_i : n717_q;
  /* mc6845_fixed.vhd:499:17  */
  always @(posedge CLOCK or posedge n534_o)
    if (n534_o)
      n717_q <= 14'b00000000000000;
    else
      n717_q <= n716_o;
  /* mc6845_fixed.vhd:499:17  */
  assign n718_o = CLKEN ? n543_o : n719_q;
  /* mc6845_fixed.vhd:499:17  */
  always @(posedge CLOCK or posedge n534_o)
    if (n534_o)
      n719_q <= 5'b00000;
    else
      n719_q <= n718_o;
endmodule

