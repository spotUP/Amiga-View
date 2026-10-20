// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * STK1160 driver
 *
 * Copyright (C) 2012 Ezequiel Garcia
 * <elezegarcia--a.t--gmail.com>
 *
 * Based on Easycap driver by R.M. Thomas
 *	Copyright (C) 2010 R.M. Thomas
 *	<rmthomas--a.t--sciolus.org>
 */

#include <linux/module.h>
#include <linux/usb.h>
#include <linux/slab.h>
#include <linux/ratelimit.h>
#include <linux/sizes.h>
#include <linux/math.h>

#include "stk1160.h"
#include "stk1160-fieldfix.h"

static unsigned int debug;
module_param(debug, int, 0644);
MODULE_PARM_DESC(debug, "enable debug messages");

/* Totals since module load, readable in /sys/module/stk1160/parameters */
static unsigned int total_lost_pkts, total_fixed_fields, total_unfixed_fields;
module_param_named(lost_total, total_lost_pkts, uint, 0444);
module_param_named(fixed_total, total_fixed_fields, uint, 0444);
module_param_named(unfixed_total, total_unfixed_fields, uint, 0444);

static inline void print_err_status(struct stk1160 *dev,
				     int packet, int status)
{
	char *errmsg = "Unknown";

	switch (status) {
	case -ENOENT:
		errmsg = "unlinked synchronously";
		break;
	case -ECONNRESET:
		errmsg = "unlinked asynchronously";
		break;
	case -ENOSR:
		errmsg = "Buffer error (overrun)";
		break;
	case -EPIPE:
		errmsg = "Stalled (device not responding)";
		break;
	case -EOVERFLOW:
		errmsg = "Babble (bad cable?)";
		break;
	case -EPROTO:
		errmsg = "Bit-stuff error (bad cable?)";
		break;
	case -EILSEQ:
		errmsg = "CRC/Timeout (could be anything)";
		break;
	case -ETIME:
		errmsg = "Device does not respond";
		break;
	}

	if (packet < 0)
		printk_ratelimited(KERN_WARNING "URB status %d [%s].\n",
				status, errmsg);
	else
		printk_ratelimited(KERN_INFO "URB packet %d, status %d [%s].\n",
			       packet, status, errmsg);
}

static inline
struct stk1160_buffer *stk1160_next_buffer(struct stk1160 *dev)
{
	struct stk1160_buffer *buf = NULL;
	unsigned long flags = 0;

	/* Current buffer must be NULL when this functions gets called */
	WARN_ON(dev->isoc_ctl.buf);

	spin_lock_irqsave(&dev->buf_lock, flags);
	if (!list_empty(&dev->avail_bufs)) {
		buf = list_first_entry(&dev->avail_bufs,
				struct stk1160_buffer, list);
		list_del(&buf->list);
	}
	spin_unlock_irqrestore(&dev->buf_lock, flags);

	return buf;
}

/*
 * A field ended. If exactly one packet was lost in it, the lost packet's
 * size is the field shortfall: move the data after the hole later by it.
 */
static void stk1160_field_end(struct stk1160 *dev)
{
	struct stk1160_buffer *buf = dev->isoc_ctl.buf;
	unsigned int bpl = dev->width * 2;
	unsigned int field_size = bpl * (dev->height / 2);
	unsigned int shift;

	if (buf->holes == 1) {
		shift = stk1160_fix_field(buf->mem, bpl, buf->odd,
					  dev->field == V4L2_FIELD_ALTERNATE, field_size,
					  buf->hole_pos, buf->pos,
					  dev->isoc_ctl.max_pkt_size - 4);
		if (shift) {
			buf->bytesused += shift;
			dev->isoc_ctl.fixed_fields++;
			total_fixed_fields++;
		} else {
			total_unfixed_fields++;
		}
		dev_dbg_ratelimited(dev->dev,
			"field end: hole at %u, shortfall %u, %s (lost %u, corrected %u)\n",
			buf->hole_pos, field_size - min(field_size, buf->pos),
			shift ? "corrected" : "left", dev->isoc_ctl.lost_pkts,
			dev->isoc_ctl.fixed_fields);
	} else if (buf->holes) {
		total_unfixed_fields++;
		dev_dbg_ratelimited(dev->dev,
			"field end: %u holes, left (lost %u, corrected %u)\n",
			buf->holes, dev->isoc_ctl.lost_pkts,
			dev->isoc_ctl.fixed_fields);
	}
	buf->holes = 0;
}

