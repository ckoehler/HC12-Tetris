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

PORTG	equ	$0828	;Expanded Address of Command
DDRG	equ	$082A
PORTH	equ	$0829	;Expanded Address of Data
DDRH	equ	$082B

BIT_0	equ	1	;/RESET
BIT_1	equ	2	;/READ
BIT_2	equ	4	;/WRITE
BIT_3	equ	8	;/CS
BIT_4	equ	16	;A0

CursorInit	equ	#$0000	;Initial Condition for LCD stage

Mwrite	equ	$42	;Memory write command for LCD

* =============
* = Variables =
* =============

	org	$00
* cursor pointers used to define location on screen	
CPointer	rmb	2
CCPointer	rmb	2
* define memory range to store the stage in.
* stage = all unmovable pixels
stage_beg	rmb	15
stage_end	rmb	1

* points to the bottom memory location that defines
* the block shape
block_ptr	rmb	2

* it's the block height
block_height	rmb	1

* The following hex codes for buttons are only
* necessary to work around our broken controller.
* 01 = no buton pressed
* 03 = Select
* 19 = Start
* 81 = Left
* 61 = Right
* C1 = Down
buttons1	rmb	1

* C1 = no button pressed
* E1 = circle
* F1 = square
* D9 = R1
* CD = L1
* C7 = R2
* C3 = L2
buttons2	rmb	1

* saves last button configs
buttons1l	rmb	1
buttons2l	rmb	1

* offset from top of the stage, downwards
stage_block_ptr	rmb	1

* FF if vertical collision detected
collision	rmb	1

temp	rmb	1
block_1	rmb	1

	org	$1000
* ========
* = Init =
* ========
Init:	
	jsr	SPI_INIT
	jsr	Var_Init
	ldaa	#0
	staa	buttons1l
	staa	buttons2l
;LCD Init	
	jsr	LCD_INIT
	jsr	InitCurPointers
	
;************TESTING ONLY**********************	
	ldd	#$0000
	jsr	UpdateCursor
	ldaa	#Mwrite
	jsr	LCD_Command
	jsr	Square
;***********TESTING ONLY***********************

;Jump to Main
	jsr	Main

*Init SPI
SPI_INIT:
	ldab	DDRS	*Load Current state of DDRS
	orab	#%11100000	*Define output ports for Port S
	stab	DDRS	*store
	ldab	#%01011101	*Enable SPI
	stab	SP0CR1
	ldab	#%00000101	* set rate to 125kHz
	stab	SP0BR
	ldab	PORTS	
	orab	#$80
	stab	PORTS
	rts

Var_Init:	ldaa	#4
	staa	block_height
* 	because of the broken controller, "no buttons pushed"
* 	is $01 for the first set of buttons, and $C1 for the second
	ldaa	#$01
	staa	buttons1l
	ldaa	#$C1
	staa	buttons2l
* 	Testing a block, so preloading it here
	ldaa	#$10
	staa	block_1
	ldd	#block_1
	std	block_ptr
* 	Testing done
	rts

* ========
* = Main =
* ========
Main:
	jsr	get_buttons
	
* check for left button
	ldaa	buttons1
	cmpa	#$81
	bne	Main1
	jsr	move_left
Main1:
* check for right button
	ldaa	buttons1
	cmpa	#$61
	bne	Main2
	jsr	move_right
Main2:
	
* check for rotate left (triangle)
	ldaa	buttons2
	cmpa	#$F1
	bne	Main3
	jsr	rotate_left
Main3:
* check for rotate right (O)
	ldaa	buttons2
	cmpa	#$E1
	bne	Main4
	jsr	rotate_right
Main4:
	jsr	delay_small
	bra	Main

* ========
* = Subs =
* ========

* saves buttons in buttons1 and buttons2
get_buttons:
	psha
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
	cmpb	buttons1l
	bne	get_buttons1
	clr	buttons1
	bra	get_buttons2
get_buttons1:
	stab	buttons1
	stab	buttons1l
