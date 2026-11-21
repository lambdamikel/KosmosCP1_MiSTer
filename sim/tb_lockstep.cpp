// Lockstep test, Verilog side: runs a scenario on rtl/cp1.v + rtl/i8049.v and prints the same
// checkpoints as lockstep.js does on the browser emulator's js/cp1.js.
//   ops: run N [every] | down KEY | up KEY | p1 V | p3 V | cross 0/1 | load CELL WORD... (hex) | reset | check
#include "Vcp1.h"
#include "Vcp1___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <string>
#include <map>
#include <fstream>
#include <sstream>

static Vcp1 *t;
static Vcp1___024root *R;
static uint64_t steps = 0;
static uint32_t h = 2166136261u;
static inline uint32_t fnv(uint32_t x, uint32_t v) { return (x ^ (v & 255)) * 16777619u; }

static void clk() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); }

static std::map<std::string, int> KEY = {   // row*4 + column, as CP1_KEYS
	{"0",16},{"1",17},{"2",18},{"3",19},{"4",12},{"5",13},{"6",14},{"7",15},{"8",8},{"9",9},{"OUT",10},{"INP",11},
	{"CAL",4},{"STEP",5},{"STP",6},{"RUN",7},{"CAS",0},{"CLR",1},{"PC",2},{"ACC",3}};

#define CPU(x) R->cp1__DOT__cpu__DOT__##x
#define BRD(x) R->cp1__DOT__##x

static void step() {
	do clk(); while (!t->executed);
	steps++;
	uint32_t v[] = { CPU(a), (uint32_t)(CPU(pc) & 255), (uint32_t)(CPU(pc) >> 8), CPU(psw), CPU(dbf), CPU(f1), CPU(t), CPU(tf),
	                 CPU(timer_irq), CPU(tcnt_irq_en), CPU(timer_run), CPU(in_irq), CPU(pre), CPU(p1), CPU(p2), CPU(bus) };
	for (uint32_t x : v) h = fnv(h, x);
}

static void check() {
	uint32_t hr = 2166136261u, hp = 2166136261u, he = 2166136261u;
	for (int i = 0; i < 128; i++) hr = fnv(hr, CPU(iram)[i]);
	for (int i = 0; i < 256; i++) { hp = fnv(hp, BRD(pid_ram)[i]); he = fnv(he, BRD(ext_ram)[i]); }
	uint32_t regs[] = { BRD(pid_cmd), BRD(pid_pa), BRD(pid_pb), BRD(pid_pc), BRD(ext_cmd), BRD(ext_pa), BRD(ext_pb), BRD(ext_pc) };
	for (uint32_t x : regs) hp = fnv(hp, x);
	printf("chk %llu %08x %08x %08x %08x\n", (unsigned long long)steps, h, hr, hp, he);
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vcp1; R = t->rootp;
	t->mcyc = 1; t->keys = 0; t->port1_in = 0xff; t->port3_in = 0xff; t->xwire = 0; t->ld_we = 0;
	t->reset = 1; clk(); t->reset = 0;
	std::ifstream in(argv[1]);
	std::string line;
	while (std::getline(in, line)) {
		std::istringstream ss(line);
		std::string op; ss >> op;
		if (op == "run") {
			uint64_t n = 0, every = 0; ss >> n >> every;
			for (uint64_t i = 0; i < n; i++) { step(); if (every && steps % every == 0) check(); }
		}
		else if (op == "down" || op == "up") {
			std::string k; ss >> k;
			if (KEY.count(k)) { if (op == "down") t->keys |= 1u << KEY[k]; else t->keys &= ~(1u << KEY[k]); }
		}
		else if (op == "p1") { int v; ss >> v; t->port1_in = v; }
		else if (op == "p3") { int v; ss >> v; t->port3_in = v; }
		else if (op == "cross") { int v; ss >> v; t->xwire = v; }
		else if (op == "load") {
			int a; std::string w; ss >> a;
			while (ss >> w) {                                   // writeCell: like the JavaScript, at once
				unsigned v = std::stoul(w, nullptr, 16);
				auto &ram = (a < 128) ? BRD(pid_ram) : BRD(ext_ram);
				ram[(a & 127) * 2] = v >> 8; ram[(a & 127) * 2 + 1] = v & 255; a++;
			}
		}
		else if (op == "reset") { t->reset = 1; clk(); t->reset = 0; }
		else if (op == "check") check();
	}
	check();
	delete t;
	return 0;
}
