// Runs a scenario on board + picture and writes frames as PPM.  Ops as tb_lockstep.cpp (p1 sets the
// switches), plus "frame <file.ppm>" and "speed <n>" (a machine cycle every n clocks; 125 = original).
#include "Vsim_top.h"
#include "Vsim_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <string>
#include <map>
#include <vector>
#include <fstream>
#include <sstream>
static Vsim_top *t;
static uint64_t steps = 0;
static int phase = 0, every = 2;
static void tick() {
	t->mcyc = (++phase % every) == 0;
	t->clk = 0; t->eval(); t->clk = 1; t->eval();
	if (t->executed) steps++;
}
static std::map<std::string, int> KEY = {
	{"0",16},{"1",17},{"2",18},{"3",19},{"4",12},{"5",13},{"6",14},{"7",15},{"8",8},{"9",9},{"OUT",10},{"INP",11},
	{"CAL",4},{"STEP",5},{"STP",6},{"RUN",7},{"CAS",0},{"CLR",1},{"PC",2},{"ACC",3}};
static void frame(const char *fn) {
	while (!t->VBlank) tick();
	while (t->VBlank) tick();
	std::vector<uint8_t> img; img.reserve(640 * 480 * 3);
	while (img.size() < 640 * 480 * 3) {
		tick();
		if (t->ce_pix && !t->HBlank && !t->VBlank) { img.push_back(t->R); img.push_back(t->G); img.push_back(t->B); }
	}
	FILE *f = fopen(fn, "wb"); fprintf(f, "P6\n640 480\n255\n"); fwrite(img.data(), 1, img.size(), f); fclose(f);
	printf("frame %s at step %llu\n", fn, (unsigned long long)steps);
}
int main(int argc, char **argv) {
	t = new Vsim_top;
	t->keys = 0; t->sw = 0xff; t->port3_in = 0xff; t->xwire = 0; t->ld_we = 0;
	t->reset = 1; tick(); t->reset = 0;
	std::ifstream in(argv[1]); std::string line;
	while (std::getline(in, line)) {
		std::istringstream ss(line); std::string op; ss >> op;
		if (op == "run") { uint64_t n; ss >> n; uint64_t end = steps + n; while (steps < end) tick(); }
		else if (op == "down" || op == "up") { std::string k; ss >> k; if (KEY.count(k)) { if (op == "down") t->keys |= 1u << KEY[k]; else t->keys &= ~(1u << KEY[k]); } }
		else if (op == "p1") { int v; ss >> v; t->sw = v; }
		else if (op == "cross") { int v; ss >> v; t->xwire = v; }
		else if (op == "load") {
			int a; std::string w; ss >> a;
			while (ss >> w) { t->ld_addr = a++; t->ld_word = std::stoul(w, nullptr, 16); t->ld_we = 1; tick(); t->ld_we = 0; tick(); tick(); }
		}
		else if (op == "speed") ss >> every;
		else if (op == "frame") { std::string fn; ss >> fn; frame(fn.c_str()); }
		else if (op == "scan") {                            // (port C, port A) per machine cycle over N clocks
			uint64_t n; ss >> n; std::map<int, int> hist; auto *r = t->rootp;
			for (uint64_t i = 0; i < n; i++) { tick(); if (r->sim_top__DOT__board__DOT__tick) hist[r->sim_top__DOT__board__DOT__pid_pc << 8 | r->sim_top__DOT__board__DOT__pid_pa]++; }
			for (auto &kv : hist) printf("pc=%02x pa=%02x  %d cycles\n", kv.first >> 8, kv.first & 255, kv.second);
		}
		else if (op == "levels") {                          // the board's segment levels, digit by digit
			auto &L = t->rootp->sim_top__DOT__board__DOT__seg_level;
			printf("wcnt=%d scnt0-7:", t->rootp->sim_top__DOT__board__DOT__wcnt); for (int i = 0; i < 8; i++) printf(" %d", t->rootp->sim_top__DOT__board__DOT__scnt[i]);
			printf("  scnt24-31:"); for (int i = 24; i < 32; i++) printf(" %d", t->rootp->sim_top__DOT__board__DOT__scnt[i]); printf("\n");
			for (int d = 0; d < 6; d++) { printf("digit %d:", d); for (int b = 0; b < 8; b++) { int i = d * 8 + b; printf(" %3d", (L[i / 4] >> ((i % 4) * 8)) & 255); } printf("   pc=%02x\n", t->rootp->sim_top__DOT__board__DOT__pid_pc); }
		}
	}
	return 0;
}
