	CPU	8021
	ORG	0
	jmp	start
start:	mov	a, #0FFH
	mov	t, a
	strt	cnt
loop:	in	a, p0
	outl	p0, a
	in	a, p1
	outl	p2, a
	jt1	l1
l1:	jtf	l2
l2:	movd	a, p4
	movp	a, @a
	call	sub
	jmp	loop
sub:	ret
