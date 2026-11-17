	CPU	8041
	ORG	0
	jmp	start
	ORG	3
	retr
	ORG	7
	retr
start:	en	dma
	en	flags
loop:	mov	a, #040H
	outl	p2, a
	in	a, dbb
	out	dbb, a
	clr	f1
	cpl	f1
	anl	p2, #0BFH
	orl	p2, #040H
	jmp	loop
