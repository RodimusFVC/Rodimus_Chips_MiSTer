	CPU	8022
	ORG	0
	jmp	start
	ORG	3
	inc	r7
	reti
	ORG	7
	inc	r6
	reti
start:	mov	a, #0FFH
	mov	t, a
	strt	cnt
	en	tcnti
	en	i
loop:	sel	an0
	rad
	sel	an1
	rad
	in	a, p0
	outl	p0, a
	jt0	l1
l1:	jnt1	l2
l2:	call	sub
	jmp	loop
sub:	ret
