// Loads a CP1 program file (.CP1, plain text) as it streams in from the SD card.
//
// The format is the browser emulator's: '#' or ';' starts a comment that runs to the end of the
// line, and a addr is a line "NNN [mnemonic] OO.DDD" (addr address, opcode, operand, all decimal)
// or just "OO.DDD" for the next addr.  Words made of letters (the mnemonics) are skipped, so the
// numbers decide.  A comma may stand for the dot.

module cp1_loader
(
	input             clk,
	input             download,      // file transfer active
	input             wr,            // byte strobe
	input       [7:0] din,

	output reg        we,            // one clock per addr
	output reg  [7:0] addr,
	output reg [15:0] word           // opcode << 8 | operand
);

reg        dl, comment, inword, alpha;
reg  [9:0] val;                      // the number being read
reg  [2:0] len;                      // its digits
reg  [1:0] n;                        // numbers on this line so far
reg  [9:0] v0, v1, v2;
reg  [2:0] l0;                       // digits of the first number
reg        dot1;                     // the second number ended with '.' or ','
reg  [7:0] next;                     // the addr after the last one stored

wire isdig  = din >= "0" && din <= "9";
wire isalph = (din >= "A" && din <= "Z") || (din >= "a" && din <= "z");
wire eol    = din == 8'h0a || din == 8'h0d;

// one finished number joins the line; at the end of the line the line becomes a addr
task finish_number(input enddot);
	begin
		case (n)
			2'd0: begin v0 <= val; l0 <= len; end
			2'd1: begin v1 <= val; dot1 <= enddot; end
			2'd2: v2 <= val;
			default: ;
		endcase
		if (n != 2'd3) n <= n + 1'd1;
	end
endtask

task end_line(input [1:0] cnt, input [9:0] a0, input [2:0] la0, input [9:0] a1, input [9:0] a2);
	begin
		// "NNN OO.DDD" (three numbers, the first with three digits) or "OO.DDD" (two numbers)
		if (cnt == 2'd3 && la0 == 3'd3 && a0 < 10'd256 && a1 < 10'd256 && a2 < 10'd256) begin
			we <= 1'b1; addr <= a0[7:0]; word <= {a1[7:0], a2[7:0]}; next <= a0[7:0] + 1'd1;
		end
		else if (cnt == 2'd2 && a0 < 10'd256 && a1 < 10'd256) begin
			we <= 1'b1; addr <= next; word <= {a0[7:0], a1[7:0]}; next <= next + 1'd1;
		end
		n <= 0;
	end
endtask

always @(posedge clk) begin
	we <= 1'b0;
	dl <= download;
	if (download && !dl) begin
		comment <= 0; inword <= 0; alpha <= 0; val <= 0; len <= 0; n <= 0; next <= 0; dot1 <= 0;
	end
	else if (!download && dl) begin                        // end of file: a last line without a line break
		if (inword && !alpha && !comment) begin
			if (n == 2'd1) end_line(2'd2, v0, l0, val, 10'd0);
			else if (n == 2'd2) end_line(2'd3, v0, l0, v1, val);
		end
		else if (!comment) end_line(n, v0, l0, v1, v2);
	end
	else if (download && wr) begin
		if (comment) begin
			if (eol) begin comment <= 0; end_line(n, v0, l0, v1, v2); end
		end
		else if (isdig && !(inword && alpha)) begin              // a digit: part of a number
			if (!inword) begin inword <= 1; alpha <= 0; val <= din[3:0]; len <= 3'd1; end
			else begin val <= val * 10'd10 + din[3:0]; if (len != 3'd7) len <= len + 1'd1; end
		end
		else if ((isalph || isdig) && inword && alpha) ;          // still in a word of letters
		else if (isalph) begin inword <= 1; alpha <= 1; end      // a word of letters starts: skipped
		else begin                                               // a delimiter ends a number (or a word)
			inword <= 0;
			if (inword && !alpha) begin
				// the number just ended; n and the slots update at the clock edge, so finish the line from the new values
				if (eol || din == "#" || din == ";") begin
					case (n)
						2'd0: end_line(2'd1, val, len, 10'd0, 10'd0);
						2'd1: end_line(2'd2, v0, l0, val, 10'd0);
						2'd2: end_line(2'd3, v0, l0, v1, val);
						default: end_line(2'd3, v0, l0, v1, v2);
					endcase
					if (din == "#" || din == ";") comment <= 1;
				end
				else finish_number(din == "." || din == ",");
			end
			else if (eol) end_line(n, v0, l0, v1, v2);
			else if (din == "#" || din == ";") comment <= 1;
		end
	end
end

initial begin dl = 0; comment = 0; inword = 0; alpha = 0; n = 0; next = 0; we = 0; end

endmodule
