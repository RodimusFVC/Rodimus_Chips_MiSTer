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
	stop	tcnt
	mov	a, #0FEH
	mov	t, a
	strt	t
	mov	a, t
	strt	cnt
	jtf	t1
t1:	dis	tcnti
	en	tcnti
	dis	i
	en	i
	jmp	loop
