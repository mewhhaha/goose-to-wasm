
build/parity-nov19/llvm-review/wasm2c/simd.cwasm:	file format elf64-x86-64

Disassembly of section .text:

00000000001c53c0 <wasm[0]::function[679]>:
  1c53c0:      	pushq	%rbp
  1c53c1:      	movq	%rsp, %rbp
  1c53c4:      	movq	0x8(%rdi), %r10
  1c53c8:      	movq	0x18(%r10), %r10
  1c53cc:      	addq	$0x10, %r10
  1c53d0:      	cmpq	%rsp, %r10
  1c53d3:      	ja	0x1c54a9 <wasm[0]::function[679]+0xe9>
  1c53d9:      	movq	%rdx, %rsi
  1c53dc:      	movl	0x340(%rdi), %r9d
  1c53e3:      	movl	0x3e0(%rdi), %eax
  1c53e9:      	leal	0x20(%r9), %edx
  1c53ed:      	cmpl	%eax, %edx
  1c53ef:      	ja	0x1c5484 <wasm[0]::function[679]+0xc4>
  1c53f5:      	leal	0x20(%r9), %eax
  1c53f9:      	movl	%eax, 0x340(%rdi)
  1c53ff:      	testq	%r8, %r8
  1c5402:      	jl	0x1c544b <wasm[0]::function[679]+0x8b>
  1c5408:      	movq	0x38(%rdi), %rdx
  1c540c:      	movq	%rsi, %rax
  1c540f:      	movl	%eax, %esi
  1c5411:      	cmpq	%r8, %rcx
  1c5414:      	jle	0x1c543a <wasm[0]::function[679]+0x7a>
  1c541a:      	movq	(%rdx,%rsi), %rax
  1c541e:      	movq	%rax, %r10
  1c5421:      	shrq	$0x20, %r10
  1c5425:      	cmpq	%r10, %rcx
  1c5428:      	jae	0x1c545c <wasm[0]::function[679]+0x9c>
  1c542e:      	leal	(%rax,%rcx,8), %eax
  1c5431:      	movq	(%rdx,%rax), %rcx
  1c5435:      	jmp	0x1c5411 <wasm[0]::function[679]+0x51>
  1c543a:      	movq	%rdi, %rsi
  1c543d:      	cmpq	%r8, %rcx
  1c5440:      	sete	%al
  1c5443:      	movzbl	%al, %eax
  1c5446:      	jmp	0x1c5450 <wasm[0]::function[679]+0x90>
  1c544b:      	movq	%rdi, %rsi
  1c544e:      	xorl	%eax, %eax
  1c5450:      	movl	%r9d, 0x340(%rsi)
  1c5457:      	movq	%rbp, %rsp
  1c545a:      	popq	%rbp
  1c545b:      	retq
  1c545c:      	movq	0x130(%rdi), %rax
  1c5463:      	movq	%rdi, %rcx
  1c5466:      	movq	0x140(%rcx), %rdi
  1c546d:      	movq	%rcx, %rsi
  1c5470:      	movl	$0xf91, %edx            # imm = 0xF91
  1c5475:      	movl	$0x19, %ecx
  1c547a:      	movl	$0x8e2, %r8d            # imm = 0x8E2
  1c5480:      	callq	*%rax
  1c5482:      	ud2
  1c5484:      	movq	%rdi, %rsi
  1c5487:      	movq	0x130(%rsi), %rax
  1c548e:      	movq	0x140(%rsi), %rdi
  1c5495:      	movl	$0xf20, %edx            # imm = 0xF20
  1c549a:      	movl	$0x1a, %ecx
  1c549f:      	movl	$0x8de, %r8d            # imm = 0x8DE
  1c54a5:      	callq	*%rax
  1c54a7:      	ud2
  1c54a9:      	ud2
		...
  1c54bf:      	addb	%dl, 0x48(%rbp)
