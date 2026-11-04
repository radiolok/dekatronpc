/* State-time integrator of the tube cells over a VCD stream (doc/vtube_power.md).
 *
 *   vtube_power_vcd <plan> <vcd|-> <out>
 *
 * The plan (written by vtube_power.py plan) lists the cells: their block, their
 * pins as full VCD paths (scopes joined with '/') and a current table of
 * (2^n + 1) x R values in mA, one row per pin state (pin 0 = bit 0) and the last
 * row for a state with an x or z pin. The VCD is read once, as a stream (it can
 * be a FIFO that vvp writes, so the file of pi.bfk, tens of GB, never lands on
 * disk). Changes at one timestamp are applied together at the next one, so zero
 * width glitches of the zero-delay netlist cost nothing.
 *
 * Output: per cell the time in each state (for the means), and per block and rail
 * the largest mean current over a window (default one Clk period), the block sum
 * included: the static load the supply has to carry, not the edge peaks.
 *
 * Plan format, whitespace separated:
 *   rails <R>  blocks <B>  window <ps>  cells <N>
 *   then per cell:  <block> <n> <path_1> ... <path_n>  <(2^n + 1) * R numbers>
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXPINS 8
#define MAXR 8

typedef struct {
	int block, n;
	uint32_t val, xmask;     /* current pin values; xmask: pins at x/z */
	int state;               /* row of the table in effect */
	int dirty;
	uint64_t since;          /* time the state was entered */
	double *tab;             /* (2^n + 1) * R */
	double *hist;            /* time per row, ps */
} Cell;

typedef struct { int cell, bit; } PinRef;

static int R, B, N;
static uint64_t window;
static Cell *cells;

/* path -> list of pins (header resolution) */
typedef struct PathEnt { char *path; PinRef ref; int found; struct PathEnt *next; } PathEnt;
#define PHASH (1 << 16)
static PathEnt *paths[PHASH];

/* VCD id -> list of pins */
typedef struct IdEnt { char id[64]; int cnt, cap; PinRef *refs; struct IdEnt *next; } IdEnt;
#define IHASH (1 << 18)
static IdEnt *ids[IHASH];

static uint32_t hstr(const char *s)
{
	uint32_t h = 2166136261u;
	while (*s) h = (h ^ (unsigned char)*s++) * 16777619u;
	return h;
}

static void die(const char *m) { fprintf(stderr, "vtube_power_vcd: %s\n", m); exit(1); }

static void read_plan(const char *fn)
{
	FILE *f = fopen(fn, "r");
	char kw[64], buf[4096];
	if (!f) die("cannot open plan");
	if (fscanf(f, "%63s %d", kw, &R) != 2 || strcmp(kw, "rails")) die("plan: rails");
	if (fscanf(f, "%63s %d", kw, &B) != 2 || strcmp(kw, "blocks")) die("plan: blocks");
	if (fscanf(f, "%63s %lu", kw, (unsigned long *)&window) != 2 || strcmp(kw, "window")) die("plan: window");
	if (fscanf(f, "%63s %d", kw, &N) != 2 || strcmp(kw, "cells")) die("plan: cells");
	if (R > MAXR) die("too many rails");
	cells = calloc(N, sizeof(Cell));
	for (int c = 0; c < N; c++) {
		Cell *k = &cells[c];
		if (fscanf(f, "%d %d", &k->block, &k->n) != 2) die("plan: cell");
		if (k->n > MAXPINS) die("too many pins");
		for (int p = 0; p < k->n; p++) {
			if (fscanf(f, "%4095s", buf) != 1) die("plan: pin");
			PathEnt *e = malloc(sizeof(PathEnt));
			e->path = strdup(buf); e->ref.cell = c; e->ref.bit = p; e->found = 0;
			uint32_t h = hstr(buf) & (PHASH - 1);
			e->next = paths[h]; paths[h] = e;
		}
		int rows = (1 << k->n) + 1;
		k->tab = malloc(sizeof(double) * rows * R);
		k->hist = calloc(rows, sizeof(double));
		for (int i = 0; i < rows * R; i++)
			if (fscanf(f, "%lf", &k->tab[i]) != 1) die("plan: table");
		k->xmask = (1u << k->n) - 1;   /* everything x before $dumpvars */
		k->state = k->n ? (1 << k->n) : 0;
	}
	fclose(f);
}

static void bind(const char *id, PinRef r)
{
	uint32_t h = hstr(id) & (IHASH - 1);
	IdEnt *e;
	for (e = ids[h]; e; e = e->next)
		if (!strcmp(e->id, id)) break;
	if (!e) {
		e = calloc(1, sizeof(IdEnt));
		snprintf(e->id, sizeof e->id, "%s", id);
		e->next = ids[h]; ids[h] = e;
	}
	if (e->cnt == e->cap) {
		e->cap = e->cap ? 2 * e->cap : 4;
		e->refs = realloc(e->refs, e->cap * sizeof(PinRef));
	}
	e->refs[e->cnt++] = r;
}

