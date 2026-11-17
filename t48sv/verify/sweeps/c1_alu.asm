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
	inc	a
	add	a, r0
	xch	a, @r0
	dec	r1
	rl	a
	swap	a
	da	a
	cpl	c
	xrl	a, r1
	orl	a, @r1
	jmp	loop
