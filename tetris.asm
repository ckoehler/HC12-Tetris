* =============
* = Registers =
* =============
SPCR	equ	$1028	*SPI Control
SPSR	equ	$1029	*SPI Status
SPDR	equ	$102A	*SPI Data
DDRD	equ	$1009	*Register D
PORTD	equ	$1008
SCCR2	equ	$102D
SCSR	equ	$102E
SCDR	equ	$102F
BAUD	equ	$102B

* =============
* = Variables =
* =============
* define memory range to store the stage in.
* stage = all unmovable pixels
stage_beg	equ	$0000
stage_end	equ	$000F

block_top_ptr	equ	$0010
block_bot_ptr	equ	$0011

* L D R U Start _ _ Select
buttons1	equ	$0012
* Square X O Triangle R1 L1 R2 L2
buttons2	equ	$0013

* points somewhere in the stage to the bottom
* of the current block
block_ptr	equ	$0012

	org	$2000
* ========
* = Init =
* ========
Init:	jsr	SPI_INIT
*	jsr	SCI_INIT
	jsr	Main

*Init SPI
SPI_INIT:
	ldab	DDRD	*Load Current state of DDRD
	orab	#$38	*Turn on Slave select
	stab	DDRD	*store
	ldab	#%01011110	*Enable SPI
	stab	SPCR
	ldab	PORTD
	orab	#$20
	stab	PORTD
	rts

*Init SCI
SCI_INIT:
	psha
	ldaa	#$08	* enable Tx and Rx
	staa	SCCR2
	ldaa	#$30	* set BAUD to 9600
	staa	BAUD
	pula
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
	ldab	#$80	* send Hello to pad
	jsr	Pad_RW
	ldab	#$42	* now send request for data
	jsr	Pad_RW	* after this we get Pad ID
	ldab	#$00
	jsr	Pad_RW
	ldab	#$00
	jsr	Pad_RW
	comb
	stab	buttons1
	ldab	#$00
	jsr	Pad_RW
	comb
	stab	buttons2
	jsr	Pad_En
	rts
	
*Toggles Pad SS
Pad_En:
	pshb
	ldab	PORTD	*Load Current State of DDRD
	eorb	#$20	*Toggle Slave Select
	stab	PORTD	*Store back
	pulb
	rts

* In: {B} with what's sent to the pad
* Out: {B} with what's returned
Pad_RW:		
	psha
	stab	SPDR	*Store {B} to send to pad

Pad_RW1:
	ldab	SPSR	*Reads Pad Status Register
	andb	#$80	*Checks for status high on bit 7
	beq	Pad_RW1	*Checks again if not high
	ldab	SPDR	*Pulls data from Pad
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
Output_Char1:	ldab	SCSR	* check to see if the transmit register is empty
	andb	#$80
	cmpb	#$80
	bne	Output_Char1	* if not, keep looping until it is
	staa	SCDR	* finally, write the character to the SCI
	pulb
	rts

STR_moveleft:	fcc	"Left pushed!"
	fcb	10,13,0

STR_moveright:	fcc	"Right pushed!"
	fcb	10,13,0
* ===========
* = Vectors =
* ===========
