// The Kosmos CP1 board around the 8049, as modelled in the browser emulator's js/cp1.js:
//
//   P2 bit 4      /CE of the main 8155 (program cells 000-127, display, keypad rows, Port 2)
//   P2 bit 5      /CE of the CP3 8155 (cells 128-255, Port 3 in, Port 4 and 5 out)
//   P2 bit 6      RESET of both 8155s (on a rising edge; like the JavaScript, this also clears their RAM)
//   P2 bit 7      IO/M: MOVX reaches the 8155 registers (0 command, 1 port A, 2 port B, 3 port C) or the RAM
//   main 8155     port A = segments, port C = digit / keypad row select (active low; digit = 5 - bit),
//                 port B = user Port 2 (outputs)
//   keypad        columns on the low nibble read by MOVD A,P4 (the first selected row)
//   8049 P1       user Port 1 (IN A,P1 reads P1 & the levels on the terminals)

module cp1
(
	input              clk,
	input              reset,          // power on: CPU and both 8155s reset, RAMs cleared
	input              mcyc,           // allows one machine cycle (400 kHz for the original speed)
	output             executed,       // pulse per instruction (and interrupt entry)
	output             fetch,          // pulse per opcode fetch

	input       [19:0] keys,           // held keys: bit row*4 + column (rows 0-4 as CP1_KEYS)
	input        [7:0] port1_in,       // levels applied to the Port 1 terminals (1 = high / open)
	input        [7:0] port3_in,       // levels applied to Port 3
	input              xwire,          // random-number wiring: Port 2 lines 1-8 to Port 1 lines 3,4,2,1,7,8,6,5

	input              ld_we,          // write a program cell (opcode, operand) from the loader
	input        [7:0] ld_cell,
	input       [15:0] ld_word,

	output       [7:0] port1,          // what the program wrote to Port 1
	output       [7:0] port2,          // Port 2 (main 8155 port B)
	output       [7:0] port4,          // Port 4 (CP3 8155 port A)
	output       [7:0] port5,          // Port 5 (CP3 8155 port C)
	output       [7:0] port1_pins,     // levels on the Port 1 terminals
	output reg [383:0] seg_level       // digit d (0 = leftmost), segment b: [(d*8+b)*8 +: 8]
);

// ---- the 8155s ----
reg  [7:0] pid_ram[0:255], ext_ram[0:255];
reg  [7:0] pid_cmd, pid_pa, pid_pb, pid_pc, ext_cmd, ext_pa, ext_pb, ext_pc;

// ---- CPU ----
wire       idle, tick, cpu_done, p2_wr, x_rd, x_wr;
wire [7:0] p1, p2, p2_old, x_addr, x_dout;
reg  [7:0] x_din;
reg  [3:0] keynib;
reg        clearing;
reg  [8:0] clr_a;
reg signed [3:0] credit;

i8049 cpu
(
	.clk(clk), .reset(reset), .go(!clearing && credit > 0), .idle(idle), .tick(tick), .done(cpu_done), .fetch(fetch),
	.p1(p1), .p2(p2), .p2_wr(p2_wr), .p2_old(p2_old), .p1_pins(port1_pins), .p4_in(keynib),
	.x_rd(x_rd), .x_wr(x_wr), .x_addr(x_addr), .x_dout(x_dout), .x_din(x_din)
);
assign executed = cpu_done;

