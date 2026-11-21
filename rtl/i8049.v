// Intel 8049 at the instruction level: a port of the core in the browser emulator's js/cp1.js
// (https://github.com/lambdamikel/kosmos-cp1-emulator), which follows Andreas Signer's
// kosmos-cp1 emulator.  It runs the 2 KB CP1 firmware from rtl/cp1_rom.hex.
//
// One instruction per 'go'.  The machine cycles it takes (1 or 2) come out as 'tick' pulses, at
// the same points as _tick() in the JavaScript, so the timer (and with it the interrupt) behaves
// exactly the same.  The board paces 'go' to 400,000 machine cycles per second.
//
// External bus (MOVX): x_rd or x_wr pulses for one clock with x_addr (and x_dout); read data is
// expected on x_din in the following clock.

module i8049
(
	input             clk,
	input             reset,          // like KosmosCP1.reset(): registers, flags and internal RAM cleared
	input             go,             // start the next instruction
	output            idle,           // waiting for 'go'
	output reg        tick,           // one pulse per machine cycle used
	output reg        done,           // pulse when an instruction (and any interrupt entry) is complete
	output reg        fetch,          // pulse with the opcode fetch (for the lockstep test)

	output reg  [7:0] p1,
	output reg  [7:0] p2,
	output reg        p2_wr,          // P2 written (the board resets the 8155s on a rising bit 6)
	output reg  [7:0] p2_old,         // P2 before that write
	input       [7:0] p1_pins,        // IN A,P1 reads p1 & p1_pins
	input       [3:0] p4_in,          // MOVD A,P4..P7: the keypad columns

	output reg        x_rd,
	output reg        x_wr,
	output reg  [7:0] x_addr,
	output reg  [7:0] x_dout,
	input       [7:0] x_din
);

// ---- program ROM ----
reg  [7:0] rom[0:2047];
initial $readmemh("rtl/cp1_rom.hex", rom);
reg [10:0] ra;
reg  [7:0] romq;
always @(posedge clk) romq <= rom[ra];

// ---- internal RAM: one read address (registered), one write port ----
reg  [7:0] iram[0:127];
reg  [6:0] iaddr;
wire [7:0] iq = iram[iaddr];
reg        iwe;
reg  [6:0] iwa;
reg  [7:0] iwd;
reg  [7:0] clr_n;                 // clearing on reset
always @(posedge clk) if (iwe) iram[iwa] <= iwd;

// ---- registers (names as in cp1.js) ----
reg  [7:0] a, psw, t, bus, op, imm, rv, mv;
reg [11:0] pc;
reg        dbf, f1, tf, timer_irq, ext_irq_en, tcnt_irq_en, timer_run, cnt_run, in_irq;
reg  [5:0] pre;
reg        two, jtf_taken, irq_next;
reg [11:0] retpc;                 // the address pushed by CALL or an interrupt
reg  [4:0] st, ret_st;

localparam S_IDLE = 5'd0, S_F0 = 5'd1, S_F1 = 5'd2, S_T1 = 5'd3, S_F2 = 5'd4, S_EX = 5'd5, S_R1 = 5'd6, S_R2 = 5'd7,
           S_X1 = 5'd8, S_T2 = 5'd9, S_END = 5'd10, S_PU0 = 5'd11, S_PU1 = 5'd12, S_PO0 = 5'd13, S_PO1 = 5'd14, S_CLR = 5'd15,
           S_X2 = 5'd16;

assign idle = (st == S_IDLE);