static inline
void stk1160_buffer_done(struct stk1160 *dev)
{
	struct stk1160_buffer *buf = dev->isoc_ctl.buf;

	stk1160_field_end(dev);
	buf->vb.sequence = dev->sequence++;
	if (dev->field == V4L2_FIELD_ALTERNATE)
		buf->vb.field = buf->odd ? V4L2_FIELD_TOP : V4L2_FIELD_BOTTOM;
	else
		buf->vb.field = V4L2_FIELD_INTERLACED;
	buf->vb.vb2_buf.timestamp = ktime_get_ns();

	vb2_set_plane_payload(&buf->vb.vb2_buf, 0, buf->bytesused);
	vb2_buffer_done(&buf->vb.vb2_buf, VB2_BUF_STATE_DONE);

	dev->isoc_ctl.buf = NULL;
}

static inline
void stk1160_copy_video(struct stk1160 *dev, u8 *src, int len)
{
	int lencopy, offset;
	int bytesperline = dev->width * 2;
	struct stk1160_buffer *buf = dev->isoc_ctl.buf;
	u8 *dst = buf->mem;
	int remain;
	int alt = dev->field == V4L2_FIELD_ALTERNATE;
	/* Gap between two lines of this field in the buffer */
	int skip = alt ? 0 : bytesperline;

	/*
	 * TODO: These stk1160_dbg are very spammy!
	 * We should check why we are getting them.
	 *
	 * UPDATE: One of the reasons (the only one?) for getting these
	 * is incorrect standard (mismatch between expected and configured).
	 * So perhaps, we could add a counter for errors. When the counter
	 * reaches some value, we simply stop streaming.
	 */

	len -= 4;
	src += 4;

	remain = len;

	dst += stk1160_field_addr(bytesperline, buf->odd, alt, buf->pos);

	/* Copy the remaining of current line */
	lencopy = min(remain, bytesperline - (int)(buf->pos % bytesperline));

	/*
	 * Check if we have enough space left in the buffer.
	 * In that case, we force loop exit after copy.
	 */
	offset = dst - (u8 *)buf->mem;
	if (offset > buf->length) {
		dev_warn_ratelimited(dev->dev, "out of bounds offset\n");
		return;
	}
	if (lencopy > buf->length - offset) {
		lencopy = buf->length - offset;
		remain = lencopy;
	}

	/* Check if the copy is done */
	if (lencopy == 0 || remain == 0)
		return;

	/* Let the bug hunt begin! sanity checks! */
	if (lencopy < 0) {
		printk_ratelimited(KERN_DEBUG "copy skipped: negative lencopy\n");
		return;
	}

	if ((unsigned long)dst + lencopy >
		(unsigned long)buf->mem + buf->length) {
		printk_ratelimited(KERN_WARNING "stk1160: buffer overflow detected\n");
		return;
	}

	memcpy(dst, src, lencopy);

	buf->bytesused += lencopy;
	buf->pos += lencopy;
	remain -= lencopy;

	/* Copy current field line by line, interlacing with the other field */
	while (remain > 0) {

		dst += lencopy + skip;
		src += lencopy;

		/* Copy one line at a time */
		lencopy = min(remain, bytesperline);

		/*
		 * Check if we have enough space left in the buffer.
		 * In that case, we force loop exit after copy.
		 */
		offset = dst - (u8 *)buf->mem;
		if (offset > buf->length) {
			dev_warn_ratelimited(dev->dev, "offset out of bounds\n");
			return;
		}
		if (lencopy > buf->length - offset) {
			lencopy = buf->length - offset;
			remain = lencopy;
		}

		/* Check if the copy is done */
		if (lencopy == 0 || remain == 0)
			return;

		if (lencopy < 0) {
			printk_ratelimited(KERN_WARNING "stk1160: negative lencopy detected\n");
			return;
		}

		if ((unsigned long)dst + lencopy >
			(unsigned long)buf->mem + buf->length) {
			printk_ratelimited(KERN_WARNING "stk1160: buffer overflow detected\n");
			return;
		}

		memcpy(dst, src, lencopy);
		remain -= lencopy;

		buf->bytesused += lencopy;
		buf->pos += lencopy;
	}
}

