//============================================================================
//  Kosmos CP1 for MiSTer
//
//  The 1983 Kosmos "Computer-Praxis" experimental computer, running its original
//  Intel 8049 firmware ROM.  CPU and board are a port of the browser emulator
//  (lambdamikel/kosmos-cp1-emulator) and are checked against it in lockstep (sim/).
//
//  Made with Claude Opus 5.5 (Claude Code), together with Michael Wessel.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.  The firmware ROM (rtl/cp1_rom.hex) remains
//  (c) Franckh-Kosmos and is not covered by this licence.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_POWER = 0;
assign BUTTONS   = 0;

wire         clk_sys;
wire [127:0] status;

wire [1:0] ar = status[122:121];
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

// Status bits:
//  0      reset
//  1-2    speed
//  3      random-number wiring (Port 2 to Port 1)
//  4      tone generators on Port 2
//  5      tone generator on Port 4 off

`include "build_id.v"
localparam CONF_STR = {
	"KosmosCP1;;",
	"-;",
	"F1,CP1,Load program;",
	"-;",
	"O[2:1],Speed,Original,4x,16x,1/4x;",
	"-;",
	"O[3],Random-number wiring,Off,On;",
	"O[4],Tone generators on Port 2,Off,On;",
	"O[5],Tone generator on Port 4,On,Off;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"R[0],Reset;",
	"-;",
	"-,Version 1.1 - build ",`BUILD_DATE,";",
	"V,v1.1-",`BUILD_DATE
};

wire         forced_scandoubler;
wire   [1:0] buttons;
wire  [10:0] ps2_key;

wire         ioctl_download;
wire  [15:0] ioctl_index;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(1'b0),

	.ps2_key(ps2_key)
);

assign LED_DISK = {1'b0, ioctl_download};

///////////////////////   CLOCKS   ///////////////////////////////

pll pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_sys)        // 50 MHz
);

///////////////////////   KEYBOARD   /////////////////////////////

wire executed;                 // pulse after each instruction

// PC keys as in the browser emulator: 0-9 (and the number pad) digits, Enter/I INP, O OUT, P PC,
// A ACC, R RUN, H or . STP, T STEP, Delete/Backspace/X CLR, L CAL, S CAS, Esc switches off and on.
// F1-F8 toggle the Port 1 switches; Shift + 1-8 press a contact clip (the line goes low while held).
reg  [19:0] keys = 0;          // held keys, bit = row*4 + column as CP1_KEYS
reg  [19:0] pend = 0;          // releases waiting for the minimum hold time
reg  [15:0] held = 0;          // instructions since the last key press
reg   [7:0] sw = 8'hff;        // Port 1 switches, up = 1
reg   [7:0] clips = 0;         // contact clips pressed
reg         lshift = 0, rshift = 0;
reg         kbd_reset = 0;
reg         old_stb = 0;

wire        pressed = ps2_key[9];
wire        ext     = ps2_key[8];
wire  [7:0] code    = ps2_key[7:0];
wire        shift   = lshift | rshift;

reg   [4:0] kidx;              // key bit, 20 = none
reg   [3:0] clipn;             // Shift + 1-8: line, 8 = none
always @* begin
	kidx = 5'd20; clipn = 4'd8;
	if (!ext) case (code)
		8'h16: if (shift) clipn = 0; else kidx = 17;    // 1
		8'h1e: if (shift) clipn = 1; else kidx = 18;    // 2
		8'h26: if (shift) clipn = 2; else kidx = 19;    // 3
		8'h25: if (shift) clipn = 3; else kidx = 12;    // 4
		8'h2e: if (shift) clipn = 4; else kidx = 13;    // 5
		8'h36: if (shift) clipn = 5; else kidx = 14;    // 6
		8'h3d: if (shift) clipn = 6; else kidx = 15;    // 7
		8'h3e: if (shift) clipn = 7; else kidx = 8;     // 8
		8'h46: if (!shift) kidx = 9;                    // 9
		8'h45: if (!shift) kidx = 16;                   // 0
		8'h70: kidx = 16; 8'h69: kidx = 17; 8'h72: kidx = 18; 8'h7a: kidx = 19; 8'h6b: kidx = 12;   // number pad
		8'h73: kidx = 13; 8'h74: kidx = 14; 8'h6c: kidx = 15; 8'h75: kidx = 8;  8'h7d: kidx = 9;
		8'h5a, 8'h43: kidx = 11;          // INP: Enter, I
		8'h44: kidx = 10;                 // OUT: O
		8'h4d: kidx = 2;                  // PC: P
		8'h1c: kidx = 3;                  // ACC: A
		8'h2d: kidx = 7;                  // RUN: R
		8'h33, 8'h49: kidx = 6;           // STP: H, .
		8'h2c: kidx = 5;                  // STEP: T
		8'h66, 8'h22: kidx = 1;           // CLR: Backspace, X
		8'h4b: kidx = 4;                  // CAL: L
		8'h1b: kidx = 0;                  // CAS: S
		default: ;
	endcase
	else case (code)
		8'h5a: kidx = 11;                 // number pad Enter: INP
		8'h71: kidx = 1;                  // Delete: CLR
		default: ;
	endcase
end

always @(posedge clk_sys) begin
	kbd_reset <= 1'b0;
	old_stb <= ps2_key[10];
	if (executed && held != 16'hffff) held <= held + 1'd1;
	if (held >= 16'd16000 && pend != 0) begin keys <= keys & ~pend; pend <= 0; end   // hold ~24000 machine cycles, as the emulator
	if (old_stb != ps2_key[10]) begin
		if (kidx != 20) begin
			if (pressed) begin keys[kidx] <= 1'b1; pend[kidx] <= 1'b0; held <= 0; end
			else if (held >= 16'd16000) keys[kidx] <= 1'b0;
			else pend[kidx] <= 1'b1;
		end
		if (clipn != 8) clips[clipn[2:0]] <= pressed;
		if (!ext) case (code)
			8'h12: begin lshift <= pressed; if (!pressed && !rshift) clips <= 0; end
			8'h59: begin rshift <= pressed; if (!pressed && !lshift) clips <= 0; end
			8'h76: if (pressed) kbd_reset <= 1'b1;        // Esc: switch off and on
			8'h05: if (pressed) sw[0] <= ~sw[0];          // F1-F8: Port 1 switches
			8'h06: if (pressed) sw[1] <= ~sw[1];
			8'h04: if (pressed) sw[2] <= ~sw[2];
			8'h0c: if (pressed) sw[3] <= ~sw[3];
			8'h03: if (pressed) sw[4] <= ~sw[4];
			8'h0b: if (pressed) sw[5] <= ~sw[5];
			8'h83: if (pressed) sw[6] <= ~sw[6];
			8'h0a: if (pressed) sw[7] <= ~sw[7];
			default: ;
		endcase
	end
end

///////////////////////   MACHINE   //////////////////////////////

wire reset = RESET | status[0] | buttons[1] | kbd_reset;

// machine cycles: 400 000/s at the original speed = one every 125 clocks
// (accumulate 4 per clock against 500: 1, 4, 16 or 1/4 times that rate)
reg  [9:0] macc = 0;
reg        mcyc = 0;
wire [6:0] minc = status[2:1] == 2'd0 ? 7'd4 : status[2:1] == 2'd1 ? 7'd16 : status[2:1] == 2'd2 ? 7'd64 : 7'd1;
always @(posedge clk_sys) begin
	mcyc <= 1'b0;
	if (macc + minc >= 10'd500) begin macc <= macc + minc - 10'd500; mcyc <= 1'b1; end
	else macc <= macc + minc;
end

wire        ld_we;
wire  [7:0] ld_addr;
wire [15:0] ld_word;

cp1_loader loader
(
	.clk(clk_sys),
	.download(ioctl_download && ioctl_index[5:0] == 6'd1),
	.wr(ioctl_wr),
	.din(ioctl_dout),
	.we(ld_we), .addr(ld_addr), .word(ld_word)
);

wire [383:0] seg_level;
wire   [7:0] port1, port2, port4, port5, pins;

cp1 board
(
	.clk(clk_sys),
	.reset(reset),
	.mcyc(mcyc),
	.executed(executed),
	.fetch(),
	.keys(keys),
	.port1_in(sw & ~clips),
	.port3_in(8'hff),
	.xwire(status[3]),
	.ld_we(ld_we), .ld_cell(ld_addr), .ld_word(ld_word),
	.port1(port1), .port2(port2), .port4(port4), .port5(port5), .port1_pins(pins),
	.seg_level(seg_level)
);

///////////////////////   VIDEO   ////////////////////////////////

wire ce_pix, HBlank, VBlank, HSync, VSync;
wire [7:0] r, g, b;

video video
(
	.clk(clk_sys),
	.seg_level(seg_level),
	.port2(port2),
	.sw(sw & ~clips),
	.pins(pins),
	.keys(keys),
	.ce_pix(ce_pix),
	.R(r), .G(g), .B(b),
	.HS(HSync), .VS(VSync), .HBlank(HBlank), .VBlank(VBlank)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;
assign VGA_DE    = ~(HBlank | VBlank);
assign VGA_HS    = HSync;
assign VGA_VS    = VSync;
assign VGA_R     = r;
assign VGA_G     = g;
assign VGA_B     = b;

///////////////////////   SOUND   ////////////////////////////////

// Port 4: the tone generator, pitch by value as in the browser emulator (0 and 255 silent)
reg  [31:0] tones[0:255];
initial $readmemh("rtl/tones.hex", tones);
reg  [31:0] inc4 = 0, ph4 = 0;
always @(posedge clk_sys) begin
	inc4 <= tones[port4];
	ph4  <= ph4 + inc4;
end
wire tone4 = !status[5] && inc4 != 0;

// Port 2: one tone generator per line (c d e f g a h c'), sounding while the line is 1
localparam [32*8-1:0] P2INC = {32'd44947, 32'd42424, 32'd37796, 32'd33673, 32'd29999, 32'd28315, 32'd25225, 32'd22474};
reg  [31:0] ph2[0:7];
integer j;
always @(posedge clk_sys) for (j = 0; j < 8; j = j + 1) ph2[j] <= ph2[j] + P2INC[j*32 +: 32];
initial for (j = 0; j < 8; j = j + 1) ph2[j] = 0;

reg signed [15:0] snd;
always @(posedge clk_sys) begin
	snd = 0;
	if (tone4) snd = ph4[31] ? 16'sh0c00 : -16'sh0c00;
	if (status[4]) for (j = 0; j < 8; j = j + 1)
		if (port2[j]) snd = snd + (ph2[j][31] ? 16'sh0500 : -16'sh0500);
end

assign AUDIO_S   = 1;
assign AUDIO_L   = snd;
assign AUDIO_R   = snd;
assign AUDIO_MIX = 0;

assign LED_USER  = tone4 && !(status[5]) && port4 != 0;

endmodule
