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
	mov	a, #010H
	movp	a, @a
	mov	a, #020H
	movp3	a, @a
	jmp	loop