get_buttons2:
	ldab	#$00
	jsr	Pad_RW
	comb
	cmpb	buttons2l
	bne	get_buttons3
	clr	buttons2
	bra	get_buttons4
get_buttons3:
	stab	buttons2
	stab	buttons2l
get_buttons4:
	jsr	Pad_En
	pula
	rts
	
	
delay_small:      pshx
                  ldx               #$0000
delay_small_1:    cpx               #$00
                  beq               delay_small_end
                  dex
                  bra               delay_small_1
delay_small_end:  pulx
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
	ldx	block_ptr
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

move_left_2:	ldx	block_ptr
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
	ldx	block_ptr
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

move_right_2:	ldx	block_ptr
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
	ldd	block_ptr
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
	
* ======= *
* = LCD = *
* ======= *

InitCurPointers:	pshd
	ldd	CursorInit
	std	CPointer
	std	CCPointer
	puld
	rts

;Draws Shape based on values in memory (void)	
DrawShape:	pshd
	pshx
	pshy
	jsr	ClearShape	;Clears Old shape
	ldd	CursorInit	
	addd	stage_block_ptr
	std	CCPointer	;Sets Cursor to correct location
	std	CPointer
	
	ldx	block_ptr	;pointer to memory
	
	ldaa	#Mwrite	;init memory write
	jsr	LCD_Command	

DrawShape1:	ldd	CPointer
	jsr	UpdateCursor
	ldaa	1,x-
	ldy	#8
DrawShape2:	lsla	
	bcs	Square
	dey
	bne	DrawShape2	
	ldd	CPointer
	xgdx
	dex
	xgdx
	std	CPointer
	TFR	x,d
	addd	#4
	cmpd	block_ptr
	bne	DrawShape1	
	puly
	pulx
	puld
	rts
	
;Clears old shape based on CCPointer which has old cursor position (void)	
ClearShape:	pshd
	pshx
	pshy
	ldd	CCPointer
	jsr	UpdateCursor	;Set Cursor to start of shape
	ldy	#4	
	ldaa	#Mwrite
	jsr	LCD_Command
ClearShape1:	ldaa	#$00
	ldx	#78
ClearShape2:	jsr	LCD_Data
	dex
	bne	ClearShape2
	dey	
	
	ldd	CCPointer
	xgdx
	dex	
	xgdx
	std	CCPointer
	jsr	UpdateCursor
	
	bne	ClearShape1
	bra	ClearShape_RTS
ClearShape_RTS:	puly
	pulx
	puld
	rts

;Requires D have cursor position (D)	
UpdateCursor:	pshd
	ldaa	#$46
	jsr	LCD_Command
	puld
	psha
	tba
	jsr	LCD_Data
	pula
	jsr	LCD_Data
	rts

;Draws single square within shape (void) *WORKING	
Square:	psha
	pshx
	ldx	#8
Square1:	ldaa	#$FF
	jsr	LCD_Data
	dex
	bne	Square1
	ldaa	#$00
	jsr	LCD_Data
	jsr	LCD_Data
	pulx
	pula
	rts

LCD_INIT:	
	psha
	pshx
	
	ldaa	#$FF
	staa	DDRG
	staa	DDRH
	staa
	
	ldaa	#$1F
	staa	PORTG	;Init PORTG
	
	BCLR	PORTG,BIT_0	;RESET LOW
	
;***************** Need 3ms Delay
	ldx	#$FFFF
LCD_INIT_LOOP1:	dex	
	bne	LCD_INIT_LOOP1	

	BSET	PORTG,BIT_0	;Reset Complete PORTG
	
	ldx	#$FFFF
LCD_INIT_LOOP2:	dex
	bne	LCD_INIT_LOOP2
	
	ldaa	#$58	;Turn off Display
	jsr	LCD_Command

