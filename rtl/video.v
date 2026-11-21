// 640x480 picture of the Kosmos CP1: the I/O module (Port 2 LEDs, Port 1 switches with a lamp per
// line), the six-digit display, the kosmos plate, and the keypad with the number block.  Shapes are
// drawn here; labels come from a text layer (rtl/text.hex, 80x30 cells of 8x16, made by
// tools/mklayout.py, whose positions match the coordinates below).

module video
(
	input              clk,           // 50 MHz; one pixel every second clock
	input      [383:0] seg_level,     // digit d (0 = leftmost), segment b: [(d*8+b)*8 +: 8]
	input        [7:0] port2,         // Port 2 outputs (LED on for a 1)
	input        [7:0] sw,            // Port 1 switch positions (1 = up)
	input        [7:0] pins,          // levels on the Port 1 terminals (lamp on for a 1)
	input       [19:0] keys,          // held keys, bit = row*4 + column as in the emulator's CP1_KEYS

	output reg         ce_pix,
	output reg   [7:0] R, G, B,
	output reg         HS, VS, HBlank, VBlank
);

// ---- timing: 640x480, 800x525 total, 25 MHz pixel clock ----
reg [9:0] h0 = 0, v0 = 0;
always @(posedge clk) ce_pix <= ~ce_pix;
initial ce_pix = 0;
always @(posedge clk) if (ce_pix) begin
	if (h0 == 799) begin h0 <= 0; v0 <= (v0 == 524) ? 10'd0 : v0 + 1'd1; end
	else h0 <= h0 + 1'd1;
end