static IdEnt *lookup(const char *id, size_t len)
{
	char tmp[64];
	if (len >= sizeof tmp) return NULL;
	memcpy(tmp, id, len); tmp[len] = 0;
	for (IdEnt *e = ids[hstr(tmp) & (IHASH - 1)]; e; e = e->next)
		if (!strcmp(e->id, tmp)) return e;
	return NULL;
}

/* running totals per block and rail, and the window integrals */
static double cur[64][MAXR], tot[MAXR];
static double wq[64][MAXR], wqt[MAXR];
static double peak[64][MAXR], peakt[MAXR];
static uint64_t wstart, tnow, tfirst;
static int *dirty_list, ndirty;

static void row_add(Cell *k, int st, double sgn)
{
	double *t = &k->tab[st * R];
	for (int r = 0; r < R; r++) { cur[k->block][r] += sgn * t[r]; tot[r] += sgn * t[r]; }
}

static void close_window(void)
{
	for (int b = 0; b < B; b++)
		for (int r = 0; r < R; r++) {
			double m = wq[b][r] / window;
			if (m > peak[b][r]) peak[b][r] = m;
			wq[b][r] = 0;
		}
	for (int r = 0; r < R; r++) {
		double m = wqt[r] / window;
		if (m > peakt[r]) peakt[r] = m;
		wqt[r] = 0;
	}
}

/* integrate the present totals from tnow to t */
static void advance(uint64_t t)
{
	while (t > tnow) {
		uint64_t wend = wstart + window;
		uint64_t step = (t < wend ? t : wend) - tnow;
		for (int b = 0; b < B; b++)
			for (int r = 0; r < R; r++) wq[b][r] += cur[b][r] * step;
		for (int r = 0; r < R; r++) wqt[r] += tot[r] * step;
		tnow += step;
		if (tnow == wend) {
			close_window();
			wstart = wend;
			/* whole windows at a constant load: one step */
			if (t - tnow >= window) {
				uint64_t k = (t - tnow) / window;
				for (int b = 0; b < B; b++)
					for (int r = 0; r < R; r++)
						if (cur[b][r] > peak[b][r]) peak[b][r] = cur[b][r];
				for (int r = 0; r < R; r++)
					if (tot[r] > peakt[r]) peakt[r] = tot[r];
				tnow += k * window; wstart += k * window;
			}
		}
	}
}

static void settle(void)
{
	for (int i = 0; i < ndirty; i++) {
		Cell *k = &cells[dirty_list[i]];
		k->dirty = 0;
		int st = k->xmask ? (1 << k->n) : (int)k->val;
		if (st == k->state) continue;
		k->hist[k->state] += (double)(tnow - k->since);
		row_add(k, k->state, -1);
		row_add(k, st, +1);
		k->state = st; k->since = tnow;
	}
	ndirty = 0;
}

static void set_pin(IdEnt *e, char v)
{
	for (int i = 0; i < e->cnt; i++) {
		Cell *k = &cells[e->refs[i].cell];
		uint32_t m = 1u << e->refs[i].bit;
		if (v == '0') { k->val &= ~m; k->xmask &= ~m; }
		else if (v == '1') { k->val |= m; k->xmask &= ~m; }
		else k->xmask |= m;
		if (!k->dirty) { k->dirty = 1; dirty_list[ndirty++] = e->refs[i].cell; }
	}
}