*Init Setup	
	ldaa	#$40
	jsr 	LCD_Command
	ldaa	#$30	
	jsr	LCD_Data
	ldaa	#$87	;8-2 frame AC Drive 7 - Char Width FX
	jsr	LCD_Data
	ldaa	#$07	;Char Height FY
	jsr	LCD_Data
	ldaa	#$1F	;32 Diplay bites per line
	jsr	LCD_Data
	ldaa	#$23	;Total addr range per line TC/R (C/R+4 H-Blanking)
	jsr	LCD_Data
	ldaa	#$7F	; 128 diplay lines L/F
	jsr	LCD_Data
	ldaa	#$20	;Low Bite APL (Virtual Screen)
	jsr	LCD_Data
	ldaa	#$00	;High Bite APL (Virtual Screen)
	jsr	LCD_Data

*Scorll Settings	
	ldaa	#$44	;Set Scroll Command
	jsr	LCD_Command
	ldaa	#$00	;Layer 1 Start Address
	jsr	LCD_Data	;Lower byte
	ldaa	#$00
	jsr	LCD_Data	;High byte
	ldaa	#$7F	
	jsr	LCD_Data	;128 lines
	ldaa	#$00	;Layer 2 Start Address
	jsr	LCD_Data	;Lower byte
	ldaa	#$10	
	jsr	LCD_Data	;High byte
	ldaa	#$7F	
	jsr	LCD_Data	;128 lines
	ldaa	#$00
	jsr	LCD_Data	;Layer 3 Start Address
	ldaa	#$20
	jsr	LCD_Data	;High byte
	ldaa	#$7F
	jsr	LCD_Data	;128 lines

*Horizonal Scroll Set	
	ldaa	#$5A	;Horizonal Scroll CMD
	jsr	LCD_Command
	ldaa	#$00	;At Origin on X
	jsr	LCD_Data
*Overlay Settings	
	ldaa	#$5B
	jsr	LCD_Command	;Overlay CMD
	ldaa	#$1C
	jsr	LCD_Data	;3 layers, Graphics,OR layers

*Set Cursor increment to increment for memory clear	
	ldaa	#$4C	;Curser auto inc AP+1
	jsr	LCD_Command
	
*Set Cursor location
	ldaa	#$46
	jsr	LCD_Command	;Set Cursor
	clra
	jsr	LCD_Data	;to 0000h
	clra
	jsr	LCD_Data


*Clear Memeory
	ldx	#$0000
	ldaa	#$42
	jsr	LCD_Command
	
INIT_L2_RAM:	ldaa	#$00	;Zero
	jsr	LCD_Data
	inx	
	cpx	#$3000
	bne	INIT_L2_RAM
	
*Set Cursor increment to increment for program	
	ldaa	#$4F	;Curser auto inc AP+1
	jsr	LCD_Command
	
*Turn on Display	
	ldaa	#$59
	jsr	LCD_Command	;Display On
	ldaa	#%00010100	;Layer 1,2 on layer 3,4, curser off
	jsr	LCD_Data
*Set CGRAM
;	ldaa	#$5C
;	jsr	LCD_Command
;	ldaa	#$00
;	jsr	LCD_Data
;	ldaa	#$04
;	jsr	LCD_Data
	
	pulx
	pula
	rts

;PORTG
;bit0 - /Reset
;bit1 - /Read
;bit2 - /Write
;bit3 - /CS
;bit4 - A0
	
LCD_Command:
	pshb
	BSET	PORTG,BIT_4	;Set A0
	staa	PORTH	;Write Command
	BSET	PORTG,BIT_1	;Read disabled
	BCLR	PORTG,BIT_3	;CS enabled
	BCLR	PORTG,BIT_2	;Write enabled
	movb	#$FF,PORTG	;Restore PG
	pulb
	rts
	
LCD_Data:	
	pshb
	BCLR	PORTG,BIT_4	;Clear A0
	staa	PORTH	;Write Data
	BSET	PORTG,BIT_1	;Read disabled
	BCLR	PORTG,BIT_3	;CS enabled
	BCLR	PORTG,BIT_2	;Write enabled
	movb	#$FF,PORTG	;Restore PG
	pulb
	rts

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

STR_test:	fcc	"Test!"
	fcb	10,13,0
* ===========
* = Vectors =
* ===========
