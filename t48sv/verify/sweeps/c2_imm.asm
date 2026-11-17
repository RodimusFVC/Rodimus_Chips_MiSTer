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
	mov	a, #05AH
	add	a, #033H
	anl	a, #0F0H
	mov	r2, #003H
	in	a, p1
	outl	p1, a
	anl	p2, #0FEH
	orl	p1, #001H
	outl	bus, a
	ins	a, bus
	anl	bus, #07FH
	orl	bus, #080H
	jmp	loop