/*
 * Controls the isoc copy of each urb packet
 */
/*
 * A packet was lost inside a field. Its size is unknown here (the device
 * mixes 3072 and 2048 byte packets), so do not move pos: record the hole and
 * let stk1160_field_end() repair the field from the measured shortfall.
 */
static void stk1160_skip_video(struct stk1160 *dev)
{
	struct stk1160_buffer *buf = dev->isoc_ctl.buf;

	dev->isoc_ctl.lost_pkts++;
	total_lost_pkts++;
	if (buf->holes++ == 0)
		buf->hole_pos = buf->pos;
	dev_dbg_ratelimited(dev->dev, "lost packet, hole at %u, %u so far\n",
			    buf->hole_pos, dev->isoc_ctl.lost_pkts);
}

static void stk1160_process_isoc(struct stk1160 *dev, struct urb *urb)
{
	int i, len, status;
	u8 *p;

	if (!dev) {
		stk1160_warn("%s called with null device\n", __func__);
		return;
	}

	if (urb->status < 0) {
		/* Print status and drop current packet (or field?) */
		print_err_status(dev, -1, urb->status);
		return;
	}

	for (i = 0; i < urb->number_of_packets; i++) {
		status = urb->iso_frame_desc[i].status;
		if (status < 0) {
			print_err_status(dev, i, status);
			if (dev->isoc_ctl.buf)
				stk1160_skip_video(dev);
			continue;
		}

		/* Get packet actual length and pointer to data */
		p = urb->transfer_buffer + urb->iso_frame_desc[i].offset;
		len = urb->iso_frame_desc[i].actual_length;

		/* Empty packet */
		if (len <= 4)
			continue;

		/*
		 * An 8-byte packet sequence means end of field.
		 * So if we don't have any packet, we start receiving one now
		 * and if we do have a packet, then we are done with it.
		 *
		 * These end of field packets are always 0xc0 or 0x80,
		 * but not always 8-byte long so we don't check packet length.
		 */
		if (p[0] == 0xc0 || (p[0] == 0x80 &&
				     dev->field == V4L2_FIELD_ALTERNATE)) {

			/*
			 * If first byte is 0xc0 then we received
			 * second field, and frame has ended. In
			 * V4L2_FIELD_ALTERNATE every field start (0xc0
			 * or 0x80) ends the buffer of the field before,
			 * so a field leaves one field period earlier.
			 */
			if (dev->isoc_ctl.buf != NULL)
				stk1160_buffer_done(dev);

			dev->isoc_ctl.buf = stk1160_next_buffer(dev);
			if (dev->isoc_ctl.buf == NULL)
				return;
		}

		/*
		 * If we don't have a buffer here, then it means we
		 * haven't found the start mark sequence.
		 */
		if (dev->isoc_ctl.buf == NULL)
			continue;

		if (p[0] == 0xc0 || p[0] == 0x80) {

			/* We set next packet parity and
			 * continue to get next one
			 */
			if (p[0] == 0x80 && dev->field != V4L2_FIELD_ALTERNATE)
				stk1160_field_end(dev);
			dev->isoc_ctl.buf->odd = *p & 0x40;
			dev->isoc_ctl.buf->pos = 0;
			dev->isoc_ctl.buf->holes = 0;
			continue;
		}

		dev->isoc_ctl.last_payload = len - 4;
		stk1160_copy_video(dev, p, len);
	}
}


/*
 * IRQ callback, called by URB callback
 */
