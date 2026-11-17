	CPU	8041
	ORG	0
	jmp	start
	ORG	3
	in	a, dbb
	out	dbb, a
	retr
	ORG	7
	inc	r6
	retr
start:	mov	a, #0FFH
	mov	t, a
	strt	cnt
	en	tcnti
	en	i
	en	flags
loop:	jnibf	l1
l1:	jobf	l2
l2:	in	a, dbb
	inc	a
	out	dbb, a
	mov	sts, a
	mov	a, psw
	jf1	l3
l3:	jt1	l4
l4:	movp3	a, @a
	jmp	loop
