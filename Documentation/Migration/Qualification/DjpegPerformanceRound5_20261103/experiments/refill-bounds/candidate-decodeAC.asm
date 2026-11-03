
/private/tmp/swiftjli-round5-evidence/refill-bounds/dct-candidate:	file format mach-o arm64

Disassembly of section __TEXT,__text:

0000000100071a34 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n>:
100071a34: f81a0ffc    	str	x28, [sp, #-0x60]!
100071a38: a9016bfb    	stp	x27, x26, [sp, #0x10]
100071a3c: a90263f9    	stp	x25, x24, [sp, #0x20]
100071a40: a9035bf7    	stp	x23, x22, [sp, #0x30]
100071a44: a9044ff4    	stp	x20, x19, [sp, #0x40]
100071a48: a9057bfd    	stp	x29, x30, [sp, #0x50]
100071a4c: 910143fd    	add	x29, sp, #0x50
100071a50: f101009f    	cmp	x4, #0x40
100071a54: 540012e1    	b.ne	0x100071cb0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x27c>
100071a58: aa0303f6    	mov	x22, x3
100071a5c: b40012a3    	cbz	x3, 0x100071cb0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x27c>
100071a60: aa1503f3    	mov	x19, x21
100071a64: aa0203f7    	mov	x23, x2
100071a68: aa0103f8    	mov	x24, x1
100071a6c: aa0003f4    	mov	x20, x0
100071a70: 6f00e400    	movi.2d	v0, #0000000000000000
100071a74: ad0702c0    	stp	q0, q0, [x22, #0xe0]
100071a78: ad0602c0    	stp	q0, q0, [x22, #0xc0]
100071a7c: ad0502c0    	stp	q0, q0, [x22, #0xa0]
100071a80: ad0402c0    	stp	q0, q0, [x22, #0x80]
100071a84: ad0302c0    	stp	q0, q0, [x22, #0x60]
100071a88: ad0202c0    	stp	q0, q0, [x22, #0x40]
100071a8c: d10012c8    	sub	x8, x22, #0x4
100071a90: f90007e8    	str	x8, [sp, #0x8]
100071a94: ad0102c0    	stp	q0, q0, [x22, #0x20]
100071a98: 9100805b    	add	x27, x2, #0x20
100071a9c: 52800039    	mov	w25, #0x1               ; =1
100071aa0: 5280081c    	mov	w28, #0x40              ; =64
100071aa4: ad0002c0    	stp	q0, q0, [x22]
100071aa8: 14000004    	b	0x100071ab8 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x84>
100071aac: 91004339    	add	x25, x25, #0x10
100071ab0: f101033f    	cmp	x25, #0x40
100071ab4: 5400126a    	b.ge	0x100071d00 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2cc>
100071ab8: f9401e88    	ldr	x8, [x20, #0x38]
100071abc: f100311f    	cmp	x8, #0xc
100071ac0: 540002cc    	b.gt	0x100071b18 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0xe4>
100071ac4: f9400e8a    	ldr	x10, [x20, #0x18]
100071ac8: b40001ea    	cbz	x10, 0x100071b04 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0xd0>
100071acc: f9401289    	ldr	x9, [x20, #0x20]
100071ad0: cb0a0129    	sub	x9, x9, x10
100071ad4: f100212b    	subs	x11, x9, #0x8
100071ad8: 54000163    	b.lo	0x100071b04 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0xd0>
100071adc: f9401689    	ldr	x9, [x20, #0x28]
100071ae0: eb09017f    	cmp	x11, x9
100071ae4: 5400010b    	b.lt	0x100071b04 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0xd0>
100071ae8: f869694a    	ldr	x10, [x10, x9]
100071aec: dac00d4a    	rev	x10, x10
100071af0: b207dbeb    	mov	x11, #-0x101010101010102 ; =-72340172838076674
100071af4: cb0a016b    	sub	x11, x11, x10
100071af8: 8a0b014b    	and	x11, x10, x11
100071afc: f201c17f    	tst	x11, #0x8080808080808080
100071b00: 54000620    	b.eq	0x100071bc4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x190>
100071b04: 52800100    	mov	w0, #0x8                ; =8
100071b08: 97fff5ee    	bl	0x10006f2c0 <_$s8SwiftJLI9BitReaderV10fillBuffer33_9B6CCCA236C7246A9623077FA8DFE944LL4upToySi_tF>
100071b0c: f9401e88    	ldr	x8, [x20, #0x38]
100071b10: f100351f    	cmp	x8, #0xd
100071b14: 5400078b    	b.lt	0x100071c04 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1d0>
100071b18: f9401a89    	ldr	x9, [x20, #0x30]
100071b1c: 1100cd0a    	add	w10, w8, #0x33
100071b20: 9aca2529    	lsr	x9, x9, x10
100071b24: 92403129    	and	x9, x9, #0x1fff
100071b28: f9400aea    	ldr	x10, [x23, #0x10]
100071b2c: eb0a013f    	cmp	x9, x10
100071b30: 54000f82    	b.hs	0x100071d20 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2ec>
100071b34: cb19038b    	sub	x11, x28, x25
100071b38: b8697b69    	ldr	w9, [x27, x9, lsl #2]
100071b3c: 7100013f    	cmp	w9, #0x0
100071b40: d3505d2a    	ubfx	x10, x9, #16, #8
100071b44: fa4a1168    	ccmp	x11, x10, #0x8, ne
100071b48: 540002ea    	b.ge	0x100071ba4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x170>
100071b4c: f9401a89    	ldr	x9, [x20, #0x30]
100071b50: d100210a    	sub	x10, x8, #0x8
100071b54: 9aca2529    	lsr	x9, x9, x10
100071b58: 92401d29    	and	x9, x9, #0xff
100071b5c: f1011d1f    	cmp	x8, #0x47
100071b60: 9a8983e9    	csel	x9, xzr, x9, hi
100071b64: f9401b0a    	ldr	x10, [x24, #0x30]
100071b68: f940094b    	ldr	x11, [x10, #0x10]
100071b6c: eb0b013f    	cmp	x9, x11
100071b70: 54000da2    	b.hs	0x100071d24 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2f0>
100071b74: 8b09014a    	add	x10, x10, x9
100071b78: 3940814a    	ldrb	w10, [x10, #0x20]
100071b7c: b400052a    	cbz	x10, 0x100071c20 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1ec>
100071b80: cb0a0108    	sub	x8, x8, x10
100071b84: f9001e88    	str	x8, [x20, #0x38]
100071b88: f9401f08    	ldr	x8, [x24, #0x38]
100071b8c: f940090a    	ldr	x10, [x8, #0x10]
100071b90: eb0a013f    	cmp	x9, x10
100071b94: 54000ca2    	b.hs	0x100071d28 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2f4>
100071b98: 8b090108    	add	x8, x8, x9
100071b9c: 39408100    	ldrb	w0, [x8, #0x20]
100071ba0: 14000026    	b	0x100071c38 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x204>
100071ba4: cb496108    	sub	x8, x8, x9, lsr #24
100071ba8: f9001e88    	str	x8, [x20, #0x38]
100071bac: 34000aaa    	cbz	w10, 0x100071d00 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2cc>
100071bb0: 8b0a0339    	add	x25, x25, x10
100071bb4: 13003d28    	sxth	w8, w9
100071bb8: f94007e9    	ldr	x9, [sp, #0x8]
100071bbc: b8397928    	str	w8, [x9, x25, lsl #2]
100071bc0: 17ffffbc    	b	0x100071ab0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x7c>
100071bc4: cb08038b    	sub	x11, x28, x8
100071bc8: 927df16c    	and	x12, x11, #0xfffffffffffffff8
100071bcc: b4000108    	cbz	x8, 0x100071bec <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1b8>
100071bd0: f9401a8d    	ldr	x13, [x20, #0x30]
100071bd4: 927d096e    	and	x14, x11, #0x38
100071bd8: 9ace21ad    	lsl	x13, x13, x14
100071bdc: 4b0c03ee    	neg	w14, w12
100071be0: 927d09ce    	and	x14, x14, #0x38
100071be4: 9ace254a    	lsr	x10, x10, x14
100071be8: aa0a01aa    	orr	x10, x13, x10
100071bec: 8b080188    	add	x8, x12, x8
100071bf0: a903228a    	stp	x10, x8, [x20, #0x30]
100071bf4: 8b8b0d29    	add	x9, x9, x11, asr #3
100071bf8: f9001689    	str	x9, [x20, #0x28]
100071bfc: f100351f    	cmp	x8, #0xd
100071c00: 54fff8ca    	b.ge	0x100071b18 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0xe4>
100071c04: f1001d1f    	cmp	x8, #0x7
100071c08: 54fffa2c    	b.gt	0x100071b4c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x118>
100071c0c: 52800100    	mov	w0, #0x8                ; =8
100071c10: 97fff5ac    	bl	0x10006f2c0 <_$s8SwiftJLI9BitReaderV10fillBuffer33_9B6CCCA236C7246A9623077FA8DFE944LL4upToySi_tF>
100071c14: f9401e88    	ldr	x8, [x20, #0x38]
100071c18: f100211f    	cmp	x8, #0x8
100071c1c: 54fff98a    	b.ge	0x100071b4c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x118>
100071c20: aa1403e0    	mov	x0, x20
100071c24: aa1803e1    	mov	x1, x24
100071c28: aa1303f5    	mov	x21, x19
100071c2c: 97fffd37    	bl	0x100071108 <_$s8SwiftJLI14HuffmanDecoderO017decodeSymbolBitByG04from5tables5UInt8VAA0G6ReaderVz_AA0C5TableVtKFZTf4nnd_n>
100071c30: aa1503f3    	mov	x19, x21
100071c34: b5000675    	cbnz	x21, 0x100071d00 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2cc>
100071c38: 12001c08    	and	w8, w0, #0xff
100071c3c: 7103c11f    	cmp	w8, #0xf0
100071c40: 54fff360    	b.eq	0x100071aac <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x78>
100071c44: 340005e8    	cbz	w8, 0x100071d00 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2cc>
100071c48: 53041c08    	ubfx	w8, w0, #4, #4
100071c4c: 8b08033a    	add	x26, x25, x8
100071c50: f100ff5f    	cmp	x26, #0x3f
100071c54: 5400056c    	b.gt	0x100071d00 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2cc>
100071c58: 72000c1f    	tst	w0, #0xf
100071c5c: 54000180    	b.eq	0x100071c8c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x258>
100071c60: 92400c19    	and	x25, x0, #0xf
100071c64: aa1903e0    	mov	x0, x25
100071c68: aa1303f5    	mov	x21, x19
100071c6c: 97fff2ec    	bl	0x10006e81c <_$s8SwiftJLI9BitReaderV8readBitsys6UInt32VSiKF>
100071c70: aa1503f3    	mov	x19, x21
100071c74: b5000475    	cbnz	x21, 0x100071d00 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2cc>
100071c78: 51000728    	sub	w8, w25, #0x1
100071c7c: 1ac82408    	lsr	w8, w0, w8
100071c80: 340000a8    	cbz	w8, 0x100071c94 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x260>
100071c84: 36f80100    	tbz	w0, #0x1f, 0x100071ca4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x270>
100071c88: 14000029    	b	0x100071d2c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2f8>
100071c8c: 52800000    	mov	w0, #0x0                ; =0
100071c90: 14000005    	b	0x100071ca4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x270>
100071c94: 12800008    	mov	w8, #-0x1               ; =-1
100071c98: 1ad92108    	lsl	w8, w8, w25
100071c9c: 0b080008    	add	w8, w0, w8
100071ca0: 11000500    	add	w0, w8, #0x1
100071ca4: b83a7ac0    	str	w0, [x22, x26, lsl #2]
100071ca8: 91000759    	add	x25, x26, #0x1
100071cac: 17ffff81    	b	0x100071ab0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x7c>
100071cb0: b0000108    	adrp	x8, 0x100092000 <_vImageConvert_RGB888toPlanar8+0x100092000>
100071cb4: 91378108    	add	x8, x8, #0xde0
100071cb8: d1008108    	sub	x8, x8, #0x20
100071cbc: b2410114    	orr	x20, x8, #0x8000000000000000
100071cc0: 97fe9cec    	bl	0x100019070 <_$s8SwiftJLI8JLIErrorOACs5ErrorAAWl>
100071cc4: aa0003e1    	mov	x1, x0
100071cc8: d0000180    	adrp	x0, 0x1000a3000 <_$s8SwiftJLI14SRGBICCProfileO4data_WZTv_r+0x758>
100071ccc: 91264000    	add	x0, x0, #0x990
100071cd0: d2800002    	mov	x2, #0x0                ; =0
100071cd4: 52800003    	mov	w3, #0x0                ; =0
100071cd8: 94006c06    	bl	0x10008ccf0 <_vImageConvert_RGB888toPlanar8+0x10008ccf0>
100071cdc: aa0003f3    	mov	x19, x0
100071ce0: d2800448    	mov	x8, #0x22               ; =34
100071ce4: f2fa0008    	movk	x8, #0xd000, lsl #48
100071ce8: a9005028    	stp	x8, x20, [x1]
100071cec: a9017c3f    	stp	xzr, xzr, [x1, #0x10]
100071cf0: 528000c8    	mov	w8, #0x6                ; =6
100071cf4: 39008028    	strb	w8, [x1, #0x20]
100071cf8: aa0003f5    	mov	x21, x0
100071cfc: 94006c8a    	bl	0x10008cf24 <_vImageConvert_RGB888toPlanar8+0x10008cf24>
100071d00: aa1303f5    	mov	x21, x19
100071d04: a9457bfd    	ldp	x29, x30, [sp, #0x50]
100071d08: a9444ff4    	ldp	x20, x19, [sp, #0x40]
100071d0c: a9435bf7    	ldp	x23, x22, [sp, #0x30]
100071d10: a94263f9    	ldp	x25, x24, [sp, #0x20]
100071d14: a9416bfb    	ldp	x27, x26, [sp, #0x10]
100071d18: f84607fc    	ldr	x28, [sp], #0x60
100071d1c: d65f03c0    	ret
100071d20: d4200020    	brk	#0x1
100071d24: d4200020    	brk	#0x1
100071d28: d4200020    	brk	#0x1
100071d2c: d4200020    	brk	#0x1