static void stk1160_isoc_irq(struct urb *urb)
{
	int i, rc;
	struct stk1160 *dev = urb->context;

	switch (urb->status) {
	case 0:
		break;
	case -ECONNRESET:   /* kill */
	case -ENOENT:
	case -ESHUTDOWN:
		/* TODO: check uvc driver: he frees the queue here */
		return;
	default:
		stk1160_err("urb error! status %d\n", urb->status);
		return;
	}

	stk1160_process_isoc(dev, urb);

	/* Reset urb buffers */
	for (i = 0; i < urb->number_of_packets; i++) {
		urb->iso_frame_desc[i].status = 0;
		urb->iso_frame_desc[i].actual_length = 0;
	}

	rc = usb_submit_urb(urb, GFP_ATOMIC);
	if (rc)
		stk1160_err("urb re-submit failed (%d)\n", rc);
}

/*
 * Cancel urbs
 * This function can't be called in atomic context
 */
void stk1160_cancel_isoc(struct stk1160 *dev)
{
	int i, num_bufs = dev->isoc_ctl.num_bufs;

	/*
	 * This check is not necessary, but we add it
	 * to avoid a spurious debug message
	 */
	if (!num_bufs)
		return;

	stk1160_dbg("killing %d urbs...\n", num_bufs);

	for (i = 0; i < num_bufs; i++) {

		/*
		 * To kill urbs we can't be in atomic context.
		 * We don't care for NULL pointer since
		 * usb_kill_urb allows it.
		 */
		usb_kill_urb(dev->isoc_ctl.urb_ctl[i].urb);
	}

	stk1160_dbg("all urbs killed\n");
}

static void stk_free_urb(struct stk1160 *dev, struct stk1160_urb *stk_urb)
{
	usb_free_noncoherent(dev->udev, stk_urb->urb->transfer_buffer_length,
			     stk_urb->transfer_buffer, DMA_FROM_DEVICE,
			     stk_urb->sgt);
	usb_free_urb(stk_urb->urb);

	stk_urb->transfer_buffer = NULL;
	stk_urb->sgt = NULL;
	stk_urb->urb = NULL;
	stk_urb->dev = NULL;
	stk_urb->dma = 0;
}

/*
 * Releases urb and transfer buffers
 * Obviusly, associated urb must be killed before releasing it.
 */
void stk1160_free_isoc(struct stk1160 *dev)
{
	int i, num_bufs = dev->isoc_ctl.num_bufs;

	stk1160_dbg("freeing %d urb buffers...\n", num_bufs);

	for (i = 0; i < num_bufs; i++)
		stk_free_urb(dev, &dev->isoc_ctl.urb_ctl[i]);

	dev->isoc_ctl.num_bufs = 0;

	stk1160_dbg("all urb buffers freed\n");
}

/*
 * Helper for cancelling and freeing urbs
 * This function can't be called in atomic context
 */
void stk1160_uninit_isoc(struct stk1160 *dev)
{
	stk1160_cancel_isoc(dev);
	stk1160_free_isoc(dev);
}

static int stk1160_fill_urb(struct stk1160 *dev, struct stk1160_urb *stk_urb,
			    int sb_size, int max_packets)
{
	stk_urb->urb = usb_alloc_urb(max_packets, GFP_KERNEL);
	if (!stk_urb->urb)
		return -ENOMEM;

	stk_urb->transfer_buffer = usb_alloc_noncoherent(dev->udev, sb_size,
							 GFP_KERNEL, &stk_urb->dma,
							 DMA_FROM_DEVICE, &stk_urb->sgt);
	if (!stk_urb->transfer_buffer) {
		/*
		 * If the buffer allocation failed, we exit but return 0 since
		 * we allow the driver working with less buffers.
		 */
		goto free_urb;
	}

	stk_urb->dev = dev;
	return 0;

free_urb:
	usb_free_urb(stk_urb->urb);
	stk_urb->urb = NULL;

	return 0;
}
/*
 * Lay out the isoc packets of one URB so that no packet straddles a 64 KiB
 * boundary of the transfer buffer.  xhci splits a TD at every 64 KiB boundary
 * into two TRBs.  With 3072-byte packets back to back, packet 42 starts at
 * 129024 and is split 2048 + 1024 at 128 KiB; when the device sends a 2048-byte
 * packet there (short transfer ending exactly at the TRB end), the Pi 4's VL805
 * reports it as -EXDEV and the data is lost, about 25 times a second.  Starting
 * each packet that would cross a boundary at the boundary keeps every packet
 * in one TRB.  The buffer comes from the page allocator in one naturally
 * aligned block, so buffer offsets match the DMA address boundaries.
 * Returns the buffer size needed; fills the descriptors when urb is non-NULL.
 */