wire [6:0] bank = psw[4] ? 7'd24 : 7'd0;
wire [2:0] sp   = psw[2:0];
wire [3:0] lo   = op[3:0];
wire [3:0] hi   = op[7:4];
wire [2:0] r    = op[2:0];
wire [6:0] ra_r = bank + {4'd0, r};                // register Rr
wire [6:0] ptr  = rv[6:0];                         // @R0 / @R1

// keypad, port 1
wire [7:0] p1_in = p1 & p1_pins;

// the adder of _add(): result, carry and auxiliary carry
function [9:0] addf(input [7:0] x, input [7:0] y, input c);
	reg [8:0] s; reg [4:0] h;
	begin s = {1'b0, x} + {1'b0, y} + c; h = {1'b0, x[3:0]} + {1'b0, y[3:0]} + c; addf = {s[8], h[4], s[7:0]}; end
endfunction

// timer: one machine cycle (_tick)
task do_tick;
	begin
		tick <= 1'b1;
		if (timer_run) begin
			if (pre == 6'd1) begin
				pre <= 6'd32;
				if (t == 8'hff) begin tf <= 1'b1; timer_irq <= 1'b1; end
				t <= t + 1'd1;
			end
			else pre <= pre - 1'd1;
		end
	end
endtask

reg [9:0] ad;
reg [8:0] da;
reg [4:0] dh;

always @(posedge clk) begin
	tick <= 1'b0; done <= 1'b0; fetch <= 1'b0; p2_wr <= 1'b0; x_rd <= 1'b0; x_wr <= 1'b0; iwe <= 1'b0;

	if (reset) begin
		a <= 0; pc <= 0; psw <= 8'h08; dbf <= 0; f1 <= 0;
		tf <= 0; timer_irq <= 0; ext_irq_en <= 0; tcnt_irq_en <= 0; timer_run <= 0; cnt_run <= 0; in_irq <= 0; pre <= 0;
		p1 <= 8'hff; p2 <= 8'hff; bus <= 0;
		clr_n <= 8'd128; st <= S_CLR;
	end
	else case (st)
	S_CLR: begin                                   // internal RAM cleared, as ram.fill(0)
		if (clr_n == 0) st <= S_IDLE;
		else begin iwe <= 1'b1; iwa <= clr_n[6:0] - 1'd1; iwd <= 8'd0; clr_n <= clr_n - 1'd1; end
	end

	S_IDLE: if (go) begin ra <= pc[10:0]; st <= S_F0; end

	S_F0: st <= S_F1;

	S_F1: begin                                    // opcode; pc++; read the operand byte and Rr in advance
		op <= romq; fetch <= 1'b1;
		pc <= pc + 1'd1; ra <= pc[10:0] + 1'd1;
		iaddr <= bank + {4'd0, romq[2:0]};
		st <= S_T1;
	end

	S_T1: begin                                    // the opcode fetch's machine cycle
		do_tick;
		rv <= iq; iaddr <= iq[6:0];
		st <= S_F2;
	end

	S_F2: begin imm <= romq; mv <= iq; st <= S_EX; two <= 1'b0; jtf_taken <= 1'b0; ret_st <= S_END; end

	S_EX: begin
		st <= S_T2;                                    // the second machine cycle (if any), then the interrupt check
		if (lo >= 4'd8) begin                          // ---- register column ----
			case (hi)
			4'h0: if (r == 0) begin two <= 1; a <= bus; end                                        // INS A,BUS
			      else if (r == 1) begin two <= 1; a <= p1_in; end                                  // IN A,P1
			      else if (r == 2) begin two <= 1; a <= p2; end                                     // IN A,P2
			      else if (r >= 4) begin two <= 1; a <= {4'd0, p4_in}; end                          // MOVD A,Pp
			4'h1: begin iwe <= 1; iwa <= ra_r; iwd <= rv + 1'd1; end                              // INC Rr
			4'h2: begin iwe <= 1; iwa <= ra_r; iwd <= a; a <= rv; end                             // XCH A,Rr
			4'h3: if (r == 1) begin two <= 1; p1 <= a; end                                         // OUTL P1,A
			      else if (r == 2) begin two <= 1; p2_old <= p2; p2 <= a; p2_wr <= 1; end          // OUTL P2,A
			      else if (r >= 4) two <= 1;                                                        // MOVD Pp,A
			4'h4: a <= a | rv;
			4'h5: a <= a & rv;
			4'h6: begin ad = addf(a, rv, 1'b0);   a <= ad[7:0]; psw <= {ad[9:8], psw[5:0]}; end
			4'h7: begin ad = addf(a, rv, psw[7]); a <= ad[7:0]; psw <= {ad[9:8], psw[5:0]}; end
			4'h8: if (r == 0) begin two <= 1; pc <= pc + 1'd1; bus <= bus | imm; end              // ORL BUS,#
			      else if (r == 1) begin two <= 1; pc <= pc + 1'd1; p1 <= p1 | imm; end             // ORL P1,#
			      else if (r == 2) begin two <= 1; pc <= pc + 1'd1; p2_old <= p2; p2 <= p2 | imm; p2_wr <= 1; end
			      else if (r >= 4) two <= 1;                                                        // ORLD
			4'h9: if (r == 0) begin two <= 1; pc <= pc + 1'd1; bus <= bus & imm; end              // ANL BUS,#
			      else if (r == 1) begin two <= 1; pc <= pc + 1'd1; p1 <= p1 & imm; end
			      else if (r == 2) begin two <= 1; pc <= pc + 1'd1; p2_old <= p2; p2 <= p2 & imm; p2_wr <= 1; end
			      else if (r >= 4) two <= 1;                                                        // ANLD
			4'ha: begin iwe <= 1; iwa <= ra_r; iwd <= a; end                                      // MOV Rr,A
			4'hb: begin two <= 1; pc <= pc + 1'd1; iwe <= 1; iwa <= ra_r; iwd <= imm; end         // MOV Rr,#
			4'hc: begin iwe <= 1; iwa <= ra_r; iwd <= rv - 1'd1; end                              // DEC Rr
			4'hd: a <= a ^ rv;
			4'he: begin two <= 1; iwe <= 1; iwa <= ra_r; iwd <= rv - 1'd1;                        // DJNZ Rr,addr
			            pc <= (rv != 8'd1) ? {pc[11:8], imm} : pc + 1'd1; end
			4'hf: a <= rv;                                                                          // MOV A,Rr
			endcase
		end
		else if (lo == 4'd4) begin                     // ---- JMP / CALL ----
			two <= 1;
			pc <= {dbf, op[7:5], imm};
			if (op[4]) begin retpc <= pc + 1'd1; ret_st <= S_T2; st <= S_PU0; end                 // CALL: push the return address
		end
		else if (lo == 4'd2) begin
			if (op == 8'h02) begin two <= 1; bus <= a; end                                         // OUTL BUS,A
			else if (op == 8'h42) a <= t;                                                           // MOV A,T
			else if (op == 8'h62) t <= a;                                                           // MOV T,A
			else if (hi[0]) begin two <= 1; pc <= a[hi[3:1]] ? {pc[11:8], imm} : pc + 1'd1; end  // JBb
		end
		else if (lo <= 4'd1) begin                     // ---- @R0 / @R1 ----
			case (hi)
			4'h1: begin iwe <= 1; iwa <= ptr; iwd <= mv + 1'd1; end                               // INC @Rr
			4'h2: begin iwe <= 1; iwa <= ptr; iwd <= a; a <= mv; end                              // XCH A,@Rr
			4'h3: begin iwe <= 1; iwa <= ptr; iwd <= {mv[7:4], a[3:0]}; a <= {a[7:4], mv[3:0]}; end // XCHD
			4'h4: a <= a | mv;
			4'h5: a <= a & mv;
			4'h6: begin ad = addf(a, mv, 1'b0);   a <= ad[7:0]; psw <= {ad[9:8], psw[5:0]}; end
			4'h7: begin ad = addf(a, mv, psw[7]); a <= ad[7:0]; psw <= {ad[9:8], psw[5:0]}; end
			4'h8: begin two <= 1; x_rd <= 1; x_addr <= rv; st <= S_X1; end                         // MOVX A,@Rr (data in S_X2)
			4'h9: begin two <= 1; x_wr <= 1; x_addr <= rv; x_dout <= a; bus <= a; end              // MOVX @Rr,A
			4'ha: begin iwe <= 1; iwa <= ptr; iwd <= a; end                                       // MOV @Rr,A
			4'hb: begin two <= 1; pc <= pc + 1'd1; iwe <= 1; iwa <= ptr; iwd <= imm; end          // MOV @Rr,#
			4'hd: a <= a ^ mv;
			4'hf: a <= mv;
			default: ;
			endcase
		end
		else case (op)
		8'h03: begin two <= 1; pc <= pc + 1'd1; ad = addf(a, imm, 1'b0);   a <= ad[7:0]; psw <= {ad[9:8], psw[5:0]}; end
		8'h13: begin two <= 1; pc <= pc + 1'd1; ad = addf(a, imm, psw[7]); a <= ad[7:0]; psw <= {ad[9:8], psw[5:0]}; end
		8'h23: begin two <= 1; pc <= pc + 1'd1; a <= imm; end
		8'h43: begin two <= 1; pc <= pc + 1'd1; a <= a | imm; end
		8'h53: begin two <= 1; pc <= pc + 1'd1; a <= a & imm; end
		8'hd3: begin two <= 1; pc <= pc + 1'd1; a <= a ^ imm; end
		8'h83, 8'h93: begin two <= 1; iaddr <= 7'd8 + {sp - 1'd1, 1'b0}; st <= S_PO0; end           // RET, RETR
		8'ha3, 8'hb3: begin two <= 1; ra <= {pc[10:8], a}; st <= S_R1; end                          // MOVP A,@A / JMPP @A
		8'he3: begin two <= 1; ra <= {3'b011, a}; st <= S_R1; end                                    // MOVP3 A,@A
		8'h05: ext_irq_en <= 1;
		8'h15: ext_irq_en <= 0;
		8'h25: tcnt_irq_en <= 1;
		8'h35: begin tcnt_irq_en <= 0; timer_irq <= 0; end
		8'h45: begin cnt_run <= 1; timer_run <= 0; end
		8'h55: begin cnt_run <= 0; timer_run <= 1; pre <= 6'd32; end
		8'h65: begin timer_run <= 0; cnt_run <= 0; end
		8'h07: a <= a - 1'd1;
		8'h17: a <= a + 1'd1;
		8'h27: a <= 0;
		8'h37: a <= ~a;
		8'h47: a <= {a[3:0], a[7:4]};
		8'h57: begin                                                                                 // DA A
			da = {1'b0, a};
			if (a[3:0] > 4'd9 || psw[6]) da = da + 9'd6;
			dh = {1'b0, da[7:4]} | {da[8], 4'd0};
			if (dh > 5'd9 || psw[7]) dh = dh + 5'd6;
			a <= {dh[3:0], da[3:0]}; psw <= {dh > 5'd15, psw[6:0]};
		end
		8'h67: begin a <= {psw[7], a[7:1]}; psw <= {a[0], psw[6:0]}; end                             // RRC A
		8'h77: a <= {a[0], a[7:1]};                                                                  // RR A
		8'he7: a <= {a[6:0], a[7]};                                                                  // RL A
		8'hf7: begin a <= {a[6:0], psw[7]}; psw <= {a[7], psw[6:0]}; end                             // RLC A
		8'h85: psw[5] <= 1'b0;                                                                       // CLR F0
		8'h95: psw[5] <= ~psw[5];                                                                    // CPL F0
		8'ha5: f1 <= 0;
		8'hb5: f1 <= ~f1;
		8'h97: psw[7] <= 1'b0;                                                                       // CLR C
		8'ha7: psw[7] <= ~psw[7];                                                                    // CPL C
		8'hc5: psw[4] <= 1'b0;                                                                       // SEL RB0
		8'hd5: psw[4] <= 1'b1;                                                                       // SEL RB1
		8'he5: dbf <= 0;
		8'hf5: dbf <= 1;
		8'hc7: a <= psw;
		8'hd7: psw <= a;
		8'h16: begin two <= 1; jtf_taken <= tf; pc <= tf ? {pc[11:8], imm} : pc + 1'd1; end         // JTF
		8'h26, 8'h46, 8'h86: begin two <= 1; pc <= {pc[11:8], imm}; end                              // JNT0, JNT1, JNI: taken
		8'h36, 8'h56: begin two <= 1; pc <= pc + 1'd1; end                                           // JT0, JT1: not taken
		8'h76: begin two <= 1; pc <= f1 ? {pc[11:8], imm} : pc + 1'd1; end                          // JF1
		8'h96: begin two <= 1; pc <= (a != 0) ? {pc[11:8], imm} : pc + 1'd1; end                    // JNZ
		8'hb6: begin two <= 1; pc <= psw[5] ? {pc[11:8], imm} : pc + 1'd1; end                      // JF0
		8'hc6: begin two <= 1; pc <= (a == 0) ? {pc[11:8], imm} : pc + 1'd1; end                    // JZ
		8'he6: begin two <= 1; pc <= !psw[7] ? {pc[11:8], imm} : pc + 1'd1; end                     // JNC
		8'hf6: begin two <= 1; pc <= psw[7] ? {pc[11:8], imm} : pc + 1'd1; end                      // JC
		default: ;                                                                                   // NOP, undefined
		endcase
		// all two-cycle instructions take their second machine cycle next (after any push/pop/read)
	end

	// ROM read for MOVP / JMPP / MOVP3 (ra set in S_EX)
	S_R1: st <= S_R2;
	S_R2: begin
		if (op == 8'hb3) pc <= {pc[11:8], romq}; else a <= romq;
		st <= S_T2;
	end

	// MOVX A,@Rr: data from the board
	S_X1: st <= S_X2;
	S_X2: begin a <= x_din; bus <= x_din; st <= S_T2; end

	// push the pc and the upper PSW (CALL, interrupt), then continue at ret_st
	S_PU0: begin iwe <= 1; iwa <= 7'd8 + {sp, 1'b0}; iwd <= retpc[7:0]; st <= S_PU1; end
	S_PU1: begin
		iwe <= 1; iwa <= 7'd9 + {sp, 1'b0};
		iwd <= {psw[7:4], retpc[11:8]};
		psw[2:0] <= sp + 1'd1;
		if (irq_next) begin pc <= 12'd7; in_irq <= 1'b1; irq_next <= 1'b0; done <= 1'b1; st <= S_IDLE; end
		else st <= ret_st;
	end

	// pop (RET / RETR): iaddr = 8 + 2*(sp-1) set in S_EX
	S_PO0: begin pc[7:0] <= iq; iaddr <= iaddr + 1'd1; st <= S_PO1; end
	S_PO1: begin
		pc[11:8] <= iq[3:0];
		if (op == 8'h93) begin psw <= {iq[7:4], 4'b1000} | {5'd0, sp - 1'd1}; in_irq <= 1'b0; end
		else psw <= {psw[7:4], 4'b1000} | {5'd0, sp - 1'd1};
		st <= S_T2;
	end

	S_T2: begin
		if (two) begin
			do_tick;
			if (jtf_taken) tf <= 1'b0;                 // JTF clears the flag after its second cycle
		end
		st <= S_END;
	end

	S_END: begin
		if (!in_irq && timer_irq && tcnt_irq_en) begin  // timer interrupt: push the pc, continue at 007
			timer_irq <= 1'b0; irq_next <= 1'b1; retpc <= pc; st <= S_PU0;
		end
		else begin done <= 1'b1; st <= S_IDLE; end
	end
	default: st <= S_IDLE;
	endcase
end

initial begin
	st = S_CLR; clr_n = 8'd128; t = 0; irq_next = 0; a = 0; pc = 0; psw = 8'h08; p1 = 8'hff; p2 = 8'hff; bus = 0;
	dbf = 0; f1 = 0; tf = 0; timer_irq = 0; ext_irq_en = 0; tcnt_irq_en = 0; timer_run = 0; cnt_run = 0; in_irq = 0; pre = 0;
end

endmodule
