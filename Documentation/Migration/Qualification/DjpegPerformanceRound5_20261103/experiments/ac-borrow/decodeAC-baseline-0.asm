
/private/tmp/swiftjli-round5-evidence/ac-borrow/dct-baseline:	file format mach-o arm64

Disassembly of section __TEXT,__text:

0000000100071e44 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n>:
100071e44: f81a0ffc    	str	x28, [sp, #-0x60]!
100071e48: a9016bfb    	stp	x27, x26, [sp, #0x10]
100071e4c: a90263f9    	stp	x25, x24, [sp, #0x20]
100071e50: a9035bf7    	stp	x23, x22, [sp, #0x30]
100071e54: a9044ff4    	stp	x20, x19, [sp, #0x40]
100071e58: a9057bfd    	stp	x29, x30, [sp, #0x50]
100071e5c: 910143fd    	add	x29, sp, #0x50
100071e60: f101009f    	cmp	x4, #0x40
100071e64: 54001421    	b.ne	0x1000720e8 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2a4>
100071e68: aa0303f6    	mov	x22, x3
100071e6c: b40013e3    	cbz	x3, 0x1000720e8 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2a4>
100071e70: aa1503f3    	mov	x19, x21
100071e74: aa0203f7    	mov	x23, x2
100071e78: aa0103f8    	mov	x24, x1
100071e7c: aa0003f4    	mov	x20, x0
100071e80: 6f00e400    	movi.2d	v0, #0000000000000000
100071e84: ad0702c0    	stp	q0, q0, [x22, #0xe0]
100071e88: ad0602c0    	stp	q0, q0, [x22, #0xc0]
100071e8c: ad0502c0    	stp	q0, q0, [x22, #0xa0]
100071e90: ad0402c0    	stp	q0, q0, [x22, #0x80]
100071e94: ad0302c0    	stp	q0, q0, [x22, #0x60]
100071e98: ad0202c0    	stp	q0, q0, [x22, #0x40]
100071e9c: d10012c8    	sub	x8, x22, #0x4
100071ea0: f90007e8    	str	x8, [sp, #0x8]
100071ea4: ad0102c0    	stp	q0, q0, [x22, #0x20]
100071ea8: 9100805b    	add	x27, x2, #0x20
100071eac: 52800039    	mov	w25, #0x1               ; =1
100071eb0: 5280081c    	mov	w28, #0x40              ; =64
100071eb4: ad0002c0    	stp	q0, q0, [x22]
100071eb8: 14000004    	b	0x100071ec8 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x84>
100071ebc: 91004339    	add	x25, x25, #0x10
100071ec0: f101033f    	cmp	x25, #0x40
100071ec4: 540013aa    	b.ge	0x100072138 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2f4>
100071ec8: f9401e88    	ldr	x8, [x20, #0x38]
100071ecc: f100311f    	cmp	x8, #0xc
100071ed0: 540004ac    	b.gt	0x100071f64 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x120>
100071ed4: f9401689    	ldr	x9, [x20, #0x28]
100071ed8: b100212b    	adds	x11, x9, #0x8
100071edc: 54001426    	b.vs	0x100072160 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x31c>
100071ee0: f9400e8a    	ldr	x10, [x20, #0x18]
100071ee4: b400032a    	cbz	x10, 0x100071f48 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x104>
100071ee8: f940128c    	ldr	x12, [x20, #0x20]
100071eec: cb0a018c    	sub	x12, x12, x10
100071ef0: eb0b019f    	cmp	x12, x11
100071ef4: 540002eb    	b.lt	0x100071f50 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x10c>
100071ef8: f869694a    	ldr	x10, [x10, x9]
100071efc: dac00d4a    	rev	x10, x10
100071f00: b207dbeb    	mov	x11, #-0x101010101010102 ; =-72340172838076674
100071f04: cb0a016b    	sub	x11, x11, x10
100071f08: 8a0b014b    	and	x11, x10, x11
100071f0c: f201c17f    	tst	x11, #0x8080808080808080
100071f10: 54000201    	b.ne	0x100071f50 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x10c>
100071f14: eb08038b    	subs	x11, x28, x8
100071f18: 540012c6    	b.vs	0x100072170 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x32c>
100071f1c: b40007a8    	cbz	x8, 0x100072010 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1cc>
100071f20: 927df16c    	and	x12, x11, #0xfffffffffffffff8
100071f24: eb0c038d    	subs	x13, x28, x12
100071f28: 540012a6    	b.vs	0x10007217c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x338>
100071f2c: f9401a8e    	ldr	x14, [x20, #0x30]
100071f30: 927d096f    	and	x15, x11, #0x38
100071f34: 9acf21ce    	lsl	x14, x14, x15
100071f38: 927d09ad    	and	x13, x13, #0x38
100071f3c: 9acd254a    	lsr	x10, x10, x13
100071f40: aa0a01ca    	orr	x10, x14, x10
100071f44: 14000034    	b	0x100072014 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1d0>
100071f48: f100057f    	cmp	x11, #0x1
100071f4c: 540010eb    	b.lt	0x100072168 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x324>
100071f50: 52800100    	mov	w0, #0x8                ; =8
100071f54: 97fff5bc    	bl	0x10006f644 <_$s8SwiftJLI9BitReaderV10fillBuffer33_9B6CCCA236C7246A9623077FA8DFE944LL4upToySi_tF>
100071f58: f9401e88    	ldr	x8, [x20, #0x38]
100071f5c: f100351f    	cmp	x8, #0xd
100071f60: 540006eb    	b.lt	0x10007203c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1f8>
100071f64: f9401a89    	ldr	x9, [x20, #0x30]
100071f68: 1100cd0a    	add	w10, w8, #0x33
100071f6c: 9aca2529    	lsr	x9, x9, x10
100071f70: 92403129    	and	x9, x9, #0x1fff
100071f74: f9400aea    	ldr	x10, [x23, #0x10]
100071f78: eb0a013f    	cmp	x9, x10
100071f7c: 54000ee2    	b.hs	0x100072158 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x314>
100071f80: cb19038b    	sub	x11, x28, x25
100071f84: b8697b69    	ldr	w9, [x27, x9, lsl #2]
100071f88: 7100013f    	cmp	w9, #0x0
100071f8c: d3505d2a    	ubfx	x10, x9, #16, #8
100071f90: fa4a1168    	ccmp	x11, x10, #0x8, ne
100071f94: 540002ea    	b.ge	0x100071ff0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1ac>
100071f98: f9401a89    	ldr	x9, [x20, #0x30]
100071f9c: d100210a    	sub	x10, x8, #0x8
100071fa0: 9aca2529    	lsr	x9, x9, x10
100071fa4: 92401d29    	and	x9, x9, #0xff
100071fa8: f1011d1f    	cmp	x8, #0x47
100071fac: 9a8983e9    	csel	x9, xzr, x9, hi
100071fb0: f9401b0a    	ldr	x10, [x24, #0x30]
100071fb4: f940094b    	ldr	x11, [x10, #0x10]
100071fb8: eb0b013f    	cmp	x9, x11
100071fbc: 54000d02    	b.hs	0x10007215c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x318>
100071fc0: 8b09014a    	add	x10, x10, x9
100071fc4: 3940814a    	ldrb	w10, [x10, #0x20]
100071fc8: b400048a    	cbz	x10, 0x100072058 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x214>
100071fcc: cb0a0108    	sub	x8, x8, x10
100071fd0: f9001e88    	str	x8, [x20, #0x38]
100071fd4: f9401f08    	ldr	x8, [x24, #0x38]
100071fd8: f940090a    	ldr	x10, [x8, #0x10]
100071fdc: eb0a013f    	cmp	x9, x10
100071fe0: 54000c22    	b.hs	0x100072164 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x320>
100071fe4: 8b090108    	add	x8, x8, x9
100071fe8: 39408100    	ldrb	w0, [x8, #0x20]
100071fec: 14000021    	b	0x100072070 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x22c>
100071ff0: cb496108    	sub	x8, x8, x9, lsr #24
100071ff4: f9001e88    	str	x8, [x20, #0x38]
100071ff8: 34000a0a    	cbz	w10, 0x100072138 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2f4>
100071ffc: 8b0a0339    	add	x25, x25, x10
100072000: 13003d28    	sxth	w8, w9
100072004: f94007e9    	ldr	x9, [sp, #0x8]
100072008: b8397928    	str	w8, [x9, x25, lsl #2]
10007200c: 17ffffad    	b	0x100071ec0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x7c>
100072010: 5280080c    	mov	w12, #0x40              ; =64
100072014: f9001a8a    	str	x10, [x20, #0x30]
100072018: ab0c0108    	adds	x8, x8, x12
10007201c: 54000ac6    	b.vs	0x100072174 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x330>
100072020: 9343fd6a    	asr	x10, x11, #3
100072024: f9001e88    	str	x8, [x20, #0x38]
100072028: ab0a0129    	adds	x9, x9, x10
10007202c: 54000a66    	b.vs	0x100072178 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x334>
100072030: f9001689    	str	x9, [x20, #0x28]
100072034: f100351f    	cmp	x8, #0xd
100072038: 54fff96a    	b.ge	0x100071f64 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x120>
10007203c: f1001d1f    	cmp	x8, #0x7
100072040: 54fffacc    	b.gt	0x100071f98 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x154>
100072044: 52800100    	mov	w0, #0x8                ; =8
100072048: 97fff57f    	bl	0x10006f644 <_$s8SwiftJLI9BitReaderV10fillBuffer33_9B6CCCA236C7246A9623077FA8DFE944LL4upToySi_tF>
10007204c: f9401e88    	ldr	x8, [x20, #0x38]
100072050: f100211f    	cmp	x8, #0x8
100072054: 54fffa2a    	b.ge	0x100071f98 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x154>
100072058: aa1403e0    	mov	x0, x20
10007205c: aa1803e1    	mov	x1, x24
100072060: aa1303f5    	mov	x21, x19
100072064: 97fffd2d    	bl	0x100071518 <_$s8SwiftJLI14HuffmanDecoderO017decodeSymbolBitByG04from5tables5UInt8VAA0G6ReaderVz_AA0C5TableVtKFZTf4nnd_n>
100072068: aa1503f3    	mov	x19, x21
10007206c: b5000675    	cbnz	x21, 0x100072138 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2f4>
100072070: 12001c08    	and	w8, w0, #0xff
100072074: 7103c11f    	cmp	w8, #0xf0
100072078: 54fff220    	b.eq	0x100071ebc <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x78>
10007207c: 340005e8    	cbz	w8, 0x100072138 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2f4>
100072080: 53041c08    	ubfx	w8, w0, #4, #4
100072084: 8b08033a    	add	x26, x25, x8
100072088: f100ff5f    	cmp	x26, #0x3f
10007208c: 5400056c    	b.gt	0x100072138 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2f4>
100072090: 72000c1f    	tst	w0, #0xf
100072094: 54000180    	b.eq	0x1000720c4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x280>
100072098: 92400c19    	and	x25, x0, #0xf
10007209c: aa1903e0    	mov	x0, x25
1000720a0: aa1303f5    	mov	x21, x19
1000720a4: 97fff2ac    	bl	0x10006eb54 <_$s8SwiftJLI9BitReaderV8readBitsys6UInt32VSiKF>
1000720a8: aa1503f3    	mov	x19, x21
1000720ac: b5000475    	cbnz	x21, 0x100072138 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2f4>
1000720b0: 51000728    	sub	w8, w25, #0x1
1000720b4: 1ac82408    	lsr	w8, w0, w8
1000720b8: 340000a8    	cbz	w8, 0x1000720cc <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x288>
1000720bc: 36f80100    	tbz	w0, #0x1f, 0x1000720dc <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x298>
1000720c0: 1400002b    	b	0x10007216c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x328>
1000720c4: 52800000    	mov	w0, #0x0                ; =0
1000720c8: 14000005    	b	0x1000720dc <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x298>
1000720cc: 12800008    	mov	w8, #-0x1               ; =-1
1000720d0: 1ad92108    	lsl	w8, w8, w25
1000720d4: 0b080008    	add	w8, w0, w8
1000720d8: 11000500    	add	w0, w8, #0x1
1000720dc: b83a7ac0    	str	w0, [x22, x26, lsl #2]
1000720e0: 91000759    	add	x25, x26, #0x1
1000720e4: 17ffff77    	b	0x100071ec0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x7c>
1000720e8: b0000108    	adrp	x8, 0x100093000 <_vImageConvert_RGB888toPlanar8+0x100093000>
1000720ec: 91088108    	add	x8, x8, #0x220
1000720f0: d1008108    	sub	x8, x8, #0x20
1000720f4: b2410114    	orr	x20, x8, #0x8000000000000000
1000720f8: 97fe9bde    	bl	0x100019070 <_$s8SwiftJLI8JLIErrorOACs5ErrorAAWl>
1000720fc: aa0003e1    	mov	x1, x0
100072100: b0000180    	adrp	x0, 0x1000a3000 <_$s8SwiftJLI14SRGBICCProfileO4data_WZTv_r+0x758>
100072104: 91264000    	add	x0, x0, #0x990
100072108: d2800002    	mov	x2, #0x0                ; =0
10007210c: 52800003    	mov	w3, #0x0                ; =0
100072110: 94006c0c    	bl	0x10008d140 <_vImageConvert_RGB888toPlanar8+0x10008d140>
100072114: aa0003f3    	mov	x19, x0
100072118: d2800448    	mov	x8, #0x22               ; =34
10007211c: f2fa0008    	movk	x8, #0xd000, lsl #48
100072120: a9005028    	stp	x8, x20, [x1]
100072124: a9017c3f    	stp	xzr, xzr, [x1, #0x10]
100072128: 528000c8    	mov	w8, #0x6                ; =6
10007212c: 39008028    	strb	w8, [x1, #0x20]
100072130: aa0003f5    	mov	x21, x0
100072134: 94006c90    	bl	0x10008d374 <_vImageConvert_RGB888toPlanar8+0x10008d374>
100072138: aa1303f5    	mov	x21, x19
10007213c: a9457bfd    	ldp	x29, x30, [sp, #0x50]
100072140: a9444ff4    	ldp	x20, x19, [sp, #0x40]
100072144: a9435bf7    	ldp	x23, x22, [sp, #0x30]
100072148: a94263f9    	ldp	x25, x24, [sp, #0x20]
10007214c: a9416bfb    	ldp	x27, x26, [sp, #0x10]
100072150: f84607fc    	ldr	x28, [sp], #0x60
100072154: d65f03c0    	ret
100072158: d4200020    	brk	#0x1
10007215c: d4200020    	brk	#0x1
100072160: d4200020    	brk	#0x1
100072164: d4200020    	brk	#0x1
100072168: d4200020    	brk	#0x1
10007216c: d4200020    	brk	#0x1
100072170: d4200020    	brk	#0x1
100072174: d4200020    	brk	#0x1
100072178: d4200020    	brk	#0x1
10007217c: d4200020    	brk	#0x1