static int stk1160_isoc_layout(struct urb *urb, int max_packets, int pkt_size)
{
	const int seg = SZ_64K;
	int j, k = 0;

	for (j = 0; j < max_packets; j++) {
		if (pkt_size <= seg && (k % seg) + pkt_size > seg)
			k = round_up(k, seg);
		if (urb) {
			urb->iso_frame_desc[j].offset = k;
			urb->iso_frame_desc[j].length = pkt_size;
		}
		k += pkt_size;
	}
	return k;
}

/*
 * Allocate URBs
 */
int stk1160_alloc_isoc(struct stk1160 *dev)
{
	struct urb *urb;
	int i, sb_size, max_packets, num_bufs;
	int ret;

	/*
	 * It may be necessary to release isoc here,
	 * since isoc are only released on disconnection.
	 * (see new_pkt_size flag)
	 */
	if (dev->isoc_ctl.num_bufs)
		stk1160_uninit_isoc(dev);

	stk1160_dbg("allocating urbs...\n");

	num_bufs = STK1160_NUM_BUFS;
	max_packets = STK1160_NUM_PACKETS;
	sb_size = stk1160_isoc_layout(NULL, max_packets, dev->max_pkt_size);

	dev->isoc_ctl.buf = NULL;
	dev->isoc_ctl.max_pkt_size = dev->max_pkt_size;

	/* allocate urbs and transfer buffers */
	for (i = 0; i < num_bufs; i++) {

		ret = stk1160_fill_urb(dev, &dev->isoc_ctl.urb_ctl[i],
				       sb_size, max_packets);
		if (ret)
			goto free_i_bufs;

		urb = dev->isoc_ctl.urb_ctl[i].urb;

		if (!urb) {
			/* Not enough transfer buffers, so just give up */
			if (i < STK1160_MIN_BUFS)
				goto free_i_bufs;
			goto nomore_tx_bufs;
		}
		memset(dev->isoc_ctl.urb_ctl[i].transfer_buffer, 0, sb_size);

		/*
		 * FIXME: Where can I get the endpoint?
		 */
		urb->dev = dev->udev;
		urb->pipe = usb_rcvisocpipe(dev->udev, STK1160_EP_VIDEO);
		urb->transfer_buffer = dev->isoc_ctl.urb_ctl[i].transfer_buffer;
		urb->transfer_buffer_length = sb_size;
		urb->complete = stk1160_isoc_irq;
		urb->context = dev;
		urb->interval = 1;
		urb->start_frame = 0;
		urb->number_of_packets = max_packets;
		urb->transfer_flags = URB_ISO_ASAP | URB_NO_TRANSFER_DMA_MAP;
		urb->transfer_dma = dev->isoc_ctl.urb_ctl[i].dma;
		urb->sgt = dev->isoc_ctl.urb_ctl[i].sgt;

		stk1160_isoc_layout(urb, max_packets,
				    dev->isoc_ctl.max_pkt_size);
	}

	stk1160_dbg("%d urbs allocated\n", num_bufs);

	/* At last we can say we have some buffers */
	dev->isoc_ctl.num_bufs = num_bufs;

	return 0;

nomore_tx_bufs:
	/*
	 * Failed to allocate desired buffer count. However, we may have
	 * enough to work fine, so we just free the extra urb,
	 * store the allocated count and keep going, fingers crossed!
	 */

	stk1160_warn("%d urbs allocated. Trying to continue...\n", i);

	dev->isoc_ctl.num_bufs = i;

	return 0;

free_i_bufs:
	/* Save the allocated buffers so far, so we can properly free them */
	dev->isoc_ctl.num_bufs = i;
	stk1160_free_isoc(dev);
	return -ENOMEM;
}

