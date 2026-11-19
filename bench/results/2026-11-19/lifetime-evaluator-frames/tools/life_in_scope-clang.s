
build/parity-nov19/llvm-review/wasm2c/aot:	file format elf64-x86-64

Disassembly of section .text:

0000000000376170 <w2c_compiler_f679>:
  376170:      	pushq	%rax
  376171:      	movl	0x10(%rdi), %r8d
  376175:      	leal	0x20(%r8), %r9d
  376179:      	cmpl	0x38(%rdi), %r9d
  37617d:      	ja	0x3761f5 <w2c_compiler_f679+0x85>
  37617f:      	movq	0x40(%rdi), %rax
  376183:      	movl	%r9d, 0x10(%rdi)
  376187:      	movl	0x14(%rdi), %r9d
  37618b:      	testq	%rcx, %rcx
  37618e:      	js	0x3761c7 <w2c_compiler_f679+0x57>
  376190:      	cmpq	%rcx, %rdx
  376193:      	jle	0x3761bd <w2c_compiler_f679+0x4d>
  376195:      	movl	%esi, %esi
  376197:      	nopw	(%rax,%rax)
  3761a0:      	movq	(%rax,%rsi), %r10
  3761a4:      	movq	%r10, %r11
  3761a7:      	shrq	$0x20, %r11
  3761ab:      	cmpq	%r11, %rdx
  3761ae:      	jae	0x3761d3 <w2c_compiler_f679+0x63>
  3761b0:      	leal	(%r10,%rdx,8), %edx
  3761b4:      	movq	(%rax,%rdx), %rdx
  3761b8:      	cmpq	%rcx, %rdx
  3761bb:      	jg	0x3761a0 <w2c_compiler_f679+0x30>
  3761bd:      	xorl	%eax, %eax
  3761bf:      	cmpq	%rcx, %rdx
  3761c2:      	sete	%al
  3761c5:      	jmp	0x3761c9 <w2c_compiler_f679+0x59>
  3761c7:      	xorl	%eax, %eax
  3761c9:      	movl	%r9d, 0x14(%rdi)
  3761cd:      	movl	%r8d, 0x10(%rdi)
  3761d1:      	popq	%rcx
  3761d2:      	retq
  3761d3:      	movq	0x8(%rdi), %rdi
  3761d7:      	movl	$0xf91, %esi            # imm = 0xF91
  3761dc:      	movl	$0x19, %edx
  3761e1:      	movl	$0x8e2, %ecx            # imm = 0x8E2
  3761e6:      	callq	0x163b0 <w2c_goose_abort>
  3761eb:      	movl	$0x5, %edi
  3761f0:      	callq	0x5489d0 <wasm_rt_trap>
  3761f5:      	movq	0x8(%rdi), %rdi
  3761f9:      	movl	$0xf20, %esi            # imm = 0xF20
  3761fe:      	movl	$0x1a, %edx
  376203:      	movl	$0x8de, %ecx            # imm = 0x8DE
  376208:      	jmp	0x3761e6 <w2c_compiler_f679+0x76>
  37620a:      	nopw	(%rax,%rax)
