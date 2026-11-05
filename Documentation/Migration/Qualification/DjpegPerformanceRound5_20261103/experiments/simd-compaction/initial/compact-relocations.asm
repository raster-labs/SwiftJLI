
/private/tmp/swiftjli-round5-vector-compaction-build/out/Products/Release/SwiftJLI.o:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000000000509c8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n>:
   509c8: fc190fea     	str	d10, [sp, #-0x70]!
   509cc: 6d00a3e9     	stp	d9, d8, [sp, #0x8]
   509d0: f9000ffc     	str	x28, [sp, #0x18]
   509d4: a9026bfb     	stp	x27, x26, [sp, #0x20]
   509d8: a90363f9     	stp	x25, x24, [sp, #0x30]
   509dc: a9045bf7     	stp	x23, x22, [sp, #0x40]
   509e0: a9054ff4     	stp	x20, x19, [sp, #0x50]
   509e4: a9067bfd     	stp	x29, x30, [sp, #0x60]
   509e8: 910183fd     	add	x29, sp, #0x60
   509ec: d101c3ff     	sub	sp, sp, #0x70
   509f0: aa1503f3     	mov	x19, x21
   509f4: aa0403f7     	mov	x23, x4
   509f8: aa0303f6     	mov	x22, x3
   509fc: aa0203fb     	mov	x27, x2
   50a00: aa0103f4     	mov	x20, x1
   50a04: aa0003f8     	mov	x24, x0
   50a08: d2800000     	mov	x0, #0x0                ; =0
   50a0c: 94000000     	bl	0x50a0c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x44>
		0000000000050a0c:  ARM64_RELOC_BRANCH26	_$ss25FloatingPointRoundingRuleOMa
   50a10: aa0003f9     	mov	x25, x0
   50a14: f85f8008     	ldur	x8, [x0, #-0x8]
   50a18: f81983a8     	stur	x8, [x29, #-0x68]
   50a1c: f9402108     	ldr	x8, [x8, #0x40]
   50a20: aa0803e9     	mov	x9, x8
   50a24: 90000010     	adrp	x16, 0x50000 <_$ss5SIMD4Vss17FixedWidthIntegerRzrlE_8roundingAByxGAByqd__G_s25FloatingPointRoundingRuleOtcSBRd__s10SIMDScalarRd__lufCs6UInt16V_SfTt2g5+0x100>
		0000000000050a24:  ARM64_RELOC_GOT_LOAD_PAGE21	___chkstk_darwin
   50a28: f9400210     	ldr	x16, [x16]
		0000000000050a28:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	___chkstk_darwin
   50a2c: d63f0200     	blr	x16
   50a30: 910003e9     	mov	x9, sp
   50a34: 91003d08     	add	x8, x8, #0xf
   50a38: 927ced08     	and	x8, x8, #0xfffffffffffffff0
   50a3c: cb08013a     	sub	x26, x9, x8
   50a40: 9100035f     	mov	sp, x26
   50a44: b27e0368     	orr	x8, x27, #0x4
   50a48: f100311f     	cmp	x8, #0xc
   50a4c: 540005c1     	b.ne	0x50b04 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x13c>
   50a50: 36000217     	tbz	w23, #0x0, 0x50a90 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xc8>
   50a54: 52800088     	mov	w8, #0x4                ; =4
   50a58: eb0802df     	cmp	x22, x8
   50a5c: 54000541     	b.ne	0x50b04 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x13c>
   50a60: b4000538     	cbz	x24, 0x50b04 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x13c>
   50a64: d2fc0008     	mov	x8, #-0x2000000000000000 ; =-2305843009213693952
   50a68: 8b080288     	add	x8, x20, x8
   50a6c: d37efd08     	lsr	x8, x8, #62
   50a70: f1000d1f     	cmp	x8, #0x3
   50a74: 54000243     	b.lo	0x50abc <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0xf4>
   50a78: 92800008     	mov	x8, #-0x1               ; =-1
   50a7c: 9adb2108     	lsl	x8, x8, x27
   50a80: aa2803e8     	mvn	x8, x8
   50a84: 9e230102     	ucvtf	s2, x8
   50a88: 36000857     	tbz	w23, #0x0, 0x50b90 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x1c8>
   50a8c: 1400010f     	b	0x50ec8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x500>
   50a90: 52800048     	mov	w8, #0x2                ; =2
   50a94: f10006df     	cmp	x22, #0x1
   50a98: 54fffe01     	b.ne	0x50a58 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x90>
   50a9c: f100277f     	cmp	x27, #0x9
   50aa0: 54fffdc2     	b.hs	0x50a58 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x90>
   50aa4: b4000318     	cbz	x24, 0x50b04 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x13c>
   50aa8: d2fc0008     	mov	x8, #-0x2000000000000000 ; =-2305843009213693952
   50aac: 8b080288     	add	x8, x20, x8
   50ab0: d37efd08     	lsr	x8, x8, #62
   50ab4: f1000d1f     	cmp	x8, #0x3
   50ab8: 54000642     	b.hs	0x50b80 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x1b8>
   50abc: 90000008     	adrp	x8, 0x50000 <_$ss5SIMD4Vss17FixedWidthIntegerRzrlE_8roundingAByxGAByqd__G_s25FloatingPointRoundingRuleOtcSBRd__s10SIMDScalarRd__lufCs6UInt16V_SfTt2g5+0x100>
		0000000000050abc:  ARM64_RELOC_PAGE21	LC27
   50ac0: 91000108     	add	x8, x8, #0x0
		0000000000050ac0:  ARM64_RELOC_PAGEOFF12	LC27
   50ac4: d1008108     	sub	x8, x8, #0x20
   50ac8: b2410114     	orr	x20, x8, #0x8000000000000000
   50acc: 94000000     	bl	0x50acc <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x104>
		0000000000050acc:  ARM64_RELOC_BRANCH26	_$s8SwiftJLI10CodecErrorVACs0D0AAWl
   50ad0: aa0003e1     	mov	x1, x0
   50ad4: 90000000     	adrp	x0, 0x50000 <_$ss5SIMD4Vss17FixedWidthIntegerRzrlE_8roundingAByxGAByqd__G_s25FloatingPointRoundingRuleOtcSBRd__s10SIMDScalarRd__lufCs6UInt16V_SfTt2g5+0x100>
		0000000000050ad4:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s8SwiftJLI10CodecErrorVN
   50ad8: f9400000     	ldr	x0, [x0]
		0000000000050ad8:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s8SwiftJLI10CodecErrorVN
   50adc: d2800002     	mov	x2, #0x0                ; =0
   50ae0: 52800003     	mov	w3, #0x0                ; =0
   50ae4: 94000000     	bl	0x50ae4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x11c>
		0000000000050ae4:  ARM64_RELOC_BRANCH26	_swift_allocError
   50ae8: aa0003f3     	mov	x19, x0
   50aec: 3900003f     	strb	wzr, [x1]
   50af0: d28003e8     	mov	x8, #0x1f               ; =31
   50af4: f2fa0008     	movk	x8, #0xd000, lsl #48
   50af8: d1001508     	sub	x8, x8, #0x5
   50afc: a900d028     	stp	x8, x20, [x1, #0x8]
   50b00: 14000013     	b	0x50b4c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x184>
   50b04: 90000008     	adrp	x8, 0x50000 <_$ss5SIMD4Vss17FixedWidthIntegerRzrlE_8roundingAByxGAByqd__G_s25FloatingPointRoundingRuleOtcSBRd__s10SIMDScalarRd__lufCs6UInt16V_SfTt2g5+0x100>
		0000000000050b04:  ARM64_RELOC_PAGE21	LC247
   50b08: 91000108     	add	x8, x8, #0x0
		0000000000050b08:  ARM64_RELOC_PAGEOFF12	LC247
   50b0c: d1008108     	sub	x8, x8, #0x20
   50b10: b2410114     	orr	x20, x8, #0x8000000000000000
   50b14: 94000000     	bl	0x50b14 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x14c>
		0000000000050b14:  ARM64_RELOC_BRANCH26	_$s8SwiftJLI8JLIErrorOACs5ErrorAAWl
   50b18: aa0003e1     	mov	x1, x0
   50b1c: 90000000     	adrp	x0, 0x50000 <_$ss5SIMD4Vss17FixedWidthIntegerRzrlE_8roundingAByxGAByqd__G_s25FloatingPointRoundingRuleOtcSBRd__s10SIMDScalarRd__lufCs6UInt16V_SfTt2g5+0x100>
		0000000000050b1c:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s8SwiftJLI8JLIErrorON
   50b20: f9400000     	ldr	x0, [x0]
		0000000000050b20:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s8SwiftJLI8JLIErrorON
   50b24: d2800002     	mov	x2, #0x0                ; =0
   50b28: 52800003     	mov	w3, #0x0                ; =0
   50b2c: 94000000     	bl	0x50b2c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x164>
		0000000000050b2c:  ARM64_RELOC_BRANCH26	_swift_allocError
   50b30: aa0003f3     	mov	x19, x0
   50b34: d28003e8     	mov	x8, #0x1f               ; =31
   50b38: f2fa0008     	movk	x8, #0xd000, lsl #48
   50b3c: a9005028     	stp	x8, x20, [x1]
   50b40: a9017c3f     	stp	xzr, xzr, [x1, #0x10]
   50b44: 528000c8     	mov	w8, #0x6                ; =6
   50b48: 39008028     	strb	w8, [x1, #0x20]
   50b4c: aa0003f5     	mov	x21, x0
   50b50: 94000000     	bl	0x50b50 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x188>
		0000000000050b50:  ARM64_RELOC_BRANCH26	_swift_willThrow
   50b54: aa1303f5     	mov	x21, x19
   50b58: d10183bf     	sub	sp, x29, #0x60
   50b5c: a9467bfd     	ldp	x29, x30, [sp, #0x60]
   50b60: a9454ff4     	ldp	x20, x19, [sp, #0x50]
   50b64: a9445bf7     	ldp	x23, x22, [sp, #0x40]
   50b68: a94363f9     	ldp	x25, x24, [sp, #0x30]
   50b6c: a9426bfb     	ldp	x27, x26, [sp, #0x20]
   50b70: f9400ffc     	ldr	x28, [sp, #0x18]
   50b74: 6d40a3e9     	ldp	d9, d8, [sp, #0x8]
   50b78: fc4707ea     	ldr	d10, [sp], #0x70
   50b7c: d65f03c0     	ret
   50b80: 92800008     	mov	x8, #-0x1               ; =-1
   50b84: 9adb2108     	lsl	x8, x8, x27
   50b88: aa2803e8     	mvn	x8, x8
   50b8c: 9e230102     	ucvtf	s2, x8
   50b90: eb1403e8     	negs	x8, x20
   50b94: 92400508     	and	x8, x8, #0x3
   50b98: 92400689     	and	x9, x20, #0x3
   50b9c: da884528     	csneg	x8, x9, x8, mi
   50ba0: cb080288     	sub	x8, x20, x8
   50ba4: f81683a8     	stur	x8, [x29, #-0x98]
   50ba8: f100051f     	cmp	x8, #0x1
   50bac: 540018eb     	b.lt	0x50ec8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x500>
   50bb0: f81303b4     	stur	x20, [x29, #-0xd0]
   50bb4: b81383b7     	stur	w23, [x29, #-0xc8]
   50bb8: d280001b     	mov	x27, #0x0               ; =0
   50bbc: d2800014     	mov	x20, #0x0               ; =0
   50bc0: d2800017     	mov	x23, #0x0               ; =0
   50bc4: 4e040440     	dup.4s	v0, v2[0]
   50bc8: 3c9403a0     	stur	q0, [x29, #-0xc0]
   50bcc: 90000008     	adrp	x8, 0x50000 <_$ss5SIMD4Vss17FixedWidthIntegerRzrlE_8roundingAByxGAByqd__G_s25FloatingPointRoundingRuleOtcSBRd__s10SIMDScalarRd__lufCs6UInt16V_SfTt2g5+0x100>
		0000000000050bcc:  ARM64_RELOC_GOT_LOAD_PAGE21	_$ss25FloatingPointRoundingRuleO10towardZeroyA2BmFWC
   50bd0: f9400108     	ldr	x8, [x8]
		0000000000050bd0:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$ss25FloatingPointRoundingRuleO10towardZeroyA2BmFWC
   50bd4: b9400108     	ldr	w8, [x8]
   50bd8: b813c3a8     	stur	w8, [x29, #-0xc4]
   50bdc: 6f03d7e0     	mvni.4s	v0, #0x7f, msl #16
   50be0: 6ea0f800     	fneg.4s	v0, v0
   50be4: ad3b8ba0     	stp	q0, q2, [x29, #-0x90]
   50be8: 12b0100a     	mov	w10, #0x7f7fffff        ; =2139095039
   50bec: 6f00e408     	movi.2d	v8, #0000000000000000
   50bf0: 1e3e1009     	fmov	s9, #-1.00000000
   50bf4: 52a8f008     	mov	w8, #0x47800000         ; =1199570944
   50bf8: 1e27010a     	fmov	s10, w8
   50bfc: f2402eff     	tst	x23, #0xfff
   50c00: 540000e1     	b.ne	0x50c1c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x254>
   50c04: aa1303f5     	mov	x21, x19
   50c08: 94000000     	bl	0x50c08 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x240>
		0000000000050c08:  ARM64_RELOC_BRANCH26	_$s8SwiftJLI15NativeOperationV5checkyyKFZTf4d_n
   50c0c: 12b0100a     	mov	w10, #0x7f7fffff        ; =2139095039
   50c10: 3cd803a2     	ldur	q2, [x29, #-0x80]
   50c14: aa1503f3     	mov	x19, x21
   50c18: b5fff9f5     	cbnz	x21, 0x50b54 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x18c>
   50c1c: 3cf46b01     	ldr	q1, [x24, x20]
   50c20: 4ea11c20     	mov.16b	v0, v1
   50c24: 6f047400     	bic.4s	v0, #0x80, lsl #24
   50c28: 3cd703a3     	ldur	q3, [x29, #-0x90]
   50c2c: 4ea33c00     	cmge.4s	v0, v0, v3
   50c30: 0e612800     	xtn.4h	v0, v0
   50c34: 2e70a800     	umaxv.4h	h0, v0
   50c38: 1e260008     	fmov	w8, s0
   50c3c: 36000f68     	tbz	w8, #0x0, 0x50e28 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x460>
   50c40: 1e260028     	fmov	w8, s1
   50c44: 12007908     	and	w8, w8, #0x7fffffff
   50c48: 6b0a011f     	cmp	w8, w10
   50c4c: 54001b4c     	b.gt	0x50fb4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5ec>
   50c50: 1e222020     	fcmp	s1, s2
   50c54: 1e224c20     	fcsel	s0, s1, s2, mi
   50c58: 1e202008     	fcmp	s0, #0.0
   50c5c: 1e28ac00     	fcsel	s0, s0, s8, ge
   50c60: 1e264000     	frinta	s0, s0
   50c64: 1e292000     	fcmp	s0, s9
   50c68: 54001acd     	b.le	0x50fc0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5f8>
   50c6c: 1e2a2000     	fcmp	s0, s10
   50c70: 54001aa5     	b.pl	0x50fc4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5fc>
   50c74: 9b167ee9     	mul	x9, x23, x22
   50c78: 9b567ee8     	smulh	x8, x23, x22
   50c7c: eb89fd1f     	cmp	x8, x9, asr #63
   50c80: 54001a41     	b.ne	0x50fc8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x600>
   50c84: 1e380008     	fcvtzs	w8, s0
   50c88: 38296b08     	strb	w8, [x24, x9]
   50c8c: f1000adf     	cmp	x22, #0x2
   50c90: 54000121     	b.ne	0x50cb4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x2ec>
   50c94: d2800029     	mov	x9, #0x1                ; =1
   50c98: f2e80009     	movk	x9, #0x4000, lsl #48
   50c9c: 8b0902e9     	add	x9, x23, x9
   50ca0: f100053f     	cmp	x9, #0x1
   50ca4: 54001964     	b.mi	0x50fd0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x608>
   50ca8: 53087d08     	lsr	w8, w8, #8
   50cac: 8b1b0309     	add	x9, x24, x27
   50cb0: 39000528     	strb	w8, [x9, #0x1]
   50cb4: 5e0c0420     	mov	s0, v1[1]
   50cb8: 1e260008     	fmov	w8, s0
   50cbc: 12007908     	and	w8, w8, #0x7fffffff
   50cc0: 6b0a011f     	cmp	w8, w10
   50cc4: 5400178c     	b.gt	0x50fb4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5ec>
   50cc8: 1e222000     	fcmp	s0, s2
   50ccc: 1e224c00     	fcsel	s0, s0, s2, mi
   50cd0: 1e202008     	fcmp	s0, #0.0
   50cd4: 1e28ac00     	fcsel	s0, s0, s8, ge
   50cd8: 1e264000     	frinta	s0, s0
   50cdc: 1e292000     	fcmp	s0, s9
   50ce0: 5400170d     	b.le	0x50fc0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5f8>
   50ce4: 1e2a2000     	fcmp	s0, s10
   50ce8: 540016e5     	b.pl	0x50fc4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5fc>
   50cec: 910006e8     	add	x8, x23, #0x1
   50cf0: 9b167d09     	mul	x9, x8, x22
   50cf4: 9b567d08     	smulh	x8, x8, x22
   50cf8: eb89fd1f     	cmp	x8, x9, asr #63
   50cfc: 54001661     	b.ne	0x50fc8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x600>
   50d00: 1e380008     	fcvtzs	w8, s0
   50d04: 38296b08     	strb	w8, [x24, x9]
   50d08: f1000adf     	cmp	x22, #0x2
   50d0c: 54000101     	b.ne	0x50d2c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x364>
   50d10: d2800029     	mov	x9, #0x1                ; =1
   50d14: f2e80009     	movk	x9, #0x4000, lsl #48
   50d18: ab0902ff     	cmn	x23, x9
   50d1c: 540015a4     	b.mi	0x50fd0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x608>
   50d20: 53087d08     	lsr	w8, w8, #8
   50d24: 8b1b0309     	add	x9, x24, x27
   50d28: 39000d28     	strb	w8, [x9, #0x3]
   50d2c: 5e140420     	mov	s0, v1[2]
   50d30: 1e260008     	fmov	w8, s0
   50d34: 12007908     	and	w8, w8, #0x7fffffff
   50d38: 6b0a011f     	cmp	w8, w10
   50d3c: 540013cc     	b.gt	0x50fb4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5ec>
   50d40: 1e222000     	fcmp	s0, s2
   50d44: 1e224c00     	fcsel	s0, s0, s2, mi
   50d48: 1e202008     	fcmp	s0, #0.0
   50d4c: 1e28ac00     	fcsel	s0, s0, s8, ge
   50d50: 1e264000     	frinta	s0, s0
   50d54: 1e292000     	fcmp	s0, s9
   50d58: 5400134d     	b.le	0x50fc0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5f8>
   50d5c: 1e2a2000     	fcmp	s0, s10
   50d60: 54001325     	b.pl	0x50fc4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5fc>
   50d64: 91000ae8     	add	x8, x23, #0x2
   50d68: 9b167d09     	mul	x9, x8, x22
   50d6c: 9b567d08     	smulh	x8, x8, x22
   50d70: eb89fd1f     	cmp	x8, x9, asr #63
   50d74: 540012a1     	b.ne	0x50fc8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x600>
   50d78: 1e380008     	fcvtzs	w8, s0
   50d7c: 38296b08     	strb	w8, [x24, x9]
   50d80: f1000adf     	cmp	x22, #0x2
   50d84: 54000121     	b.ne	0x50da8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x3e0>
   50d88: d2800029     	mov	x9, #0x1                ; =1
   50d8c: f2e80009     	movk	x9, #0x4000, lsl #48
   50d90: 8b0902e9     	add	x9, x23, x9
   50d94: b100053f     	cmn	x9, #0x1
   50d98: 540011c4     	b.mi	0x50fd0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x608>
   50d9c: 53087d08     	lsr	w8, w8, #8
   50da0: 8b1b0309     	add	x9, x24, x27
   50da4: 39001528     	strb	w8, [x9, #0x5]
   50da8: 5e1c0420     	mov	s0, v1[3]
   50dac: 1e260008     	fmov	w8, s0
   50db0: 12007908     	and	w8, w8, #0x7fffffff
   50db4: 6b0a011f     	cmp	w8, w10
   50db8: 54000fec     	b.gt	0x50fb4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5ec>
   50dbc: 1e222000     	fcmp	s0, s2
   50dc0: 1e224c00     	fcsel	s0, s0, s2, mi
   50dc4: 1e202008     	fcmp	s0, #0.0
   50dc8: 1e28ac00     	fcsel	s0, s0, s8, ge
   50dcc: 1e264000     	frinta	s0, s0
   50dd0: 1e292000     	fcmp	s0, s9
   50dd4: 54000f6d     	b.le	0x50fc0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5f8>
   50dd8: 1e2a2000     	fcmp	s0, s10
   50ddc: 54000f45     	b.pl	0x50fc4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5fc>
   50de0: 91000ee8     	add	x8, x23, #0x3
   50de4: 9b167d09     	mul	x9, x8, x22
   50de8: 9b567d08     	smulh	x8, x8, x22
   50dec: eb89fd1f     	cmp	x8, x9, asr #63
   50df0: 54000ec1     	b.ne	0x50fc8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x600>
   50df4: 1e380008     	fcvtzs	w8, s0
   50df8: 38296b08     	strb	w8, [x24, x9]
   50dfc: f1000adf     	cmp	x22, #0x2
   50e00: 540004e1     	b.ne	0x50e9c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x4d4>
   50e04: d2800029     	mov	x9, #0x1                ; =1
   50e08: f2e80009     	movk	x9, #0x4000, lsl #48
   50e0c: 8b0902e9     	add	x9, x23, x9
   50e10: b100093f     	cmn	x9, #0x2
   50e14: 54000de4     	b.mi	0x50fd0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x608>
   50e18: 53087d08     	lsr	w8, w8, #8
   50e1c: 8b1b0309     	add	x9, x24, x27
   50e20: 39001d28     	strb	w8, [x9, #0x7]
   50e24: 1400001e     	b	0x50e9c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x4d4>
   50e28: 6f00e400     	movi.2d	v0, #0000000000000000
   50e2c: 94000000     	bl	0x50e2c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x464>
		0000000000050e2c:  ARM64_RELOC_BRANCH26	_$ss12pointwiseMaxyxx_xts4SIMDRzSF6ScalarRpzlFs5SIMD4VySfG_Tg5
   50e30: 4ea01c01     	mov.16b	v1, v0
   50e34: 3cd403a0     	ldur	q0, [x29, #-0xc0]
   50e38: 94000000     	bl	0x50e38 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x470>
		0000000000050e38:  ARM64_RELOC_BRANCH26	_$ss12pointwiseMinyxx_xts4SIMDRzSF6ScalarRpzlFs5SIMD4VySfG_Tg5
   50e3c: 6e218800     	frinta.4s	v0, v0
   50e40: 3c9503a0     	stur	q0, [x29, #-0xb0]
   50e44: f85983a8     	ldur	x8, [x29, #-0x68]
   50e48: f9403508     	ldr	x8, [x8, #0x68]
   50e4c: aa1a03e0     	mov	x0, x26
   50e50: b853c3a1     	ldur	w1, [x29, #-0xc4]
   50e54: aa1903e2     	mov	x2, x25
   50e58: d63f0100     	blr	x8
   50e5c: 3cd503a0     	ldur	q0, [x29, #-0xb0]
   50e60: aa1a03e0     	mov	x0, x26
   50e64: 94000000     	bl	0x50e64 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x49c>
		0000000000050e64:  ARM64_RELOC_BRANCH26	_$ss5SIMD4Vss17FixedWidthIntegerRzrlE_8roundingAByxGAByqd__G_s25FloatingPointRoundingRuleOtcSBRd__s10SIMDScalarRd__lufCs6UInt16V_SfTt2g5
   50e68: f10006df     	cmp	x22, #0x1
   50e6c: 54000081     	b.ne	0x50e7c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x4b4>
   50e70: 0e001800     	uzp1.8b	v0, v0, v0
   50e74: bc376b00     	str	s0, [x24, x23]
   50e78: 14000007     	b	0x50e94 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x4cc>
   50e7c: d2800028     	mov	x8, #0x1                ; =1
   50e80: f2e80008     	movk	x8, #0x4000, lsl #48
   50e84: 8b0802e8     	add	x8, x23, x8
   50e88: f100051f     	cmp	x8, #0x1
   50e8c: 54000ae4     	b.mi	0x50fe8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x620>
   50e90: fc3b6b00     	str	d0, [x24, x27]
   50e94: 3cd803a2     	ldur	q2, [x29, #-0x80]
   50e98: 12b0100a     	mov	w10, #0x7f7fffff        ; =2139095039
   50e9c: b10012fc     	adds	x28, x23, #0x4
   50ea0: 540009a6     	b.vs	0x50fd4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x60c>
   50ea4: 910012f7     	add	x23, x23, #0x4
   50ea8: 91004294     	add	x20, x20, #0x10
   50eac: 9100237b     	add	x27, x27, #0x8
   50eb0: f85683a8     	ldur	x8, [x29, #-0x98]
   50eb4: eb08039f     	cmp	x28, x8
   50eb8: 54ffea2b     	b.lt	0x50bfc <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x234>
   50ebc: b85383b7     	ldur	w23, [x29, #-0xc8]
   50ec0: f85303b4     	ldur	x20, [x29, #-0xd0]
   50ec4: 14000002     	b	0x50ecc <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x504>
   50ec8: d280001c     	mov	x28, #0x0               ; =0
   50ecc: aa1403fa     	mov	x26, x20
   50ed0: eb1c0294     	subs	x20, x20, x28
   50ed4: 5400088b     	b.lt	0x50fe4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x61c>
   50ed8: 54ffe3e0     	b.eq	0x50b54 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x18c>
   50edc: aa1703fb     	mov	x27, x23
   50ee0: d2e80008     	mov	x8, #0x4000000000000000 ; =4611686018427387904
   50ee4: 8b080397     	add	x23, x28, x8
   50ee8: 52800028     	mov	w8, #0x1                ; =1
   50eec: aa1c0519     	orr	x25, x8, x28, lsl #1
   50ef0: 12b0100a     	mov	w10, #0x7f7fffff        ; =2139095039
   50ef4: 6f00e408     	movi.2d	v8, #0000000000000000
   50ef8: 1e3e1009     	fmov	s9, #-1.00000000
   50efc: 52a8f008     	mov	w8, #0x47800000         ; =1199570944
   50f00: 1e27010a     	fmov	s10, w8
   50f04: 3c9803a2     	stur	q2, [x29, #-0x80]
   50f08: 14000008     	b	0x50f28 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x560>
   50f0c: 53087d08     	lsr	w8, w8, #8
   50f10: 38396b08     	strb	w8, [x24, x25]
   50f14: 910006f7     	add	x23, x23, #0x1
   50f18: 91000b39     	add	x25, x25, #0x2
   50f1c: 9100079c     	add	x28, x28, #0x1
   50f20: f1000694     	subs	x20, x20, #0x1
   50f24: 54ffe180     	b.eq	0x50b54 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x18c>
   50f28: eb1a039f     	cmp	x28, x26
   50f2c: 5400050a     	b.ge	0x50fcc <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x604>
   50f30: f2402f9f     	tst	x28, #0xfff
   50f34: 540000e1     	b.ne	0x50f50 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x588>
   50f38: aa1303f5     	mov	x21, x19
   50f3c: 94000000     	bl	0x50f3c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x574>
		0000000000050f3c:  ARM64_RELOC_BRANCH26	_$s8SwiftJLI15NativeOperationV5checkyyKFZTf4d_n
   50f40: 12b0100a     	mov	w10, #0x7f7fffff        ; =2139095039
   50f44: 3cd803a2     	ldur	q2, [x29, #-0x80]
   50f48: aa1503f3     	mov	x19, x21
   50f4c: b5ffe055     	cbnz	x21, 0x50b54 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x18c>
   50f50: bc7c7b00     	ldr	s0, [x24, x28, lsl #2]
   50f54: 1e260008     	fmov	w8, s0
   50f58: 12007908     	and	w8, w8, #0x7fffffff
   50f5c: 6b0a011f     	cmp	w8, w10
   50f60: 540002ac     	b.gt	0x50fb4 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x5ec>
   50f64: 3707fd9b     	tbnz	w27, #0x0, 0x50f14 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x54c>
   50f68: 1e222000     	fcmp	s0, s2
   50f6c: 1e224c00     	fcsel	s0, s0, s2, mi
   50f70: 1e202008     	fcmp	s0, #0.0
   50f74: 1e28ac00     	fcsel	s0, s0, s8, ge
   50f78: 1e264000     	frinta	s0, s0
   50f7c: 1e292000     	fcmp	s0, s9
   50f80: 540002cd     	b.le	0x50fd8 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x610>
   50f84: 1e2a2000     	fcmp	s0, s10
   50f88: 540002a5     	b.pl	0x50fdc <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x614>
   50f8c: 9b167f89     	mul	x9, x28, x22
   50f90: 9b567f88     	smulh	x8, x28, x22
   50f94: eb89fd1f     	cmp	x8, x9, asr #63
   50f98: 54000241     	b.ne	0x50fe0 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x618>
   50f9c: 1e380008     	fcvtzs	w8, s0
   50fa0: 38296b08     	strb	w8, [x24, x9]
   50fa4: f1000adf     	cmp	x22, #0x2
   50fa8: 54fffb61     	b.ne	0x50f14 <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x54c>
   50fac: b6fffb17     	tbz	x23, #0x3f, 0x50f0c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x544>
   50fb0: d4200020     	brk	#0x1
   50fb4: 90000008     	adrp	x8, 0x50000 <_$ss5SIMD4Vss17FixedWidthIntegerRzrlE_8roundingAByxGAByqd__G_s25FloatingPointRoundingRuleOtcSBRd__s10SIMDScalarRd__lufCs6UInt16V_SfTt2g5+0x100>
		0000000000050fb4:  ARM64_RELOC_PAGE21	LC174
   50fb8: 91000108     	add	x8, x8, #0x0
		0000000000050fb8:  ARM64_RELOC_PAGEOFF12	LC174
   50fbc: 17fffed4     	b	0x50b0c <_$s8SwiftJLI34ParallelSequentialGreyscaleDecoderO20compactPixelsInPlace_9precision14bytesPerSample11floatOutputySrySfG_S2iSbtKFZTf4nnnnd_n+0x144>
   50fc0: d4200020     	brk	#0x1
   50fc4: d4200020     	brk	#0x1
   50fc8: d4200020     	brk	#0x1
   50fcc: d4200020     	brk	#0x1
   50fd0: d4200020     	brk	#0x1
   50fd4: d4200020     	brk	#0x1
   50fd8: d4200020     	brk	#0x1
   50fdc: d4200020     	brk	#0x1
   50fe0: d4200020     	brk	#0x1
   50fe4: d4200020     	brk	#0x1
   50fe8: d4200020     	brk	#0x1
