
/private/tmp/swiftjli-round5-evidence/ac-borrow/dct-candidate:	file format mach-o arm64

Disassembly of section __TEXT,__text:

0000000100071f94 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n>:
100071f94: f81a0ffc    	str	x28, [sp, #-0x60]!
100071f98: a9016bfb    	stp	x27, x26, [sp, #0x10]
100071f9c: a90263f9    	stp	x25, x24, [sp, #0x20]
100071fa0: a9035bf7    	stp	x23, x22, [sp, #0x30]
100071fa4: a9044ff4    	stp	x20, x19, [sp, #0x40]
100071fa8: a9057bfd    	stp	x29, x30, [sp, #0x50]
100071fac: 910143fd    	add	x29, sp, #0x50
100071fb0: d28003a9    	mov	x9, #0x1d               ; =29
100071fb4: f2fa0009    	movk	x9, #0xd000, lsl #48
100071fb8: d0000108    	adrp	x8, 0x100093000 <_vImageConvert_RGB888toPlanar8+0x100093000>
100071fbc: 910e0108    	add	x8, x8, #0x380
100071fc0: d1008108    	sub	x8, x8, #0x20
100071fc4: 91001538    	add	x24, x9, #0x5
100071fc8: f101009f    	cmp	x4, #0x40
100071fcc: 54001461    	b.ne	0x100072258 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2c4>
100071fd0: aa0303f6    	mov	x22, x3
100071fd4: b4001423    	cbz	x3, 0x100072258 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2c4>
100071fd8: f9400848    	ldr	x8, [x2, #0x10]
100071fdc: f140091f    	cmp	x8, #0x2, lsl #12       ; =0x2000
100071fe0: 54001321    	b.ne	0x100072244 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2b0>
100071fe4: aa1503f3    	mov	x19, x21
100071fe8: aa0103f7    	mov	x23, x1
100071fec: aa0003f4    	mov	x20, x0
100071ff0: 6f00e400    	movi.2d	v0, #0000000000000000
100071ff4: ad0702c0    	stp	q0, q0, [x22, #0xe0]
100071ff8: ad0602c0    	stp	q0, q0, [x22, #0xc0]
100071ffc: ad0502c0    	stp	q0, q0, [x22, #0xa0]
100072000: ad0402c0    	stp	q0, q0, [x22, #0x80]
100072004: ad0302c0    	stp	q0, q0, [x22, #0x60]
100072008: ad0202c0    	stp	q0, q0, [x22, #0x40]
10007200c: 91008059    	add	x25, x2, #0x20
100072010: ad0102c0    	stp	q0, q0, [x22, #0x20]
100072014: d10012da    	sub	x26, x22, #0x4
100072018: 52800038    	mov	w24, #0x1               ; =1
10007201c: 5280081b    	mov	w27, #0x40              ; =64
100072020: ad0002c0    	stp	q0, q0, [x22]
100072024: 14000004    	b	0x100072034 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0xa0>
100072028: 91004318    	add	x24, x24, #0x10
10007202c: f101031f    	cmp	x24, #0x40
100072030: 5400132a    	b.ge	0x100072294 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x300>
100072034: f9401e88    	ldr	x8, [x20, #0x38]
100072038: f100311f    	cmp	x8, #0xc
10007203c: 540004ac    	b.gt	0x1000720d0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x13c>
100072040: f9401689    	ldr	x9, [x20, #0x28]
100072044: b100212b    	adds	x11, x9, #0x8
100072048: 54001386    	b.vs	0x1000722b8 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x324>
10007204c: f9400e8a    	ldr	x10, [x20, #0x18]
100072050: b400032a    	cbz	x10, 0x1000720b4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x120>
100072054: f940128c    	ldr	x12, [x20, #0x20]
100072058: cb0a018c    	sub	x12, x12, x10
10007205c: eb0b019f    	cmp	x12, x11
100072060: 540002eb    	b.lt	0x1000720bc <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x128>
100072064: f869694a    	ldr	x10, [x10, x9]
100072068: dac00d4a    	rev	x10, x10
10007206c: b207dbeb    	mov	x11, #-0x101010101010102 ; =-72340172838076674
100072070: cb0a016b    	sub	x11, x11, x10
100072074: 8a0b014b    	and	x11, x10, x11
100072078: f201c17f    	tst	x11, #0x8080808080808080
10007207c: 54000201    	b.ne	0x1000720bc <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x128>
100072080: eb08036b    	subs	x11, x27, x8
100072084: 54001226    	b.vs	0x1000722c8 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x334>
100072088: b4000728    	cbz	x8, 0x10007216c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1d8>
10007208c: 927df16c    	and	x12, x11, #0xfffffffffffffff8
100072090: eb0c036d    	subs	x13, x27, x12
100072094: 54001206    	b.vs	0x1000722d4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x340>
100072098: f9401a8e    	ldr	x14, [x20, #0x30]
10007209c: 927d096f    	and	x15, x11, #0x38
1000720a0: 9acf21ce    	lsl	x14, x14, x15
1000720a4: 927d09ad    	and	x13, x13, #0x38
1000720a8: 9acd254a    	lsr	x10, x10, x13
1000720ac: aa0a01ca    	orr	x10, x14, x10
1000720b0: 14000030    	b	0x100072170 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1dc>
1000720b4: f100057f    	cmp	x11, #0x1
1000720b8: 5400104b    	b.lt	0x1000722c0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x32c>
1000720bc: 52800100    	mov	w0, #0x8                ; =8
1000720c0: 97fff561    	bl	0x10006f644 <_$s8SwiftJLI9BitReaderV10fillBuffer33_9B6CCCA236C7246A9623077FA8DFE944LL4upToySi_tF>
1000720c4: f9401e88    	ldr	x8, [x20, #0x38]
1000720c8: f100351f    	cmp	x8, #0xd
1000720cc: 5400066b    	b.lt	0x100072198 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x204>
1000720d0: cb18036b    	sub	x11, x27, x24
1000720d4: f9401a89    	ldr	x9, [x20, #0x30]
1000720d8: 1100cd0a    	add	w10, w8, #0x33
1000720dc: 9aca2529    	lsr	x9, x9, x10
1000720e0: 92403129    	and	x9, x9, #0x1fff
1000720e4: b8697b29    	ldr	w9, [x25, x9, lsl #2]
1000720e8: 7100013f    	cmp	w9, #0x0
1000720ec: d3505d2a    	ubfx	x10, x9, #16, #8
1000720f0: fa4a1168    	ccmp	x11, x10, #0x8, ne
1000720f4: 540002ea    	b.ge	0x100072150 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x1bc>
1000720f8: f9401a89    	ldr	x9, [x20, #0x30]
1000720fc: d100210a    	sub	x10, x8, #0x8
100072100: 9aca2529    	lsr	x9, x9, x10
100072104: 92401d29    	and	x9, x9, #0xff
100072108: f1011d1f    	cmp	x8, #0x47
10007210c: 9a8983e9    	csel	x9, xzr, x9, hi
100072110: f9401aea    	ldr	x10, [x23, #0x30]
100072114: f940094b    	ldr	x11, [x10, #0x10]
100072118: eb0b013f    	cmp	x9, x11
10007211c: 54000cc2    	b.hs	0x1000722b4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x320>
100072120: 8b09014a    	add	x10, x10, x9
100072124: 3940814a    	ldrb	w10, [x10, #0x20]
100072128: b400046a    	cbz	x10, 0x1000721b4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x220>
10007212c: cb0a0108    	sub	x8, x8, x10
100072130: f9001e88    	str	x8, [x20, #0x38]
100072134: f9401ee8    	ldr	x8, [x23, #0x38]
100072138: f940090a    	ldr	x10, [x8, #0x10]
10007213c: eb0a013f    	cmp	x9, x10
100072140: 54000be2    	b.hs	0x1000722bc <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x328>
100072144: 8b090108    	add	x8, x8, x9
100072148: 39408100    	ldrb	w0, [x8, #0x20]
10007214c: 14000020    	b	0x1000721cc <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x238>
100072150: cb496108    	sub	x8, x8, x9, lsr #24
100072154: f9001e88    	str	x8, [x20, #0x38]
100072158: 340009ea    	cbz	w10, 0x100072294 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x300>
10007215c: 8b0a0318    	add	x24, x24, x10
100072160: 13003d28    	sxth	w8, w9
100072164: b8387b48    	str	w8, [x26, x24, lsl #2]
100072168: 17ffffb1    	b	0x10007202c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x98>
10007216c: 5280080c    	mov	w12, #0x40              ; =64
100072170: f9001a8a    	str	x10, [x20, #0x30]
100072174: ab0c0108    	adds	x8, x8, x12
100072178: 54000aa6    	b.vs	0x1000722cc <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x338>
10007217c: 9343fd6a    	asr	x10, x11, #3
100072180: f9001e88    	str	x8, [x20, #0x38]
100072184: ab0a0129    	adds	x9, x9, x10
100072188: 54000a46    	b.vs	0x1000722d0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x33c>
10007218c: f9001689    	str	x9, [x20, #0x28]
100072190: f100351f    	cmp	x8, #0xd
100072194: 54fff9ea    	b.ge	0x1000720d0 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x13c>
100072198: f1001d1f    	cmp	x8, #0x7
10007219c: 54fffaec    	b.gt	0x1000720f8 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x164>
1000721a0: 52800100    	mov	w0, #0x8                ; =8
1000721a4: 97fff528    	bl	0x10006f644 <_$s8SwiftJLI9BitReaderV10fillBuffer33_9B6CCCA236C7246A9623077FA8DFE944LL4upToySi_tF>
1000721a8: f9401e88    	ldr	x8, [x20, #0x38]
1000721ac: f100211f    	cmp	x8, #0x8
1000721b0: 54fffa4a    	b.ge	0x1000720f8 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x164>
1000721b4: aa1403e0    	mov	x0, x20
1000721b8: aa1703e1    	mov	x1, x23
1000721bc: aa1303f5    	mov	x21, x19
1000721c0: 97fffd2a    	bl	0x100071668 <_$s8SwiftJLI14HuffmanDecoderO017decodeSymbolBitByG04from5tables5UInt8VAA0G6ReaderVz_AA0C5TableVtKFZTf4nnd_n>
1000721c4: aa1503f3    	mov	x19, x21
1000721c8: b5000675    	cbnz	x21, 0x100072294 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x300>
1000721cc: 12001c08    	and	w8, w0, #0xff
1000721d0: 7103c11f    	cmp	w8, #0xf0
1000721d4: 54fff2a0    	b.eq	0x100072028 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x94>
1000721d8: 340005e8    	cbz	w8, 0x100072294 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x300>
1000721dc: 53041c08    	ubfx	w8, w0, #4, #4
1000721e0: 8b08031c    	add	x28, x24, x8
1000721e4: f100ff9f    	cmp	x28, #0x3f
1000721e8: 5400056c    	b.gt	0x100072294 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x300>
1000721ec: 72000c1f    	tst	w0, #0xf
1000721f0: 54000180    	b.eq	0x100072220 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x28c>
1000721f4: 92400c18    	and	x24, x0, #0xf
1000721f8: aa1803e0    	mov	x0, x24
1000721fc: aa1303f5    	mov	x21, x19
100072200: 97fff255    	bl	0x10006eb54 <_$s8SwiftJLI9BitReaderV8readBitsys6UInt32VSiKF>
100072204: aa1503f3    	mov	x19, x21
100072208: b5000475    	cbnz	x21, 0x100072294 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x300>
10007220c: 51000708    	sub	w8, w24, #0x1
100072210: 1ac82408    	lsr	w8, w0, w8
100072214: 340000a8    	cbz	w8, 0x100072228 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x294>
100072218: 36f80100    	tbz	w0, #0x1f, 0x100072238 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2a4>
10007221c: 1400002a    	b	0x1000722c4 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x330>
100072220: 52800000    	mov	w0, #0x0                ; =0
100072224: 14000005    	b	0x100072238 <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x2a4>
100072228: 12800008    	mov	w8, #-0x1               ; =-1
10007222c: 1ad82108    	lsl	w8, w8, w24
100072230: 0b080008    	add	w8, w0, w8
100072234: 11000500    	add	w0, w8, #0x1
100072238: b83c7ac0    	str	w0, [x22, x28, lsl #2]
10007223c: 91000798    	add	x24, x28, #0x1
100072240: 17ffff7b    	b	0x10007202c <_$s8SwiftJLI14HuffmanDecoderO8decodeAC4from5table6lookup4intoyAA9BitReaderVz_AA0C5TableVAA11ACLookaheadVSrys5Int32VGtKFZTf4nnnnd_n+0x98>
100072244: b0000108    	adrp	x8, 0x100093000 <_vImageConvert_RGB888toPlanar8+0x100093000>
100072248: 910ec108    	add	x8, x8, #0x3b0
10007224c: d1008108    	sub	x8, x8, #0x20
100072250: d28003b8    	mov	x24, #0x1d              ; =29
100072254: f2fa0018    	movk	x24, #0xd000, lsl #48
100072258: b2410114    	orr	x20, x8, #0x8000000000000000
10007225c: 97fe9b85    	bl	0x100019070 <_$s8SwiftJLI8JLIErrorOACs5ErrorAAWl>
100072260: aa0003e1    	mov	x1, x0
100072264: b0000180    	adrp	x0, 0x1000a3000 <_$s8SwiftJLI14SRGBICCProfileO4data_WZTv_r+0x758>
100072268: 91264000    	add	x0, x0, #0x990
10007226c: d2800002    	mov	x2, #0x0                ; =0
100072270: 52800003    	mov	w3, #0x0                ; =0
100072274: 94006c09    	bl	0x10008d298 <_vImageConvert_RGB888toPlanar8+0x10008d298>
100072278: aa0003f3    	mov	x19, x0
10007227c: a9005038    	stp	x24, x20, [x1]
100072280: a9017c3f    	stp	xzr, xzr, [x1, #0x10]
100072284: 528000c8    	mov	w8, #0x6                ; =6
100072288: 39008028    	strb	w8, [x1, #0x20]
10007228c: aa0003f5    	mov	x21, x0
100072290: 94006c8f    	bl	0x10008d4cc <_vImageConvert_RGB888toPlanar8+0x10008d4cc>
100072294: aa1303f5    	mov	x21, x19
100072298: a9457bfd    	ldp	x29, x30, [sp, #0x50]
10007229c: a9444ff4    	ldp	x20, x19, [sp, #0x40]
1000722a0: a9435bf7    	ldp	x23, x22, [sp, #0x30]
1000722a4: a94263f9    	ldp	x25, x24, [sp, #0x20]
1000722a8: a9416bfb    	ldp	x27, x26, [sp, #0x10]
1000722ac: f84607fc    	ldr	x28, [sp], #0x60
1000722b0: d65f03c0    	ret
1000722b4: d4200020    	brk	#0x1
1000722b8: d4200020    	brk	#0x1
1000722bc: d4200020    	brk	#0x1
1000722c0: d4200020    	brk	#0x1
1000722c4: d4200020    	brk	#0x1
1000722c8: d4200020    	brk	#0x1
1000722cc: d4200020    	brk	#0x1
1000722d0: d4200020    	brk	#0x1
1000722d4: d4200020    	brk	#0x1
