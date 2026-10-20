/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Pure helpers for placing and repairing one field inside an interlaced
 * frame buffer. No driver state, so a host test can compile them.
 */
#ifndef STK1160_FIELDFIX_H
#define STK1160_FIELDFIX_H

#ifdef __KERNEL__
#include <linux/string.h>
#else
#include <string.h>
#endif

/* Byte offset in the frame buffer of field byte f (odd: first, else second) */
static inline unsigned int stk1160_field_addr(unsigned int bpl, int odd,
					      unsigned int f)
{
	return (odd ? 0 : bpl) + (f / bpl) * 2 * bpl + f % bpl;
}

/*
 * One packet was lost at field byte hole, the field holds pos bytes of a
 * field of field_size bytes. Move field bytes [hole, pos) later by
 * field_size - pos, last bytes first. Returns the shift, 0 when untouched
 * (shift outside 1..max_shift or hole beyond pos).
 */
static inline unsigned int stk1160_fix_field(u8 *mem, unsigned int bpl, int odd,
					     unsigned int field_size,
					     unsigned int hole, unsigned int pos,
					     unsigned int max_shift)
{
	unsigned int shift, n, src_end, dst_end, chunk, m;

	if (pos >= field_size || hole > pos)
		return 0;
	shift = field_size - pos;
	if (shift > max_shift)
		return 0;

	n = pos - hole;
	while (n > 0) {
		src_end = hole + n;
		dst_end = src_end + shift;
		chunk = n;
		m = (src_end - 1) % bpl + 1;
		if (m < chunk)
			chunk = m;
		m = (dst_end - 1) % bpl + 1;
		if (m < chunk)
			chunk = m;
		memmove(mem + stk1160_field_addr(bpl, odd, dst_end - chunk),
			mem + stk1160_field_addr(bpl, odd, src_end - chunk),
			chunk);
		n -= chunk;
	}
	return shift;
}

#endif
