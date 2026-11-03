
/private/tmp/swiftjli-round5-vector-compaction-revised-build/out/Products/Release/SwiftJLI.o:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000000000501d4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n>:
   501d4: d10283ff     	sub	sp, sp, #0xa0
   501d8: fd001bea     	str	d10, [sp, #0x30]
   501dc: 6d03a3e9     	stp	d9, d8, [sp, #0x38]
   501e0: f90027fc     	str	x28, [sp, #0x48]
   501e4: a9056bfb     	stp	x27, x26, [sp, #0x50]
   501e8: a90663f9     	stp	x25, x24, [sp, #0x60]
   501ec: a9075bf7     	stp	x23, x22, [sp, #0x70]
   501f0: a9084ff4     	stp	x20, x19, [sp, #0x80]
   501f4: a9097bfd     	stp	x29, x30, [sp, #0x90]
   501f8: 910243fd     	add	x29, sp, #0x90
   501fc: b27e0048     	orr	x8, x2, #0x4
   50200: f100311f     	cmp	x8, #0xc
   50204: 54000621     	b.ne	0x502c8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xf4>
   50208: aa0403f3     	mov	x19, x4
   5020c: aa0303f4     	mov	x20, x3
   50210: aa0103f6     	mov	x22, x1
   50214: aa0003f7     	mov	x23, x0
   50218: 36000204     	tbz	w4, #0x0, 0x50258 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x84>
   5021c: 52800088     	mov	w8, #0x4                ; =4
   50220: eb08029f     	cmp	x20, x8
   50224: 54000521     	b.ne	0x502c8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xf4>
   50228: b4000517     	cbz	x23, 0x502c8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xf4>
   5022c: d2fc0008     	mov	x8, #-0x2000000000000000 ; =-2305843009213693952
   50230: 8b0802c8     	add	x8, x22, x8
   50234: d37efd08     	lsr	x8, x8, #62
   50238: f1000d1f     	cmp	x8, #0x3
   5023c: 54000243     	b.lo	0x50284 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xb0>
   50240: 92800008     	mov	x8, #-0x1               ; =-1
   50244: 9ac22108     	lsl	x8, x8, x2
   50248: aa2803e8     	mvn	x8, x8
   5024c: 9e230104     	ucvtf	s4, x8
   50250: 36000833     	tbz	w19, #0x0, 0x50354 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x180>
   50254: 14000138     	b	0x50734 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x560>
   50258: 52800048     	mov	w8, #0x2                ; =2
   5025c: f100205f     	cmp	x2, #0x8
   50260: 54fffe08     	b.hi	0x50220 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x4c>
   50264: f100069f     	cmp	x20, #0x1
   50268: 54fffdc1     	b.ne	0x50220 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x4c>
   5026c: b40002f7     	cbz	x23, 0x502c8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xf4>
   50270: d2fc0008     	mov	x8, #-0x2000000000000000 ; =-2305843009213693952
   50274: 8b0802c8     	add	x8, x22, x8
   50278: d37efd08     	lsr	x8, x8, #62
   5027c: f1000d1f     	cmp	x8, #0x3
   50280: 54000622     	b.hs	0x50344 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x170>
   50284: 90000008     	adrp	x8, 0x50000 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO19encodeConstantTiles33_FB27BC3D9A005ABB795EC9F3C1379AF8LL_4into9precision14bytesPerSample11floatOutputySRySfG_SwS2iSbtKFZTf4nnnnnd_nTf4nxnnn_n+0x78>
		0000000000050284:  ARM64_RELOC_PAGE21	LC27
   50288: 91000108     	add	x8, x8, #0x0
		0000000000050288:  ARM64_RELOC_PAGEOFF12	LC27
   5028c: d1008108     	sub	x8, x8, #0x20
   50290: b2410113     	orr	x19, x8, #0x8000000000000000
   50294: 94000000     	bl	0x50294 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xc0>
		0000000000050294:  ARM64_RELOC_BRANCH26	_$s8SwiftJLI10CodecErrorVACs0D0AAWl
   50298: aa0003e1     	mov	x1, x0
   5029c: 90000000     	adrp	x0, 0x50000 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO19encodeConstantTiles33_FB27BC3D9A005ABB795EC9F3C1379AF8LL_4into9precision14bytesPerSample11floatOutputySRySfG_SwS2iSbtKFZTf4nnnnnd_nTf4nxnnn_n+0x78>
		000000000005029c:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s8SwiftJLI10CodecErrorVN
   502a0: f9400000     	ldr	x0, [x0]
		00000000000502a0:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s8SwiftJLI10CodecErrorVN
   502a4: d2800002     	mov	x2, #0x0                ; =0
   502a8: 52800003     	mov	w3, #0x0                ; =0
   502ac: 94000000     	bl	0x502ac <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xd8>
		00000000000502ac:  ARM64_RELOC_BRANCH26	_swift_allocError
   502b0: 3900003f     	strb	wzr, [x1]
   502b4: d28003e8     	mov	x8, #0x1f               ; =31
   502b8: f2fa0008     	movk	x8, #0xd000, lsl #48
   502bc: d1001508     	sub	x8, x8, #0x5
   502c0: a900cc28     	stp	x8, x19, [x1, #0x8]
   502c4: 14000012     	b	0x5030c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x138>
   502c8: 90000008     	adrp	x8, 0x50000 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO19encodeConstantTiles33_FB27BC3D9A005ABB795EC9F3C1379AF8LL_4into9precision14bytesPerSample11floatOutputySRySfG_SwS2iSbtKFZTf4nnnnnd_nTf4nxnnn_n+0x78>
		00000000000502c8:  ARM64_RELOC_PAGE21	LC247
   502cc: 91000108     	add	x8, x8, #0x0
		00000000000502cc:  ARM64_RELOC_PAGEOFF12	LC247
   502d0: d1008108     	sub	x8, x8, #0x20
   502d4: b2410113     	orr	x19, x8, #0x8000000000000000
   502d8: 94000000     	bl	0x502d8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x104>
		00000000000502d8:  ARM64_RELOC_BRANCH26	_$s8SwiftJLI8JLIErrorOACs5ErrorAAWl
   502dc: aa0003e1     	mov	x1, x0
   502e0: 90000000     	adrp	x0, 0x50000 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO19encodeConstantTiles33_FB27BC3D9A005ABB795EC9F3C1379AF8LL_4into9precision14bytesPerSample11floatOutputySRySfG_SwS2iSbtKFZTf4nnnnnd_nTf4nxnnn_n+0x78>
		00000000000502e0:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s8SwiftJLI8JLIErrorON
   502e4: f9400000     	ldr	x0, [x0]
		00000000000502e4:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s8SwiftJLI8JLIErrorON
   502e8: d2800002     	mov	x2, #0x0                ; =0
   502ec: 52800003     	mov	w3, #0x0                ; =0
   502f0: 94000000     	bl	0x502f0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x11c>
		00000000000502f0:  ARM64_RELOC_BRANCH26	_swift_allocError
   502f4: d28003e8     	mov	x8, #0x1f               ; =31
   502f8: f2fa0008     	movk	x8, #0xd000, lsl #48
   502fc: a9004c28     	stp	x8, x19, [x1]
   50300: a9017c3f     	stp	xzr, xzr, [x1, #0x10]
   50304: 528000c8     	mov	w8, #0x6                ; =6
   50308: 39008028     	strb	w8, [x1, #0x20]
   5030c: aa0003f3     	mov	x19, x0
   50310: aa0003f5     	mov	x21, x0
   50314: 94000000     	bl	0x50314 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x140>
		0000000000050314:  ARM64_RELOC_BRANCH26	_swift_willThrow
   50318: aa1303f5     	mov	x21, x19
   5031c: a9497bfd     	ldp	x29, x30, [sp, #0x90]
   50320: a9484ff4     	ldp	x20, x19, [sp, #0x80]
   50324: a9475bf7     	ldp	x23, x22, [sp, #0x70]
   50328: a94663f9     	ldp	x25, x24, [sp, #0x60]
   5032c: a9456bfb     	ldp	x27, x26, [sp, #0x50]
   50330: f94027fc     	ldr	x28, [sp, #0x48]
   50334: 6d43a3e9     	ldp	d9, d8, [sp, #0x38]
   50338: fd401bea     	ldr	d10, [sp, #0x30]
   5033c: 910283ff     	add	sp, sp, #0xa0
   50340: d65f03c0     	ret
   50344: 92800008     	mov	x8, #-0x1               ; =-1
   50348: 9ac22108     	lsl	x8, x8, x2
   5034c: aa2803e8     	mvn	x8, x8
   50350: 9e230104     	ucvtf	s4, x8
   50354: eb1603e8     	negs	x8, x22
   50358: 92400508     	and	x8, x8, #0x3
   5035c: 924006c9     	and	x9, x22, #0x3
   50360: da884528     	csneg	x8, x9, x8, mi
   50364: cb0802d0     	sub	x16, x22, x8
   50368: f100061f     	cmp	x16, #0x1
   5036c: 54001e4b     	b.lt	0x50734 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x560>
   50370: d2800019     	mov	x25, #0x0               ; =0
   50374: d280001a     	mov	x26, #0x0               ; =0
   50378: d280001b     	mov	x27, #0x0               ; =0
   5037c: 4e040481     	dup.4s	v1, v4[0]
   50380: d2800031     	mov	x17, #0x1               ; =1
   50384: f2e80011     	movk	x17, #0x4000, lsl #48
   50388: 6f03d7e0     	mvni.4s	v0, #0x7f, msl #16
   5038c: 6ea0f805     	fneg.4s	v5, v0
   50390: 6f00e408     	movi.2d	v8, #0000000000000000
   50394: 12b0101c     	mov	w28, #0x7f7fffff        ; =2139095039
   50398: 1e3e1009     	fmov	s9, #-1.00000000
   5039c: 52a8f008     	mov	w8, #0x47800000         ; =1199570944
   503a0: 1e27010a     	fmov	s10, w8
   503a4: 3d800be4     	str	q4, [sp, #0x20]
   503a8: ad0017e1     	stp	q1, q5, [sp]
   503ac: f2402f7f     	tst	x27, #0xfff
   503b0: 54000101     	b.ne	0x503d0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x1fc>
   503b4: aa1003f8     	mov	x24, x16
   503b8: 94000000     	bl	0x503b8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x1e4>
		00000000000503b8:  ARM64_RELOC_BRANCH26	_$s8SwiftJLI15NativeOperationV5checkyyKFZTf4d_n
   503bc: ad4093e5     	ldp	q5, q4, [sp, #0x10]
   503c0: d2800031     	mov	x17, #0x1               ; =1
   503c4: f2e80011     	movk	x17, #0x4000, lsl #48
   503c8: aa1803f0     	mov	x16, x24
   503cc: b5fffa95     	cbnz	x21, 0x5031c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x148>
   503d0: 3cfa6ae0     	ldr	q0, [x23, x26]
   503d4: 4ea01c01     	mov.16b	v1, v0
   503d8: 6f047401     	bic.4s	v1, #0x80, lsl #24
   503dc: 4ea53c21     	cmge.4s	v1, v1, v5
   503e0: 0e612821     	xtn.4h	v1, v1
   503e4: 2e70a821     	umaxv.4h	h1, v1
   503e8: 1e260028     	fmov	w8, s1
   503ec: 36000e68     	tbz	w8, #0x0, 0x505b8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x3e4>
   503f0: 1e260008     	fmov	w8, s0
   503f4: 12007908     	and	w8, w8, #0x7fffffff
   503f8: 6b1c011f     	cmp	w8, w28
   503fc: 5400208c     	b.gt	0x5080c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x638>
   50400: 1e242000     	fcmp	s0, s4
   50404: 1e244c01     	fcsel	s1, s0, s4, mi
   50408: 1e202028     	fcmp	s1, #0.0
   5040c: 1e28ac21     	fcsel	s1, s1, s8, ge
   50410: 1e264021     	frinta	s1, s1
   50414: 1e292020     	fcmp	s1, s9
   50418: 5400200d     	b.le	0x50818 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x644>
   5041c: 1e2a2020     	fcmp	s1, s10
   50420: 54001fe5     	b.pl	0x5081c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x648>
   50424: 9b147f69     	mul	x9, x27, x20
   50428: 9b547f68     	smulh	x8, x27, x20
   5042c: eb89fd1f     	cmp	x8, x9, asr #63
   50430: 54001f81     	b.ne	0x50820 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x64c>
   50434: 1e380028     	fcvtzs	w8, s1
   50438: 38296ae8     	strb	w8, [x23, x9]
   5043c: f1000a9f     	cmp	x20, #0x2
   50440: 540000e1     	b.ne	0x5045c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x288>
   50444: 8b110369     	add	x9, x27, x17
   50448: f100053f     	cmp	x9, #0x1
   5044c: 54001ee4     	b.mi	0x50828 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x654>
   50450: 53087d08     	lsr	w8, w8, #8
   50454: 8b1902e9     	add	x9, x23, x25
   50458: 39000528     	strb	w8, [x9, #0x1]
   5045c: 5e0c0401     	mov	s1, v0[1]
   50460: 1e260028     	fmov	w8, s1
   50464: 12007908     	and	w8, w8, #0x7fffffff
   50468: 6b1c011f     	cmp	w8, w28
   5046c: 54001d0c     	b.gt	0x5080c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x638>
   50470: 1e242020     	fcmp	s1, s4
   50474: 1e244c21     	fcsel	s1, s1, s4, mi
   50478: 1e202028     	fcmp	s1, #0.0
   5047c: 1e28ac21     	fcsel	s1, s1, s8, ge
   50480: 1e264021     	frinta	s1, s1
   50484: 1e292020     	fcmp	s1, s9
   50488: 54001c8d     	b.le	0x50818 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x644>
   5048c: 1e2a2020     	fcmp	s1, s10
   50490: 54001c65     	b.pl	0x5081c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x648>
   50494: 91000768     	add	x8, x27, #0x1
   50498: 9b147d09     	mul	x9, x8, x20
   5049c: 9b547d08     	smulh	x8, x8, x20
   504a0: eb89fd1f     	cmp	x8, x9, asr #63
   504a4: 54001be1     	b.ne	0x50820 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x64c>
   504a8: 1e380028     	fcvtzs	w8, s1
   504ac: 38296ae8     	strb	w8, [x23, x9]
   504b0: f1000a9f     	cmp	x20, #0x2
   504b4: 540000c1     	b.ne	0x504cc <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x2f8>
   504b8: ab11037f     	cmn	x27, x17
   504bc: 54001b64     	b.mi	0x50828 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x654>
   504c0: 53087d08     	lsr	w8, w8, #8
   504c4: 8b1902e9     	add	x9, x23, x25
   504c8: 39000d28     	strb	w8, [x9, #0x3]
   504cc: 5e140401     	mov	s1, v0[2]
   504d0: 1e260028     	fmov	w8, s1
   504d4: 12007908     	and	w8, w8, #0x7fffffff
   504d8: 6b1c011f     	cmp	w8, w28
   504dc: 5400198c     	b.gt	0x5080c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x638>
   504e0: 1e242020     	fcmp	s1, s4
   504e4: 1e244c21     	fcsel	s1, s1, s4, mi
   504e8: 1e202028     	fcmp	s1, #0.0
   504ec: 1e28ac21     	fcsel	s1, s1, s8, ge
   504f0: 1e264021     	frinta	s1, s1
   504f4: 1e292020     	fcmp	s1, s9
   504f8: 5400190d     	b.le	0x50818 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x644>
   504fc: 1e2a2020     	fcmp	s1, s10
   50500: 540018e5     	b.pl	0x5081c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x648>
   50504: 91000b68     	add	x8, x27, #0x2
   50508: 9b147d09     	mul	x9, x8, x20
   5050c: 9b547d08     	smulh	x8, x8, x20
   50510: eb89fd1f     	cmp	x8, x9, asr #63
   50514: 54001861     	b.ne	0x50820 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x64c>
   50518: 1e380028     	fcvtzs	w8, s1
   5051c: 38296ae8     	strb	w8, [x23, x9]
   50520: f1000a9f     	cmp	x20, #0x2
   50524: 540000e1     	b.ne	0x50540 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x36c>
   50528: 8b110369     	add	x9, x27, x17
   5052c: b100053f     	cmn	x9, #0x1
   50530: 540017c4     	b.mi	0x50828 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x654>
   50534: 53087d08     	lsr	w8, w8, #8
   50538: 8b1902e9     	add	x9, x23, x25
   5053c: 39001528     	strb	w8, [x9, #0x5]
   50540: 5e1c0400     	mov	s0, v0[3]
   50544: 1e260008     	fmov	w8, s0
   50548: 12007908     	and	w8, w8, #0x7fffffff
   5054c: 6b1c011f     	cmp	w8, w28
   50550: 540015ec     	b.gt	0x5080c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x638>
   50554: 1e242000     	fcmp	s0, s4
   50558: 1e244c00     	fcsel	s0, s0, s4, mi
   5055c: 1e202008     	fcmp	s0, #0.0
   50560: 1e28ac00     	fcsel	s0, s0, s8, ge
   50564: 1e264000     	frinta	s0, s0
   50568: 1e292000     	fcmp	s0, s9
   5056c: 5400156d     	b.le	0x50818 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x644>
   50570: 1e2a2000     	fcmp	s0, s10
   50574: 54001545     	b.pl	0x5081c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x648>
   50578: 91000f68     	add	x8, x27, #0x3
   5057c: 9b147d09     	mul	x9, x8, x20
   50580: 9b547d08     	smulh	x8, x8, x20
   50584: eb89fd1f     	cmp	x8, x9, asr #63
   50588: 540014c1     	b.ne	0x50820 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x64c>
   5058c: 1e380008     	fcvtzs	w8, s0
   50590: 38296ae8     	strb	w8, [x23, x9]
   50594: f1000a9f     	cmp	x20, #0x2
   50598: 54000be1     	b.ne	0x50714 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x540>
   5059c: 8b110369     	add	x9, x27, x17
   505a0: b100093f     	cmn	x9, #0x2
   505a4: 54001424     	b.mi	0x50828 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x654>
   505a8: 53087d08     	lsr	w8, w8, #8
   505ac: 8b1902e9     	add	x9, x23, x25
   505b0: 39001d28     	strb	w8, [x9, #0x7]
   505b4: 14000058     	b	0x50714 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x540>
   505b8: 4ea0e801     	fcmlt.4s	v1, v0, #0.0
   505bc: 0e0c3c28     	mov.s	w8, v1[1]
   505c0: 0e143c29     	mov.s	w9, v1[2]
   505c4: 0e1c3c2a     	mov.s	w10, v1[3]
   505c8: 3dc003e2     	ldr	q2, [sp]
   505cc: 6ea2e402     	fcmgt.4s	v2, v0, v2
   505d0: 0e0c3c4b     	mov.s	w11, v2[1]
   505d4: 0e143c4c     	mov.s	w12, v2[2]
   505d8: 1e26002d     	fmov	w13, s1
   505dc: 0e1c3c4e     	mov.s	w14, v2[3]
   505e0: 1e26004f     	fmov	w15, s2
   505e4: 1e264001     	frinta	s1, s0
   505e8: 710001bf     	cmp	w13, #0x0
   505ec: 1e21bd01     	fcsel	s1, s8, s1, lt
   505f0: 710001ff     	cmp	w15, #0x0
   505f4: 1e21bc81     	fcsel	s1, s4, s1, lt
   505f8: 1e26002d     	fmov	w13, s1
   505fc: 5e0c0402     	mov	s2, v0[1]
   50600: 1e264042     	frinta	s2, s2
   50604: 7100011f     	cmp	w8, #0x0
   50608: 1e22bd02     	fcsel	s2, s8, s2, lt
   5060c: 7100017f     	cmp	w11, #0x0
   50610: 1e22bc82     	fcsel	s2, s4, s2, lt
   50614: 5e140403     	mov	s3, v0[2]
   50618: 1e264063     	frinta	s3, s3
   5061c: 7100013f     	cmp	w9, #0x0
   50620: 1e23bd03     	fcsel	s3, s8, s3, lt
   50624: 7100019f     	cmp	w12, #0x0
   50628: 1e23bc83     	fcsel	s3, s4, s3, lt
   5062c: 5e1c0400     	mov	s0, v0[3]
   50630: 1e264000     	frinta	s0, s0
   50634: 7100015f     	cmp	w10, #0x0
   50638: 1e20bd00     	fcsel	s0, s8, s0, lt
   5063c: 710001df     	cmp	w14, #0x0
   50640: 1e20bc80     	fcsel	s0, s4, s0, lt
   50644: 120079a8     	and	w8, w13, #0x7fffffff
   50648: 6b1c011f     	cmp	w8, w28
   5064c: 54000f8c     	b.gt	0x5083c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x668>
   50650: 1e292020     	fcmp	s1, s9
   50654: 54000f6d     	b.le	0x50840 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x66c>
   50658: 1e2a2020     	fcmp	s1, s10
   5065c: 54000f45     	b.pl	0x50844 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x670>
   50660: 1e260048     	fmov	w8, s2
   50664: 12007908     	and	w8, w8, #0x7fffffff
   50668: 6b1c011f     	cmp	w8, w28
   5066c: 54000eec     	b.gt	0x50848 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x674>
   50670: 1e292040     	fcmp	s2, s9
   50674: 54000ecd     	b.le	0x5084c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x678>
   50678: 1e2a2040     	fcmp	s2, s10
   5067c: 54000ea5     	b.pl	0x50850 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x67c>
   50680: 1e260068     	fmov	w8, s3
   50684: 12007908     	and	w8, w8, #0x7fffffff
   50688: 6b1c011f     	cmp	w8, w28
   5068c: 54000e4c     	b.gt	0x50854 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x680>
   50690: 1e292060     	fcmp	s3, s9
   50694: 54000e2d     	b.le	0x50858 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x684>
   50698: 1e2a2060     	fcmp	s3, s10
   5069c: 54000e05     	b.pl	0x5085c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x688>
   506a0: 1e260008     	fmov	w8, s0
   506a4: 12007908     	and	w8, w8, #0x7fffffff
   506a8: 6b1c011f     	cmp	w8, w28
   506ac: 54000dac     	b.gt	0x50860 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x68c>
   506b0: 1e292000     	fcmp	s0, s9
   506b4: 54000d8d     	b.le	0x50864 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x690>
   506b8: 1e2a2000     	fcmp	s0, s10
   506bc: 54000d65     	b.pl	0x50868 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x694>
   506c0: 1e38002b     	fcvtzs	w11, s1
   506c4: 1e38004a     	fcvtzs	w10, s2
   506c8: 1e380069     	fcvtzs	w9, s3
   506cc: 1e380008     	fcvtzs	w8, s0
   506d0: f100069f     	cmp	x20, #0x1
   506d4: 54000101     	b.ne	0x506f4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x520>
   506d8: 1e270160     	fmov	s0, w11
   506dc: 4e061d40     	mov.h	v0[1], w10
   506e0: 4e0a1d20     	mov.h	v0[2], w9
   506e4: 4e0e1d00     	mov.h	v0[3], w8
   506e8: 0e212800     	xtn.8b	v0, v0
   506ec: bc3b6ae0     	str	s0, [x23, x27]
   506f0: 14000009     	b	0x50714 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x540>
   506f4: 8b11036c     	add	x12, x27, x17
   506f8: f100059f     	cmp	x12, #0x1
   506fc: 54000bc4     	b.mi	0x50874 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x6a0>
   50700: 1e270160     	fmov	s0, w11
   50704: 4e061d40     	mov.h	v0[1], w10
   50708: 4e0a1d20     	mov.h	v0[2], w9
   5070c: 4e0e1d00     	mov.h	v0[3], w8
   50710: fc396ae0     	str	d0, [x23, x25]
   50714: b1001378     	adds	x24, x27, #0x4
   50718: 540008a6     	b.vs	0x5082c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x658>
   5071c: 9100137b     	add	x27, x27, #0x4
   50720: 9100435a     	add	x26, x26, #0x10
   50724: 91002339     	add	x25, x25, #0x8
   50728: eb10031f     	cmp	x24, x16
   5072c: 54ffe40b     	b.lt	0x503ac <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x1d8>
   50730: 14000002     	b	0x50738 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x564>
   50734: d2800018     	mov	x24, #0x0               ; =0
   50738: eb1802d9     	subs	x25, x22, x24
   5073c: 540009ab     	b.lt	0x50870 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x69c>
   50740: 54ffdee0     	b.eq	0x5031c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x148>
   50744: d2e80008     	mov	x8, #0x4000000000000000 ; =4611686018427387904
   50748: 8b08031a     	add	x26, x24, x8
   5074c: 52800028     	mov	w8, #0x1                ; =1
   50750: aa18051b     	orr	x27, x8, x24, lsl #1
   50754: 12b0101c     	mov	w28, #0x7f7fffff        ; =2139095039
   50758: 6f00e408     	movi.2d	v8, #0000000000000000
   5075c: 1e3e1009     	fmov	s9, #-1.00000000
   50760: 52a8f008     	mov	w8, #0x47800000         ; =1199570944
   50764: 1e27010a     	fmov	s10, w8
   50768: 3d800be4     	str	q4, [sp, #0x20]
   5076c: 14000006     	b	0x50784 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5b0>
   50770: 9100075a     	add	x26, x26, #0x1
   50774: 91000b7b     	add	x27, x27, #0x2
   50778: 91000718     	add	x24, x24, #0x1
   5077c: f1000739     	subs	x25, x25, #0x1
   50780: 54ffdce0     	b.eq	0x5031c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x148>
   50784: eb16031f     	cmp	x24, x22
   50788: 540004ea     	b.ge	0x50824 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x650>
   5078c: f2402f1f     	tst	x24, #0xfff
   50790: 54000081     	b.ne	0x507a0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5cc>
   50794: 94000000     	bl	0x50794 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5c0>
		0000000000050794:  ARM64_RELOC_BRANCH26	_$s8SwiftJLI15NativeOperationV5checkyyKFZTf4d_n
   50798: 3dc00be4     	ldr	q4, [sp, #0x20]
   5079c: b5ffdc15     	cbnz	x21, 0x5031c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x148>
   507a0: bc787ae0     	ldr	s0, [x23, x24, lsl #2]
   507a4: 1e260008     	fmov	w8, s0
   507a8: 12007908     	and	w8, w8, #0x7fffffff
   507ac: 6b1c011f     	cmp	w8, w28
   507b0: 540002ec     	b.gt	0x5080c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x638>
   507b4: 3707fdf3     	tbnz	w19, #0x0, 0x50770 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x59c>
   507b8: 1e242000     	fcmp	s0, s4
   507bc: 1e244c00     	fcsel	s0, s0, s4, mi
   507c0: 1e202008     	fcmp	s0, #0.0
   507c4: 1e28ac00     	fcsel	s0, s0, s8, ge
   507c8: 1e264000     	frinta	s0, s0
   507cc: 1e292000     	fcmp	s0, s9
   507d0: 5400030d     	b.le	0x50830 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x65c>
   507d4: 1e2a2000     	fcmp	s0, s10
   507d8: 540002e5     	b.pl	0x50834 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x660>
   507dc: 9b147f09     	mul	x9, x24, x20
   507e0: 9b547f08     	smulh	x8, x24, x20
   507e4: eb89fd1f     	cmp	x8, x9, asr #63
   507e8: 54000281     	b.ne	0x50838 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x664>
   507ec: 1e380008     	fcvtzs	w8, s0
   507f0: 38296ae8     	strb	w8, [x23, x9]
   507f4: f1000a9f     	cmp	x20, #0x2
   507f8: 54fffbc1     	b.ne	0x50770 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x59c>
   507fc: b7f8039a     	tbnz	x26, #0x3f, 0x5086c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x698>
   50800: 53087d08     	lsr	w8, w8, #8
   50804: 383b6ae8     	strb	w8, [x23, x27]
   50808: 17ffffda     	b	0x50770 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x59c>
   5080c: 90000008     	adrp	x8, 0x50000 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO19encodeConstantTiles33_FB27BC3D9A005ABB795EC9F3C1379AF8LL_4into9precision14bytesPerSample11floatOutputySRySfG_SwS2iSbtKFZTf4nnnnnd_nTf4nxnnn_n+0x78>
		000000000005080c:  ARM64_RELOC_PAGE21	LC174
   50810: 91000108     	add	x8, x8, #0x0
		0000000000050810:  ARM64_RELOC_PAGEOFF12	LC174
   50814: 17fffeaf     	b	0x502d0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xfc>
   50818: d4200020     	brk	#0x1
   5081c: d4200020     	brk	#0x1
   50820: d4200020     	brk	#0x1
   50824: d4200020     	brk	#0x1
   50828: d4200020     	brk	#0x1
   5082c: d4200020     	brk	#0x1
   50830: d4200020     	brk	#0x1
   50834: d4200020     	brk	#0x1
   50838: d4200020     	brk	#0x1
   5083c: d4200020     	brk	#0x1
   50840: d4200020     	brk	#0x1
   50844: d4200020     	brk	#0x1
   50848: d4200020     	brk	#0x1
   5084c: d4200020     	brk	#0x1
   50850: d4200020     	brk	#0x1
   50854: d4200020     	brk	#0x1
   50858: d4200020     	brk	#0x1
   5085c: d4200020     	brk	#0x1
   50860: d4200020     	brk	#0x1
   50864: d4200020     	brk	#0x1
   50868: d4200020     	brk	#0x1
   5086c: d4200020     	brk	#0x1
   50870: d4200020     	brk	#0x1
   50874: d4200020     	brk	#0x1
