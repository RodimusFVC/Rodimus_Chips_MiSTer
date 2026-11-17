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
	clr	a
	jz	l1
l1:	jnz	l2
	cpl	a
l2:	jc	l3
l3:	jnc	l4
l4:	jt0	l5
l5:	jnt0	l6
l6:	jt1	l7
l7:	jnt1	l8
l8:	jf0	l9
l9:	jf1	l10
l10:	jtf	l11
l11:	jni	l12
l12:	jb0	l13
l13:	jb7	l14
l14:	mov	r3, #2
l15:	djnz	r3, l15
	cpl	f0
	jmp	loop
