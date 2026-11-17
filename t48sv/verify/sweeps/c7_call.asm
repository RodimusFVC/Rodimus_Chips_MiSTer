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
	call	sub1
	call	sub2
	sel	mb1
	call	sub3 & 07FFH
	sel	mb0
	jmp	loop
sub1:	ret
sub2:	retr
	ORG	0800H
sub3:	ret
	jmp	loop
