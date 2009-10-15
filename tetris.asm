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

block_top_ptr	rmb	1
block_bot_ptr	rmb	1

* Select _ _ Start U R D L
buttons1	rmb	1
* L2 R2 L1 R1 Triangle O X Square
buttons2	rmb	1

* saves last button configs
buttons1l	rmb	1
buttons2l	rmb	1

* points somewhere in the stage to the bottom
* of the current block
block_ptr	rmb	1


temp	rmb	1

	org	$2000
* ========
* = Init =
* ========
Init:	jsr	SPI_INIT
	ldaa	#0
	staa	buttons1l
	staa	buttons2l
	jsr	Main

*Init SPI
SPI_INIT:
	ldab	DDRS	*Load Current state of DDRS
	orab	#%11100000	*Define output ports for Port S
	stab	DDRS	*store
	ldab	#%01011101	*Enable SPI
	stab	SP0CR1
	ldab	#%00000100	* set rate to 250kHz
	stab	SP0BR
	ldab	PORTS	
	orab	#$80
	stab	PORTS
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
	bra	Main

* ========
* = Subs =
* ========

* saves buttons in buttons1 and buttons2
get_buttons:
	jsr	Pad_En
	ldab	#$01	* send Hello to pad
	jsr	Pad_RW
	ldab	#$42	* now send request for data
	jsr	Pad_RW	* after this we get Pad ID
	ldab	#$00
	jsr	Pad_RW
	ldab	#$00
	jsr	Pad_RW
	comb
*	stab	temp
*	eorb	buttons1l
*	andb	temp
	stab	buttons1
	ldab	#$00
	jsr	Pad_RW
	comb
*	stab	temp
*	eorb	buttons2l
*	andb	temp
	stab	buttons2
	jsr	Pad_En
	rts
	
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
	

move_left:
	ldx	#STR_moveleft
	jsr	Output
	rts

move_right:
	ldx	#STR_moveright
	jsr	Output
	rts
	

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

STR_moveleft:	fcc	"Left pushed!"
	fcb	10,13,0

STR_moveright:	fcc	"Right pushed!"
	fcb	10,13,0
* ===========
* = Vectors =
* ===========
