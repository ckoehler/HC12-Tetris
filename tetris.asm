* =============
* = Registers =
* =============
SP0CR1	equ	$08D0	*SPI Control
SP0SR	equ	$08D3	*SPI Status
SP0DR	equ	$08D5	*SPI Data
SP0BR	equ	$08D2	*BAUD register
DDRS	equ	$08D7
PORTS	equ	$08D6

SC0SR1	equ	$08C4
SC0DRL	equ	$08C7

* =============
* = Variables =
* =============

	org	$00
* define memory range to store the stage in.
* stage = all unmovable pixels
stage_beg	rmb	15
stage_end	rmb	1

* points to the bottom memory location that defines
* the block shape
block_ptr	rmb	1

* it's the block height
block_height	rmb	1

* Select _ _ Start U R D L
buttons1	rmb	1
* L2 R2 L1 R1 Triangle O X Square
buttons2	rmb	1

* saves last button configs
buttons1l	rmb	1
buttons2l	rmb	1

* offset from top of the stage, downwards
stage_block_ptr	rmb	1

* FF if vertical collision detected
collision	rmb	1

temp	rmb	1

	org	$1000
* ========
* = Init =
* ========
Init:	jsr	SPI_INIT
	jsr	Var_Init
	ldaa	#0
	staa	buttons1l
	staa	buttons2l
	jsr	Main

*Init SPI
SPI_INIT:
	ldab	DDRS	*Load Current state of DDRS
	orab	#%11100000	*Define output ports for Port S
	stab	DDRS	*store
	ldab	#%01011100	*Enable SPI
	stab	SP0CR1
	ldab	#%00000101	* set rate to 125kHz
	stab	SP0BR
	ldab	PORTS	
	orab	#$80
	stab	PORTS
	rts

Var_Init:	ldaa	#4
	staa	block_height
	rts

* ========
* = Main =
* ========
Main:
	jsr	get_buttons
	
* check for left button
	ldaa	buttons1
	anda	#$01
	beq	Main1
	jsr	move_left
Main1:
* check for right button
	ldaa	buttons1
	anda	#$04
	beq	Main2
	jsr	move_right
Main2:
* check for rotate left (X)
	ldaa	buttons2
	anda	#$2
	beq	Main3
	jsr	rotate_left
Main3:
* check for rotate right (O)
	ldaa	buttons2
	anda	#$4
	beq	Main4
	jsr	rotate_right
Main4:
	bra	Main

* ========
* = Subs =
* ========

* saves buttons in buttons1 and buttons2
get_buttons:
	jsr	Pad_En
	ldab	#$80	* send Hello to pad
	jsr	Pad_RW
	ldab	#$42	* now send request for data
	jsr	Pad_RW	* after this we get Pad ID
	ldab	#$00
	jsr	Pad_RW
	ldab	#$00
	jsr	Pad_RW
	comb
	stab	temp
	eorb	buttons1l
	andb	temp
	stab	buttons1
	ldab	#$00
	jsr	Pad_RW
	comb
	stab	temp
	eorb	buttons2l
	andb	temp
	stab	buttons2
	jsr	Pad_En
	rts


* =======================
* = SPI utility methods =
* =======================
*Toggles Pad SS
Pad_En:
	pshb
	ldab	PORTS	*Load Current State of PORTS
	eorb	#$80	*Toggle Slave Select
	stab	PORTS	*Store back
	pulb
	rts

* In: {B} with what's sent to the pad
* Out: {B} with what's returned
Pad_RW:		
	psha
	stab	SP0DR	*Store {B} to send to pad

Pad_RW1:
	ldab	SP0SR	*Reads Pad Status Register
	andb	#$80	*Checks for status high on bit 7
	beq	Pad_RW1	*Checks again if not high
	ldab	SP0DR	*Pulls data from Pad
Pad_RW_E:	pula
	rts

* =======================
* = SCI utility methods =
* =======================	
* work on the byte that X points to that we get
Output:
	psha
Output1:	ldaa	0,x	* get first character of what X points to
	inx		* increment x to get the next address to read from
	cmpa	#$00	* did we encounter a 0 char?
	beq	OutputEnd	* if so, end
	jsr	Output_Char	* otherwise, print the character, from regA
	bra	Output1	* and start all over
OutputEnd:	pula
	rts

* expects data to send out in A
Output_Char:     
	pshb
Output_Char1:	ldab	SC0SR1	* check to see if the transmit register is empty
	andb	#$80
	cmpb	#$80
	bne	Output_Char1	* if not, keep looping until it is
	staa	SC0DRL	* finally, write the character to the SCI
	pulb
	rts
	
* ==================
* = Button actions =
* ==================

* make two passes: first, just check for $80. If we find it
* we can't shift anything left. Otherwise, we do the actual
* shifting
move_left:
	ldx	#stage_block_ptr
	ldab	block_height
move_left_1:
	ldaa	0,x
	inx
	decb
	anda	#$80
	beq	move_left_end
	cmpb	#0
	beq	move_left_2
	bra	move_left_1

move_left_2:	ldx	#stage_block_ptr
	ldab	block_height
move_left_3:
	ldaa	0,x
	inx
	decb
	lsla
	cmpb	#0
	beq	move_left_end
	bra	move_left_3
move_left_end:
	rts

* make two passes: first, just check for $01. If we find it
* we can't shift anything right. Otherwise, we do the actual
* shifting
move_right:
	ldx	#stage_block_ptr
	ldab	block_height
move_right_1:
	ldaa	0,x
	inx
	decb
	anda	#$01
	beq	move_right_end
	cmpb	#0
	beq	move_right_2
	bra	move_right_1

move_right_2:	ldx	#stage_block_ptr
	ldab	block_height
move_right_3:
	ldaa	0,x
	inx
	decb
	lsra
	cmpb	#0
	beq	move_right_end
	bra	move_right_3
move_right_end:
	rts

rotate_left:
	ldx	#STR_rotateleft
	jsr	Output
	rts
	
rotate_right:
	ldx	#STR_rotateright
	jsr	Output
	rts	
	
* ===================
* = Game Logic subs =
* ===================

* check for horizontal collision
check_hcol_l:
	ldab	block_height
check_hcol_l1:
* first make sure if any line of the block
* already occupies bit 7
	ldaa	block_ptr
	anda	#$80
	beq	check_hcol_l1
	jsr	set_collision
check_hcol_end:
	rts



* checks for vertical collisions 
check_vcol:
	psha
	pshb
	ldab	block_height
* x will keep track of the stage line
	ldx	#stage_block_ptr
* y will keep track of the block line
	ldy	#stage_block_ptr
check_vcol1:
* look ahead one row
	ldaa	1,x
* and it with the current line of the block
	anda	0,y
* if we don't get 0, we have a collision
	jsr	set_collision
* see if we checked all lines of the block
	cmpb	#0
* if so, finish
	beq	check_vcol_end
* else decrement b...
	decb
* ... and check the next line of the stage against the 
* next line of the block -> increment both x and y
	inx
	iny
	
	bra	check_vcol1
check_vcol_end:	
	pulb
	pula
	rts	


set_collision:
	ldaa	#$FF
	staa	collision	
	jsr

* ====================
* = Constant strings =
* ====================
STR_moveleft:	fcc	"Left pushed!"
	fcb	10,13,0

STR_moveright:	fcc	"Right pushed!"
	fcb	10,13,0

STR_rotateright:	fcc	"rotate right!"
	fcb	10,13,0
		
STR_rotateleft:	fcc	"rotate left!"
	fcb	10,13,0
* ===========
* = Vectors =
* ===========
