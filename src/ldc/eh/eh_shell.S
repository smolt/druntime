	.text
	.global	_d_eh_resume_unwind
	.align	2
_d_eh_resume_unwind:
	push	{r1-r4,lr}
	mov	r1,lr
	bl	_dx_eh_resume_unwind
	pop	{r1-r4,lr}
	b	_Unwind_Resume
