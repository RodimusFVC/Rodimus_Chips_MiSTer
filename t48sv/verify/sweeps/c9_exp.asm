	CPU	8048
	ORG	0
	jmp	start
	ORG	3
	inc	r7
	retr
	ORG	7
	inc	r6
	retr
start:	mov	r0, #020H
	mov	r1, #021H
	mov	a, #0FFH
	mov	t, a
	strt	cnt
	en	tcnti
	en	i
	clr	a
loop:
	movd	a, p4
	movd	p5, a
	anld	p6, a
	orld	p7, a
	sel	rb1
	mov	r0, #022H
	sel	rb0
	mov	a, psw
	mov	psw, a
	ent0	clk
	sel	mb1
	sel	mb0
	jmp	loop
