/* Host test: gcc -o t fieldfix_test.c && ./t   (also runs the old skip model) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned char u8;
#include "stk1160-fieldfix.h"
#define BPL 1440u
#define LINES 288u
#define FS (BPL * LINES)
static u8 val(unsigned f) { return (u8)(f * 2654435761u >> 24); }
/* write field bytes [from,to) of the true stream at stream positions */
static int run(int odd, unsigned hole, int fix)
{
	static u8 mem[2 * FS], want[2 * FS];
	unsigned f, pos = 0, bad = 0, lost = 2044;
	memset(mem, 0xEE, sizeof mem);
	memset(want, 0xEE, sizeof want);
	for (f = 0; f < FS; f++) want[stk1160_field_addr(BPL, odd, f)] = val(f);
	/* stream: bytes before hole, lost bytes, then rest; driver does not move pos at loss */
	for (f = 0; f < hole; f++) mem[stk1160_field_addr(BPL, odd, pos++)] = val(f);
	for (f = hole + lost; f < FS; f++) mem[stk1160_field_addr(BPL, odd, pos++)] = val(f);
	if (fix) {
		if (stk1160_fix_field(mem, BPL, odd, FS, hole, pos, 3068) != lost) return -1;
	} else { /* old logic: skip 3068 at loss, rest lands 1024 late */
		memset(mem, 0xEE, sizeof mem); pos = 0;
		for (f = 0; f < hole; f++) mem[stk1160_field_addr(BPL, odd, pos++)] = val(f);
		pos += 3068;
		for (f = hole + lost; f < FS && pos < FS; f++) mem[stk1160_field_addr(BPL, odd, pos++)] = val(f);
	}
	for (f = hole + lost; f < FS; f++)
		if (mem[stk1160_field_addr(BPL, odd, f)] != want[stk1160_field_addr(BPL, odd, f)]) bad++;
	for (f = 0; f < hole; f++)
		if (mem[stk1160_field_addr(BPL, odd, f)] != want[stk1160_field_addr(BPL, odd, f)]) bad++;
	return bad;
}
int main(void)
{
	unsigned holes[] = { 0, 12272, 100000, 406980, FS - 2044 };
	int i, o, rc = 0;
	for (i = 0; i < 5; i++) for (o = 0; o < 2; o++) {
		int a = run(o, holes[i], 1), b = run(o, holes[i], 0);
		printf("hole %u odd %d: fix bad=%d  oldskip bad=%d\n", holes[i], o, a, b);
		if (a != 0) rc = 1;
		if (b == 0 && holes[i] + 2044 < FS) rc = 1;
	}
	puts(rc ? "FAIL" : "PASS");
	return rc;
}