int main(int argc, char **argv)
{
	if (argc != 4) die("usage: vtube_power_vcd <plan> <vcd|-> <out>");
	read_plan(argv[1]);
	if (B > 64) die("too many blocks");
	FILE *in = strcmp(argv[2], "-") ? fopen(argv[2], "r") : stdin;
	if (!in) die("cannot open vcd");
	static char iobuf[1 << 22];
	setvbuf(in, iobuf, _IOFBF, sizeof iobuf);
	dirty_list = malloc(sizeof(int) * (N + 1));
	for (int c = 0; c < N; c++) row_add(&cells[c], cells[c].state, +1);

	/* header: resolve the pin paths to VCD ids */
	char line[1 << 16], scope[1 << 14] = "";
	size_t slen = 0;
	int bound = 0;
	double unit_ps = 1;            /* $timescale; the plan window is in ps */
	while (fgets(line, sizeof line, in)) {
		if (!strncmp(line, "$timescale", 10)) {
			char buf[256] = "";
			strncat(buf, line + 10, sizeof buf - 1);
			while (!strstr(buf, "$end") && fgets(line, sizeof line, in))
				strncat(buf, line, sizeof buf - strlen(buf) - 1);
			double num = 1; char unit[8] = "ps";
			char *q = buf;
			while (*q == ' ' || *q == '\t' || *q == '\n') q++;
			if (sscanf(q, "%lf %7[a-z]", &num, unit) >= 1) {
				double m = !strcmp(unit, "s") ? 1e12 : !strcmp(unit, "ms") ? 1e9 : !strcmp(unit, "us") ? 1e6 :
					   !strcmp(unit, "ns") ? 1e3 : !strcmp(unit, "fs") ? 1e-3 : 1;
				unit_ps = num * m;
			}
		} else if (!strncmp(line, "$scope", 6)) {
			char kind[64], name[4096];
			if (sscanf(line, "$scope %63s %4095s", kind, name) == 2) {
				if (slen) scope[slen++] = '/';
				size_t l = strlen(name);
				if (slen + l + 1 >= sizeof scope) die("scope too deep");
				memcpy(scope + slen, name, l + 1); slen += l;
			}
		} else if (!strncmp(line, "$upscope", 8)) {
			char *p = strrchr(scope, '/');
			slen = p ? (size_t)(p - scope) : 0; scope[slen] = 0;
		} else if (!strncmp(line, "$var", 4)) {
			char type[64], id[64], name[4096], full[1 << 15];
			int width;
			if (sscanf(line, "$var %63s %d %63s %4095s", type, &width, id, name) != 4 || width != 1)
				continue;
			snprintf(full, sizeof full, "%s/%s", scope, name);
			for (PathEnt *e = paths[hstr(full) & (PHASH - 1)]; e; e = e->next)
				if (!strcmp(e->path, full) && !e->found) { bind(id, e->ref); e->found = 1; bound++; }
		} else if (!strncmp(line, "$enddefinitions", 15))
			break;
	}
	window = (uint64_t)(window / unit_ps);
	if (!window) die("window below the VCD time unit");
	int npins = 0;
	for (int c = 0; c < N; c++) npins += cells[c].n;
	if (bound != npins) {
		fprintf(stderr, "vtube_power_vcd: %d of %d pins not found in the VCD:\n", npins - bound, npins);
		int shown = 0;
		for (int h = 0; h < PHASH && shown < 10; h++)
			for (PathEnt *e = paths[h]; e && shown < 10; e = e->next)
				if (!e->found) { fprintf(stderr, "  %s\n", e->path); shown++; }
		return 2;
	}

	/* value changes */
	uint64_t nchg = 0;
	int started = 0;
	while (fgets(line, sizeof line, in)) {
		char c = line[0];
		size_t l = strlen(line);
		while (l && (line[l - 1] == '\n' || line[l - 1] == '\r' || line[l - 1] == ' ')) line[--l] = 0;
		if (c == '#') {
			uint64_t t = strtoull(line + 1, NULL, 10);
			if (!started) {
				tnow = wstart = tfirst = t; started = 1;
				for (int k = 0; k < N; k++) cells[k].since = t;
			}
			settle();
			advance(t);
		} else if (c == '0' || c == '1' || c == 'x' || c == 'X' || c == 'z' || c == 'Z') {
			IdEnt *e = lookup(line + 1, l - 1);
			nchg++;
			if (e) set_pin(e, c == 'X' ? 'x' : c == 'Z' ? 'z' : c);
		} else if (c == 'b' || c == 'B') {
			char *sp = strchr(line, ' ');
			nchg++;
			if (!sp) continue;
			IdEnt *e = lookup(sp + 1, strlen(sp + 1));
			if (e) set_pin(e, sp[-1] == 'X' ? 'x' : sp[-1] == 'Z' ? 'z' : sp[-1]);
		}
	}
	settle();
	/* the run ends at the last timestamp; flush the histograms and the last window */
	for (int c = 0; c < N; c++) cells[c].hist[cells[c].state] += (double)(tnow - cells[c].since);
	if (tnow > wstart) {
		uint64_t part = tnow - wstart;
		for (int b = 0; b < B; b++)
			for (int r = 0; r < R; r++) {
				double m = wq[b][r] / part;
				if (part * 2 >= window && m > peak[b][r]) peak[b][r] = m;
			}
		for (int r = 0; r < R; r++) {
			double m = wqt[r] / part;
			if (part * 2 >= window && m > peakt[r]) peakt[r] = m;
		}
	}

	FILE *o = fopen(argv[3], "w");
	if (!o) die("cannot write output");
	fprintf(o, "time %.0f\nchanges %lu\n", (double)(tnow - tfirst) * unit_ps, (unsigned long)nchg);
	for (int b = 0; b < B; b++) {
		fprintf(o, "peak %d", b);
		for (int r = 0; r < R; r++) fprintf(o, " %.6g", peak[b][r]);
		fprintf(o, "\n");
	}
	fprintf(o, "peak -1");
	for (int r = 0; r < R; r++) fprintf(o, " %.6g", peakt[r]);
	fprintf(o, "\n");
	for (int c = 0; c < N; c++) {
		fprintf(o, "hist %d", c);
		for (int s = 0; s <= (1 << cells[c].n); s++) fprintf(o, " %.17g", cells[c].hist[s]);
		fprintf(o, "\n");
	}
	fclose(o);
	return 0;
}