// pacing: a credit of machine cycles
always @(posedge clk) begin
	if (reset) credit <= 0;
	else credit <= credit + ((mcyc && credit < 4'sd2) ? 4'sd1 : 4'sd0) - (tick ? 4'sd1 : 4'sd0);
end

// ---- ports ----
wire       sel_pid = !p2[4];
wire       sel_ext = p2[4] && !p2[5];
wire       wr_pid  = !p2[4];             // writes reach every selected 8155: the firmware selects both to clear the memory
wire       wr_ext  = !p2[5];
wire       iom     = p2[7];
assign port1 = p1;
assign port2 = pid_pb;
assign port4 = ext_pa;
assign port5 = ext_pc;

// Port 1 terminals: outside levels, pulled low by Port 2 lines wired across (a Port 2 line is low when its bit is 0)
wire [7:0] xw = xwire ? { pid_pb[5], pid_pb[4], pid_pb[6], pid_pb[7], pid_pb[1], pid_pb[0], pid_pb[2], pid_pb[3] } : 8'hff;
assign port1_pins = port1_in & xw;

// keypad: the columns of the first selected row
integer i, ki;
always @* begin
	keynib = 4'd0;
	for (ki = 7; ki >= 0; ki = ki - 1)
		if (!pid_pc[ki]) keynib = (ki < 5) ? keys[ki*4 +: 4] : 4'd0;
end

// ---- bus ----
reg  [7:0] pid_q, ext_q;
reg  [1:0] rsel;                  // read: 0 none, 1 main, 2 CP3
reg        rio;
reg  [1:0] rreg;
always @(posedge clk) begin
	pid_q <= pid_ram[x_addr];
	ext_q <= ext_ram[x_addr];
	if (x_rd) begin rsel <= sel_pid ? 2'd1 : sel_ext ? 2'd2 : 2'd0; rio <= iom; rreg <= x_addr[1:0]; end
end
always @* begin
	if (rsel == 2'd0) x_din = 8'hff;
	else if (rio) case (rreg)
		2'd1: x_din = (rsel == 2'd1) ? pid_pa : ext_pa;
		2'd2: x_din = (rsel == 2'd1) ? pid_pb : port3_in;
		2'd3: x_din = (rsel == 2'd1) ? pid_pc : ext_pc;
		default: x_din = 8'd0;
	endcase
	else x_din = (rsel == 2'd1) ? pid_q : ext_q;
end

// writes: CPU (MOVX), loader (two bytes per cell) and the clearing sweep share one write port per RAM
reg        ld_busy;
reg  [7:0] ld_byte, ld_lo;
reg  [6:0] ld_idx;
reg        ld_ext;
wire       rst8155 = p2_wr && !p2_old[6] && p2[6];

always @(posedge clk) begin
	if (reset || rst8155) begin
		pid_cmd <= 0; pid_pa <= 0; pid_pb <= 0; pid_pc <= 0; ext_cmd <= 0; ext_pa <= 0; ext_pb <= 0; ext_pc <= 0;
		clearing <= 1'b1; clr_a <= 9'd0;
	end
	else if (clearing) begin
		pid_ram[clr_a[7:0]] <= 8'd0; ext_ram[clr_a[7:0]] <= 8'd0;
		clr_a <= clr_a + 1'd1;
		if (clr_a == 9'd255) clearing <= 1'b0;
	end
	else if (x_wr && (wr_pid || wr_ext)) begin
		if (iom) case (x_addr[1:0])
			2'd0: begin if (wr_pid) pid_cmd <= x_dout; if (wr_ext) ext_cmd <= x_dout; end
			2'd1: begin if (wr_pid) pid_pa  <= x_dout; if (wr_ext) ext_pa  <= x_dout; end
			2'd2: begin if (wr_pid) pid_pb  <= x_dout; if (wr_ext) ext_pb  <= x_dout; end
			2'd3: begin if (wr_pid) pid_pc  <= x_dout; if (wr_ext) ext_pc  <= x_dout; end
		endcase
		else begin
			if (wr_pid) pid_ram[x_addr] <= x_dout;
			if (wr_ext) ext_ram[x_addr] <= x_dout;
		end
	end
	else if (ld_busy) begin                                // second byte of a loaded cell
		if (ld_ext) ext_ram[{ld_idx, 1'b1}] <= ld_lo; else pid_ram[{ld_idx, 1'b1}] <= ld_lo;
		ld_busy <= 1'b0;
	end
	else if (ld_we) begin                                  // first byte: the opcode
		if (ld_cell[7]) ext_ram[{ld_cell[6:0], 1'b0}] <= ld_word[15:8]; else pid_ram[{ld_cell[6:0], 1'b0}] <= ld_word[15:8];
		ld_idx <= ld_cell[6:0]; ld_ext <= ld_cell[7]; ld_lo <= ld_word[7:0]; ld_busy <= 1'b1;
	end
end

// ---- display: segment on-time per machine cycle, over windows of 16384 cycles (41 ms) ----
// The firmware shows each digit for a long stretch, so a shorter window can miss a digit altogether.
reg [13:0] wcnt;
reg [14:0] scnt[0:47];
integer d, b;
function [7:0] level(input [14:0] n);              // a digit lit 1/14 of the time or more is full (as the emulator)
	reg [17:0] v;
	begin v = {3'd0, n} * 18'd7 >> 5; level = (v > 18'd255) ? 8'd255 : v[7:0]; end
endfunction
always @(posedge clk) if (tick) begin
	if (wcnt == 14'd16383) begin
		for (i = 0; i < 48; i = i + 1) begin seg_level[i*8 +: 8] <= level(scnt[i]); scnt[i] <= 0; end
		wcnt <= 0;
	end else begin
		wcnt <= wcnt + 1'd1;
		for (d = 0; d < 6; d = d + 1) for (b = 0; b < 8; b = b + 1)
			if (!pid_pc[d] && pid_pa[b]) scnt[(5-d)*8+b] <= scnt[(5-d)*8+b] + 1'd1;
	end
end

initial begin
	clearing = 1'b1; clr_a = 0; credit = 0; ld_busy = 0; wcnt = 0; seg_level = 0; rsel = 0;
	pid_cmd = 0; pid_pa = 0; pid_pb = 0; pid_pc = 0; ext_cmd = 0; ext_pa = 0; ext_pb = 0; ext_pc = 0;
	for (i = 0; i < 48; i = i + 1) scnt[i] = 0;
end

endmodule
