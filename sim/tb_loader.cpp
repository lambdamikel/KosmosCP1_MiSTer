// Streams a file through rtl/cp1_loader.v and prints every cell it stores ("cell word").
#include "Vcp1_loader.h"
#include "verilated.h"
#include <cstdio>
static Vcp1_loader *t;
static void clk() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); if (t->we) printf("%d %04x\n", t->addr, t->word); }
int main(int argc, char **argv) {
	t = new Vcp1_loader; FILE *f = fopen(argv[1], "rb"); int c;
	clk(); t->download = 1; clk();
	while ((c = fgetc(f)) != EOF) { t->din = c; t->wr = 1; clk(); t->wr = 0; clk(); clk(); }
	t->download = 0; clk(); clk(); return 0;
}
