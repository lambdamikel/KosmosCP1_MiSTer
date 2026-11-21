// Board + picture, for sim/tb_video.cpp.
module sim_top
(
	input         clk, reset, mcyc,
	input  [19:0] keys,
	input   [7:0] sw, port3_in,
	input         xwire,
	input         ld_we,
	input   [7:0] ld_addr,
	input  [15:0] ld_word,
	output        executed,
	output        ce_pix, HS, VS, HBlank, VBlank,
	output  [7:0] R, G, B
);
wire [383:0] seg_level;
wire   [7:0] port1, port2, port4, port5, pins;
cp1 board(.clk(clk), .reset(reset), .mcyc(mcyc), .executed(executed), .fetch(),
	.keys(keys), .port1_in(sw), .port3_in(port3_in), .xwire(xwire), .ld_we(ld_we), .ld_cell(ld_addr), .ld_word(ld_word),
	.port1(port1), .port2(port2), .port4(port4), .port5(port5), .port1_pins(pins), .seg_level(seg_level));
video video(.clk(clk), .seg_level(seg_level), .port2(port2), .sw(sw), .pins(pins), .keys(keys),
	.ce_pix(ce_pix), .R(R), .G(G), .B(B), .HS(HS), .VS(VS), .HBlank(HBlank), .VBlank(VBlank));
endmodule