// ---- text layer: {shift, colour[2:0], char}; a shifted cell is drawn 4 pixels to the right ----
reg [11:0] text[0:4095];
reg  [7:0] font[0:4095];
initial $readmemh("rtl/text.hex", text);
initial $readmemh("rtl/font.hex", font);
reg [11:0] tq, tqb;
reg  [7:0] fq, fqb;
reg  [3:0] tcol, tcolb;
reg  [9:0] h1, v1, h2, v2;
wire [11:0] trow   = {v0[8:4], 6'd0} + {2'd0, v0[8:4], 4'd0};
wire  [9:0] hb     = h0 - 10'd4;
wire [11:0] taddr  = trow + {5'd0, h0[9:3]};
wire [11:0] taddrb = (h0 < 4) ? 12'd4095 : trow + {5'd0, hb[9:3]};
always @(posedge clk) if (ce_pix) begin
	tq <= text[taddr]; tqb <= text[taddrb];
	h1 <= h0; v1 <= v0;
	fq <= font[{tq[7:0], v1[3:0]}]; fqb <= font[{tqb[7:0], v1[3:0]}];
	tcol <= tq[11:8]; tcolb <= tqb[11:8];
	h2 <= h1; v2 <= v1;
end

// ---- helpers ----
function [7:0] mix(input [7:0] off, input [7:0] on, input [7:0] lvl);   // off + (on-off)*lvl/256
	reg [15:0] p;
	begin p = (on - off) * lvl; mix = off + p[15:8]; end
endfunction
function [7:0] sq(input [3:0] v); sq = v * v; endfunction
function circ(input [9:0] x, input [9:0] y, input [9:0] cx, input [9:0] cy, input [8:0] r2);   // radius <= 15
	reg [10:0] dx, dy; reg [3:0] ax, ay;
	begin
		dx = {1'b0, x} - {1'b0, cx}; dy = {1'b0, y} - {1'b0, cy};
		ax = dx[10] ? -dx[3:0] : dx[3:0]; ay = dy[10] ? -dy[3:0] : dy[3:0];
		if ((dx[10] ? (-dx > 11'd15) : (dx > 11'd15)) || (dy[10] ? (-dy > 11'd15) : (dy > 11'd15))) circ = 1'b0;
		else circ = ({1'b0, sq(ax)} + {1'b0, sq(ay)}) <= r2;
	end
endfunction
function inbox(input [9:0] x, input [9:0] y, input [9:0] x0, input [9:0] y0, input [9:0] x1, input [9:0] y1);
	inbox = x >= x0 && x <= x1 && y >= y0 && y <= y1;
endfunction

localparam [23:0] C_BG    = 24'h1c1f1e, C_CASE  = 24'h3d4542, C_MOD  = 24'h323937, C_MODED = 24'h262c2a,
                  C_LEDRIM = 24'h3a0c0c, C_SWB  = 24'h161616, C_LEVER = 24'hd4d4d0, C_LAMPOFF = 24'h3c3a24, C_LAMPON = 24'hf6d040,
                  C_BEZEL = 24'h2a2a2c, C_WIN   = 24'h1e0606, C_GRILL = 24'h262c2a,
                  C_PAD   = 24'h121212, C_KEY   = 24'he6e6e2, C_KEYHI = 24'hffffff, C_KEYLO = 24'h9a9a96, C_KEYDN = 24'hf2c21a;

// ---- layout ----
localparam [9:0] LEDY = 68, LAMPY = 44, SWY0 = 52, SWY1 = 91;
function [9:0] ledx(input [2:0] i); ledx = 10'd92 + 32*i; endfunction       // Port 2 LEDs, lines 1-8
function [9:0] swx(input [2:0] i);  swx  = 10'd372 + 32*i; endfunction      // Port 1 switches, lines 1-8

// display: groups 1 + 2 + 3; digit d starts at DXB + offset, 56 pixels high from DY0
localparam [9:0] DXB = 58, DY0 = 160;
function [9:0] digx(input [2:0] d);
	case (d) 3'd0: digx = 0; 3'd1: digx = 56; 3'd2: digx = 96; 3'd3: digx = 152; 3'd4: digx = 192; default: digx = 232; endcase
endfunction

// keys: index -> centre x, text row (key = row*16-5 .. +22), half width, key bit.
// One grid: columns 40 pixels apart, keys 36 wide (4-pixel gaps, as between the rows), 10 pixels
// from the panel edge.  Digit row = columns 0-9 from x 54; STEP STP RUN CAL span columns 1-2, 3-4,
// 5-6, 7-8; CLR ACC CAS and PC OUT INP span 2-3, 4-5, 6-7; the number block has its own three
// columns from x 470, 20 pixels right of the 9, and its 0 spans the first two.
function [33:0] key(input [4:0] k);     // {cx[9:0], row[4:0], hw[6:0], bit[4:0], valid, pad[5:0]}
	reg [9:0] cx; reg [4:0] row; reg [6:0] hw; reg [4:0] b;
	begin
		if (k < 10) begin cx = 10'd72 + 40*k; row = 17; hw = 18;
			case (k) 0: b = 16; 1: b = 17; 2: b = 18; 3: b = 19; 4: b = 12; 5: b = 13; 6: b = 14; 7: b = 15; 8: b = 8; default: b = 9; endcase end
		else if (k < 14) begin cx = 10'd132 + 80*(k-10); row = 19; hw = 38;                // STEP STP RUN CAL
			case (k) 10: b = 5; 11: b = 6; 12: b = 7; default: b = 4; endcase end
		else if (k < 17) begin cx = 10'd172 + 80*(k-14); row = 21; hw = 38;                // CLR ACC CAS
			case (k) 14: b = 1; 15: b = 3; default: b = 0; endcase end
		else if (k < 20) begin cx = 10'd172 + 80*(k-17); row = 23; hw = 38;                // PC OUT INP
			case (k) 17: b = 2; 18: b = 10; default: b = 11; endcase end
		else if (k < 29) begin cx = 10'd488 + 40*((k-20) % 3); row = 17 + 2*((k-20) / 3); hw = 18;   // 7 8 9 / 4 5 6 / 1 2 3
			case (k) 20: b = 15; 21: b = 8; 22: b = 9; 23: b = 12; 24: b = 13; 25: b = 14; 26: b = 17; 27: b = 18; default: b = 19; endcase end
		else begin cx = 10'd508; row = 23; hw = 38; b = 16; end                            // 0
		key = {cx, row, hw, b, 1'b1, 6'd0};
	end
endfunction

// ---- the picture ----
reg [23:0] px;
reg  [2:0] d;
reg  [9:0] lx, ly;
reg [10:0] lxs;
reg  [3:0] sg;
reg  [7:0] lvl;
reg        tbit;
reg  [2:0] tc;
reg [33:0] kk;
reg  [9:0] kx0, kx1, ky0, ky1;
integer i, k;

always @* begin
	px = C_BG;
	if (inbox(h2, v2, 16, 16, 623, 463)) px = C_CASE;
	// I/O module
	if (inbox(h2, v2, 24, 16, 615, 119)) px = (h2 < 26 || h2 > 613 || v2 > 117) ? C_MODED : C_MOD;
	for (i = 0; i < 8; i = i + 1) begin
		if (circ(h2, v2, ledx(i), LEDY, 81)) px = C_LEDRIM;
		if (circ(h2, v2, ledx(i), LEDY, 49)) px = port2[i] ? (circ(h2, v2, ledx(i) - 2, LEDY - 2, 6) ? 24'hffd0c0 : 24'hff3a24) : 24'h5a1010;
		if (circ(h2, v2, swx(i), LAMPY, 16)) px = pins[i] ? C_LAMPON : C_LAMPOFF;
		if (inbox(h2, v2, swx(i) - 8, SWY0, swx(i) + 7, SWY1)) px = C_SWB;
		if (inbox(h2, v2, swx(i) - 5, sw[i] ? SWY0 + 3 : SWY0 + 21, swx(i) + 4, sw[i] ? SWY0 + 18 : SWY0 + 36)) px = C_LEVER;
	end
	// display
	if (inbox(h2, v2, 42, 144, 343, 231)) px = inbox(h2, v2, 46, 148, 339, 227) ? C_WIN : C_BEZEL;
	sg = 4'd8; d = 0; lx = 0; ly = 0; lxs = 0; lvl = 0;
	if (v2 >= DY0 && v2 < DY0 + 56 && h2 >= DXB && h2 < DXB + 272) begin
		for (i = 0; i < 6; i = i + 1) if (h2 >= DXB + digx(i)) d = i;
		lx = h2 - DXB - digx(d);
		ly = v2 - DY0;
		lxs = {1'b0, lx} - ((11'd55 - {1'b0, ly}) >> 3);
		if (!lxs[10] && lx < 40) begin
			if      (ly <= 4  && lxs >= 4  && lxs <= 25) sg = 0;
			else if (ly >= 51 && lxs >= 4  && lxs <= 25) sg = 3;
			else if (ly >= 25 && ly <= 30 && lxs >= 4 && lxs <= 25) sg = 6;
			else if (lxs >= 25 && lxs <= 29 && ly >= 2  && ly <= 27) sg = 1;
			else if (lxs >= 25 && lxs <= 29 && ly >= 28 && ly <= 53) sg = 2;
			else if (lxs <= 4  && ly >= 28 && ly <= 53) sg = 4;
			else if (lxs <= 4  && ly >= 2  && ly <= 27) sg = 5;
			else if (lxs >= 32 && lxs <= 36 && ly >= 50) sg = 7;
		end
		if (sg != 8) begin
			lvl = seg_level[{d, sg[2:0], 3'd0} +: 8];
			px = {mix(8'h40, 8'hff, lvl), mix(8'h0a, 8'h3a, lvl), mix(8'h0a, 8'h28, lvl)};
		end
	end
	// kosmos plate in a speaker grille
	if (inbox(h2, v2, 370, 144, 597, 231)) px = (v2[2:0] < 3'd3) ? C_GRILL : C_CASE;
	if (inbox(h2, v2, 404, 172, 563, 211)) px = C_CASE;
	// keypad
	if (inbox(h2, v2, 42, 255, 597, 402)) px = (h2 < 44 || h2 > 595 || v2 < 257 || v2 > 400) ? 24'h080808 : C_PAD;
	for (k = 0; k < 30; k = k + 1) begin
		kk = key(k);
		kx0 = kk[33:24] - kk[18:12]; kx1 = kk[33:24] + kk[18:12] - 1'd1;
		ky0 = {kk[23:19], 4'd0} - 10'd5; ky1 = ky0 + 10'd27;
		if (inbox(h2, v2, kx0, ky0, kx1, ky1))
			px = keys[kk[11:7]] ? C_KEYDN :
			     (v2 <= ky0 + 1 || h2 <= kx0 + 1) ? C_KEYHI :
			     (v2 >= ky1 - 1 || h2 >= kx1 - 1) ? C_KEYLO : C_KEY;
	end
	// text on top
	if (tcolb[3])      begin tbit = fqb[~(h2[2:0] ^ 3'd4)]; tc = tcolb[2:0]; end
	else if (!tcol[3]) begin tbit = fq[~h2[2:0]];           tc = tcol[2:0];  end
	else               begin tbit = 1'b0;                   tc = 3'd0;       end
	if (tbit && v2 < 480 && h2 < 640) case (tc)
		3'd0: px = 24'h141414;
		3'd1: px = 24'hd8d8d8;
		3'd2: px = 24'h8a8a8e;
		3'd3: px = 24'hffffff;
		default: px = 24'hf2c21a;
	endcase
end

always @(posedge clk) if (ce_pix) begin
	{R, G, B} <= (h2 < 640 && v2 < 480) ? px : 24'h000000;
	HBlank <= h2 >= 640;
	VBlank <= v2 >= 480;
	HS <= h2 >= 656 && h2 < 752;
	VS <= v2 >= 490 && v2 < 492;
end

endmodule
