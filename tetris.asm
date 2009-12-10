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

TIOS	equ	$0880	;In/Out
TCNT	equ	$0884	;CNT High
TSCR	equ	$0886	;Control
TMSK1	equ	$088C	;Enable flag
TMSK2	equ	$088D	;prescaler
TFLG1	equ	$088E	;Flags
TC1	equ	$0892	;CNT Set
TC2	equ	$0894

BIT_0	equ	1	;/RESET
BIT_1	equ	2	;/READ
BIT_2	equ	4	;/WRITE
BIT_3	equ	8	;/CS
BIT_4	equ	16	;A0

CursorInit	equ	$0005	;Initial Condition for LCD stage

Mwrite	equ	$42	;Memory write command for LCD

all_block_hght	equ	112

* =============
* = Variables =
* =============

	org	$00
* cursor pointers used to define location on screen	
CPointer	rmb	2	;Pointer for current block
CCPointer	rmb	2	;Pointer for clearning current block
CSPointer	rmb	2	;Pointer for stage
CHPointer	rmb	2	;Pointer for header
* Score memory for game
Score	rmb	1
* define memory range to store the stage in.
* stage = all unmovable pixels
stage_beg	rmb	16
stage_end	rmb	1

* points to the bottom memory location that defines
* the block shape
block_ptr	rmb	2

* it's the block height
block_height	rmb	1

* L D R U Start _ _ Select
buttons1	rmb	1

* Square X O /\ R1 L1 R2 L2
buttons2	rmb	1

* saves last button configs
buttons1l	rmb	1
buttons2l	rmb	1

* offset from top of the stage, downwards
stage_block_ptr	rmb 2

* FF if vertical collision detected
collision	rmb	1
game_over	rmb	1

temp	rmb	2
shift_offset	rmb	1
rot_offset	rmb	1
cur_block_id	rmb	1

* save state information here
sav_block_ptr	rmb	2
sav_shft_offset	rmb	1
sav_rot_offset	rmb	1

	org	$1000
* ========
* = Init =
* ========
Init:	
	cli
	jsr	SPI_INIT
	jsr	Var_Init
	jsr	LCD_INIT
	jsr	InitCurPointers
	jsr	InitStage
	jsr	InitTimer

	bra	Main

*Init SPI
SPI_INIT:
	ldab	DDRS	*Load Current state of DDRS
	orab	#%11100000	*Define output ports for Port S
	stab	DDRS	*store
	ldab	#%01011101	*Enable SPI
	stab	SP0CR1
	ldab	#%00000110	* set rate to 64kHz
	stab	SP0BR
	ldab	PORTS	
	orab	#$80
	stab	PORTS
	rts
* initialize variables here
Var_Init:	ldaa	#4
	clr	buttons1l
	clr	buttons2l
	staa	block_height
	ldaa	#128
	staa	rot_offset
	clr     	shift_offset
	clr	Score
	ldaa	#$FF
	staa	stage_end
	clr	game_over
	rts

* initialize timer subsystem
InitTimer:
	ldd	#$FFFF
	std	TC1
	ldd	#$0FFF
	std	TC2
	ldaa	#$07
	staa	TMSK2
	ldaa	#$06	;TC1, TC2 Timer
	staa	TIOS
	ldaa	#$80	;Enable Timer
	staa	TSCR
	ldaa	#$06	;TC1 - EN, TC2 - EN
	staa	TMSK1
	rts

* draw up the stage
InitStage:	
	jsr	DrawStageBounds
	jsr	ScoreBoard
	jsr	determine_block
	jsr 	serve_block
	jsr	DrawShape
	rts
		
* ========
* = Main =
* ========
Main:
	jsr	get_buttons

* check for down button
	ldaa	buttons1
	anda	#$40
	beq	Main0
	sei
Main0_1:
	jsr	move_down
	ldaa	collision
	bne	Main0_2
	bra	Main0_1
Main0_2:
	cli
	bra	MainE

Main0:	
* check for left button
	ldaa	buttons1
	anda	#$80
	beq	Main1
	jsr	check_hcol_l
	ldaa	collision
	bne	MainE
	jsr	move_left
	dec     	shift_offset
	bra	MainE
Main1:
* check for right button
	ldaa	buttons1
	anda	#$20
	beq	Main2
	jsr	check_hcol_r
	ldaa	collision
	bne	MainE
	jsr	move_right
	inc	shift_offset
	bra	MainE
Main2:
	
	
* check for rotate left (square)
	ldaa	buttons2
	anda	#$80
	beq	Main3
	jsr	save_state
	jsr	rotate_left
	jsr	check_rcol
	ldaa	collision
	bne	Main2_1
	bra	MainE
Main2_1:
	jsr	revert_state
	bra	MainE
Main3:
* check for rotate right (X)
	ldaa	buttons2
	anda	#$40
	beq	Main4
	jsr	save_state
	jsr	rotate_right
	jsr	check_rcol
	ldaa	collision
	bne	Main3_1
	bra	MainE
Main3_1:
	jsr	revert_state
	bra	MainE

Main4:
* check for Pause (Start button )
	ldaa	buttons1
	anda	#$08
	beq	MainE
	sei
Main4_1:
	jsr	get_buttons
	ldaa	buttons1
	anda	#$08
	beq	Main4_1
	bra	Main4_2
	
Main4_2:	cli
	bra	MainE
MainE:
* reset collision byte. It's a new dawn!
	clr 	collision
	lbra	Main

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

	
* ==================
* = Button actions =
* ==================

* shift block left
move_left:
	psha
	pshx
	pshb
	ldx	block_ptr
	ldab	block_height
move_left_1:
	ldaa	0,x
	lsla
	staa    	0,x
 	dex
	decb
	beq	move_left_end
	bra	move_left_1
move_left_end:
	pulb
	pulx
	pula
	rts

* shift the block right
move_right:
	psha
	pshx
	pshb
	ldx	block_ptr
	ldab	block_height
move_right_1:
	ldaa	0,x
	lsra
	staa   	0,x
	dex
	decb
	beq	move_right_end
	bra	move_right_1
move_right_end:
	pulb
	pulx
	pula
	rts

rotate_left:
	pshx
	pshb
	inc	rot_offset
	ldab	cur_block_id
	jsr	serve_block
	pulb
	pulx
	rts
	
rotate_right:
	pshx
	pshb
	dec	rot_offset
	ldab	cur_block_id
	jsr 	serve_block
	pulb
	pulx
	rts

move_down:	ldx	block_ptr	
	jsr	check_vcol
	ldaa	collision
	cmpa	#$FF
* if we have a collision, merge block into the stage.
* else increment stage block pointer
	beq	move_down_2
	ldd     	stage_block_ptr
	incb
	std     	stage_block_ptr
	bra	move_down_end
move_down_2:
	jsr	merge_blk2stg
 	jsr	clr_fl_rws
	jsr     	DrawStage
	jsr	check_gameover
	ldaa	game_over
	beq	move_down_3
	jsr	show_gameover
move_down_3
	jsr	determine_block
	jsr	serve_block
move_down_end:
	rts
	
	
	
show_gameover:

	bra	show_gameover
* ===================
* = Game Logic subs =
* ===================


check_gameover:
	pshx
	psha
	ldx	#stage_beg
	ldaa	0,x
	anda	#$00
	beq	check_gameover_e
	ldaa	#$FF
	staa	game_over
check_gameover_e:
	pula
	pulx
	rts

clr_fl_rws:
	pshx
	psha
* start at the end of the stage
	ldx	#stage_end
	dex
clr_fl_rws_0:
* see if the current row is full
	ldaa	0,x
	cmpa	#$FF
* if not, move on, else, do some stuff
	bne	clr_fl_rws_1
* transfer X to Y and work with it for the internal loop
	pshx
	pshd
	xgdx
	xgdy
	puld
	pulx
* also increase the score
	jsr     Score_Inc
clr_fl_rws_01:
* take the previous row and overwrite the current row with it
	ldaa	-1,y
	staa	0,y
	dey
* if we're at the top of the stage, exit this loop.
* otherwise, keep moving lines down
	cpy	#stage_beg
	beq     clr_fl_rws_11
	bra	clr_fl_rws_01
clr_fl_rws_1:
* now move up to the next line and start the process over,
* until we arrive at the beginning of the stage.
	dex
clr_fl_rws_11:
	cpx	#stage_beg
	beq	clr_fl_rws_end
	bra	clr_fl_rws_0
clr_fl_rws_end:
	pula
	pulx
	rts

merge_blk2stg:
	pshx
	pshy
	pshd
	ldab	block_height
	ldy	stage_block_ptr
	leax	stage_beg,Y
	ldy	block_ptr
merge_blk2stg_1:
	ldaa	0,x
	oraa	0,y
	staa	0,x
	dex
	dey
	decb	
	bne	merge_blk2stg_1
	puld
	puly
	pulx
	rts


determine_block:
	jsr	rst_van_blks
	ldaa	#128
	staa	rot_offset
	clr     	shift_offset
	ldd	TCNT
	ldx	#7
	idiv
* now we have a number from 0-4 in D/B
;	ldab    #01
	stab	cur_block_id
	pshb
	ldd	#$4
	std	stage_block_ptr
	pulb
	rts

* serve the block with ID given in B
serve_block:
* shift the block back to initial position. Then, later, we
* move it forward again to the right spot.
* 
	ldaa	shift_offset
serve_block_1:
	cmpa	#00
	beq	serve_block_2
	jsr	move_left
	deca
	bra	serve_block_1
serve_block_2:
* this is the number of bytes per block to calc offset.
* it lands us at the right block type.
	ldaa	#16
	mul
* now we have the offset from the first block in D
	std	temp
	
* get rotation offset. Result will be one of [0-3].
	clrb
	ldab	rot_offset
	ldx	#4
	idiv
* now we know which rotation. Multiply by 4 to get number
* of bytes
	ldaa	#4
	mul
	addd	temp
	ldx	#BLK_squareU
	inx
	inx
	inx
	leax	d,x
* now we have a random block in X
 	stx	block_ptr

* now shift the block back right
	ldaa    	shift_offset
serve_block_3:
	cmpa	#00
	beq	serve_block_4
	jsr	move_right
	deca
	bra	serve_block_3
serve_block_4:
	rts



rst_van_blks:
	ldx	#BLK_squareU
	ldy	#BLK_van_squareU
	ldab	#all_block_hght
rst_van_blks_1:
	ldaa	0,y
	staa	0,x
	inx
	iny
	decb
	bne	rst_van_blks_1
	rts


save_state:
	pshx
	psha
	ldx	block_ptr
	stx	sav_block_ptr
	ldaa	shift_offset
	staa	sav_shft_offset
	ldaa	rot_offset
	staa	sav_rot_offset
	pula
	pulx
	rts
	
revert_state:
	pshx
	pshd
	ldab    	block_height
	ldx     	block_ptr
	leax	all_block_hght,x
	ldy     	block_ptr
revert_state_11
	ldaa    	0,x
	staa    	0,y
	dex
	dey
	decb
	bne     	revert_state_11
	
	ldx     	sav_block_ptr
	stx	block_ptr
	ldaa	sav_shft_offset
	staa	shift_offset
	ldaa	sav_rot_offset
	staa	rot_offset
	ldaa    	shift_offset
revert_state_1:
	cmpa	#0
	beq	revert_state_2
	jsr	move_right
	deca
	bra	revert_state_1
	
revert_state_2:
	puld
	pulx
	rts

check_rcol:
	pshx
	psha
	pshb
* first, check if the rotation cut off the block.
* to do that, we move it left and compare it with
* vanilla. If it's the same, we're good and move on 
* to stage collision check.
	ldaa	shift_offset
check_rcol_1:
	cmpa	#0
	beq	check_rcol_2
	jsr	move_left
	deca
	bra     	check_rcol_1
check_rcol_2:
	ldx	block_ptr
	ldy     	block_ptr
	leay	all_block_hght,y
	ldaa	block_height
check_rcol_3
	ldab	0,x
	eorb	0,y
	bne	check_rcol_col
	dex
	dey
	deca
	beq	check_rcol_5
	bra	check_rcol_3

* at this point we know the block isn't cut off, so
* check the stage
check_rcol_5:
	ldaa	shift_offset
check_rcol_6:
	cmpa	#0
	beq	check_rcol_7
	jsr	move_right
	deca
	bra     	check_rcol_6
check_rcol_7:
	ldab	block_height
	ldx	block_ptr
	ldy	stage_block_ptr
	leay	stage_beg,y
check_rcol_8:
	ldaa	0,x
	anda	0,y
	bne	check_rcol_col
	dex
	dey
	decb
	beq	check_rcol_e
	bra	check_rcol_8
check_rcol_col:
	jsr	set_collision
check_rcol_e:
	pulb
	pula
	pulx
	rts

* check for horizontal collision left
check_hcol_l:
	pshx
	pshy
	pshd
	ldab	block_height
	ldx	block_ptr
check_hcol_l1:
* first make sure if any line of the block
* already occupies bit 7
	ldaa	0,x
	anda	#$80
	bne	check_hcol_lcol
	dex
	decb
	beq	check_hcol_l2
	bra	check_hcol_l1
* now that we checked bit 7, check collision
* with the stage.
check_hcol_l2:
	ldab	block_height
	ldx	block_ptr
	ldy	stage_block_ptr
	leay	stage_beg,y
check_hcol_l3:
	ldaa	0,x
	lsla
	anda	0,y
	bne	check_hcol_lcol
	dex
	dey
	decb
	beq	check_hcol_lend
	bra	check_hcol_l3
check_hcol_lcol:
	jsr	set_collision
check_hcol_lend:
	puld
	puly
	pulx
	rts


* check for horizontal collision right
check_hcol_r:
	pshx
	pshy
	pshd
	ldab	block_height
	ldx	block_ptr
check_hcol_r1:
* first make sure if any line of the block
* already occupies bit 0
	ldaa	0,x
	anda	#$01
	bne	check_hcol_rcol
	dex
	decb
	beq	check_hcol_r2
	bra	check_hcol_r1
* now that we checked bit 7, check collision
* with the stage.
check_hcol_r2:
	ldab	block_height
	ldx	block_ptr
	ldy	stage_block_ptr
	leay	stage_beg,y
check_hcol_r3:
	ldaa	0,x
	lsra
	anda	0,y
	bne	check_hcol_rcol
	dex
	dey
	decb
	beq	check_hcol_rend
	bra	check_hcol_r3
check_hcol_rcol:
	jsr	set_collision
check_hcol_rend:
	puld
	puly
	pulx
	rts


* checks for vertical collisions 
check_vcol:
	psha
	pshb
	pshx
	pshy
	ldab	block_height
* x will keep track of the block line
	ldx	block_ptr
* y will keep track of the stage line
	ldy	stage_block_ptr
	leay    	stage_beg,y
check_vcol1:
* look ahead one row
	ldaa	1,y
* and it with the current line of the block
	anda	0,x
* if we don't get 0, we have a collision
	bne	check_vcol_col
	dex
	dey
	decb
	bne	check_vcol1
	bra	check_vcol_end
check_vcol_col:
	jsr	set_collision
	
check_vcol_end:	
	puly
	pulx
	pulb
	pula
	rts	


set_collision:
	ldaa	#$FF
	staa	collision	
 	rts

* ========= *
* = Score = *
* ========= *

Score_Inc:	pshb
	ldab    Score
	addb	#3
	stab	Score
	pulb
	jsr     ScoreBoard
	rts
	
Score_Rst:	pshb
	ldab	#0
	stab	Score
	pulb
	jsr     ScoreBoard
	rts

ScoreBoard:	pshd
	pshx
	pshy
	ldd	#$1001	;Set cursor to beginning of line
	std	CHPointer	
	jsr	UpdateCursor
;Clears Line	
	ldaa	#Mwrite
	jsr	LCD_Command
	ldx	#$7F
ScoreBoard1:	ldaa	#$00	;Clear line loop
	jsr	LCD_Data
	dex
	bne	ScoreBoard1

	ldd	CHPointer	;Set Cursor Back to beginning of line
	jsr	UpdateCursor
;Hex to Decimal	
	ldab	Score
	clra
	
	ldx	#10
	idiv
	ldy	#NumTbl
	leay	d,y
	jsr	DrawScore
	
	xgdx	
	ldx	#10
	idiv	
	ldy	#NumTbl
	leay	d,y
	jsr	DrawScore
	
	xgdx
	ldy	#NumTbl
	leay	d,y
	jsr	DrawScore
	
	puly
	pulx
	puld
	rts

DrawScore:	pshx
	ldx	d,y	;ldx with top memory address of CG number
	pshd
	ldaa	#Mwrite
	jsr	LCD_Command
	ldy	#8
DrawScore1:	ldaa	1,x+
	jsr	LCD_Data
	dey
	bne	DrawScore1
	puld
	pulx
	rts
	
* ======= *
* = LCD = *
* ======= *

InitCurPointers:	pshd
	ldd	#CursorInit
	std	CPointer
	addd    #3
	std	CCPointer
	puld
	rts

;Draws Shape based on values in memory (void)	
DrawShape:	pshd
	pshx
	pshy
	jsr	ClearShape	;Clears Old shape
	ldd	#CursorInit
	addd	stage_block_ptr
	std	CCPointer	;Sets Cursor to correct location
	addd	#$0400
	std	CPointer
	
	ldx	block_ptr	;pointer to memory
	

DrawShape1:	ldd	CPointer
	jsr	UpdateCursor
        	ldaa	#Mwrite	;init memory write
	jsr	LCD_Command
	ldaa	1,x-
	ldy	#8
DrawShape2:	lsra

	bcs     	DrawShape3
	jsr	Blank
	bra     	DrawShape4
DrawShape3:     	jsr 	Square
	bra	DrawShape4
DrawShape4:	dey
	bne	DrawShape2	
	ldd	CPointer
	xgdx
	dex
	xgdx
	std	CPointer
	TFR	x,d
	addd	#4
	cpd	block_ptr
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
ClearShape1:    ldaa	#Mwrite
	jsr	LCD_Command
	ldaa	#$00
	ldx	#$7F
ClearShape2:	jsr	LCD_Data
	dex
	bne	ClearShape2

	
	ldd	CCPointer
	xgdx
	dex	
	xgdx
	std	CCPointer
	jsr	UpdateCursor
	
	dey
	bne	ClearShape1
	puly
	pulx
	puld
	rts
	
DrawStageBounds:	pshx
	pshy
	pshd
	ldd	#CursorInit	;Load Starting Cursor Point on LCD for stage
	addd	#$1000
	xgdx
	
	TFR	x,d
	jsr	UpdateCursor
	ldaa	#Mwrite	;Draw divide line between score board and stage
	jsr	LCD_Command
	ldaa	#%10111101
	ldy	#$7F
DrawStageBounds1:	jsr	LCD_Data
	dey
	bne	DrawStageBounds1

	TFR	x,d
	addd	#17
	jsr	UpdateCursor
	ldaa	#Mwrite
	jsr	LCD_Command
	ldaa	#%01011101
	ldy	#$7F
DrawStageBounds2:	jsr	LCD_Data
	dey
	bne	DrawStageBounds2
	
	ldaa	#$4C	;Curser auto inc AP+1
	jsr	LCD_Command
	
	TFR	x,d
	addd	#$03C1
	jsr	UpdateCursor
	ldaa	#Mwrite
	jsr	LCD_Command
	ldy	#16
DrawStageBounds3:	ldaa	#$FF
	jsr	LCD_Data
	dey
	bne	DrawStageBounds3
	
	TFR	x,d
	addd	#$0C21
	jsr	UpdateCursor
	ldaa	#Mwrite
	jsr	LCD_Command
	ldy	#16
DrawStageBounds4:	ldaa	#$FF
	jsr	LCD_Data
	dey
	bne	DrawStageBounds4
	
	ldaa	#$4F	;Curser auto inc AP+1
	jsr	LCD_Command
	
	puld
	puly
	pulx
	rts
	
DrawStage:	pshx
	pshy
	pshd
	ldd	#CursorInit	;Load Starting Cursor Point on LCD for stage
	addd	#$1401
	std	CSPointer	;Set CSPointer to top of stage	
	
	
	ldx	#stage_beg
DrawStage2:	ldd	CSPointer	;Update LCD Cursor for drawing blocks on stage
	jsr	UpdateCursor
	ldaa    	#Mwrite
	jsr    	LCD_Command
	ldy	#8
	ldaa	1,x+
DrawStage3:	lsra
	bcs	DrawStage4	;Draw Each block on stage
	jsr	Blank
	bra	DrawStage5
DrawStage4:	jsr	Square
	bra	DrawStage5
DrawStage5:	dey
	bne	DrawStage3
	ldd	CSPointer
	xgdx
	inx
	xgdx
	std	CSPointer
	cpx	#stage_end
	bne	DrawStage2
	puld
	puly
	pulx
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
	pulx
	pula
	rts
	
Blank:	psha
	pshx
	ldx	#8
Blank1:	ldaa	#$00
	jsr	LCD_Data
	dex
	bne	Blank1
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
	
	bclr	PORTG,BIT_0	;RESET LOW
	
;***************** Need 3ms Delay
	ldx	#$FFFF
LCD_INIT_LOOP1:	dex	
	bne	LCD_INIT_LOOP1	

	bset	PORTG,BIT_0	;Reset Complete PORTG
	
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
	bset	PORTG,BIT_4	;Set A0
	staa	PORTH	;Write Command
	bset	PORTG,BIT_1	;Read disabled
	bclr	PORTG,BIT_3	;CS enabled
	bclr	PORTG,BIT_2	;Write enabled
	movb	#$FF,PORTG	;Restore PG
	pulb
	rts
	
LCD_Data:	
	pshb
	bclr	PORTG,BIT_4	;Clear A0
	staa	PORTH	;Write Data
	bset	PORTG,BIT_1	;Read disabled
	bclr	PORTG,BIT_3	;CS enabled
	bclr	PORTG,BIT_2	;Write enabled
	movb	#$FF,PORTG	;Restore PG
	pulb
	rts

* ========
* = ISRs =
* ========

* this ISR moves the block down one space periodically
ISR_Timer1:
	pshd
	pshx
	pshy
	pshc			
 	jsr	move_down	;******************Currently does not inc stage_block_ptr
	jsr	DrawShape
	ldaa	TFLG1
	anda	#$02	;Reset Flag
	staa	TFLG1
	pulc
	puly
	pulx
	puld
	rti
	
ISR_Timer2:	pshd
	pshx
	pshy
	pshc
	jsr	DrawShape
	ldd	TCNT
	addd	#$0FFF
	std	TC2
	ldaa	TFLG1
	anda	#$04
	staa	TFLG1
	pulc
	puly
	pulx
	puld
	rti

	
* ==========
* = Blocks =
* ==========
BLK_squareU	fcb	$C0,$C0,0,0
BLK_squareL	fcb	$C0,$C0,0,0
BLK_squareD	fcb	$C0,$C0,0,0
BLK_squareR	fcb	$C0,$C0,0,0
BLK_teeU	fcb	$40,$E0,0,0
BLK_teeL	fcb	$40,$C0,$40,0
BLK_teeD	fcb	$E0,$40,0,0
BLK_teeR	fcb	$80,$C0,$80,0
BLK_longU	fcb	$F0,0,0,0
BLK_longL	fcb	$80,$80,$80,$80
BLK_longD	fcb	$F0,0,0,0
BLK_longR	fcb	$80,$80,$80,$80
BLK_ZU	fcb	$C0,$60,0,0
BLK_ZL	fcb	$40,$C0,$80,0
BLK_ZD	fcb	$C0,$60,0,0
BLK_ZR	fcb	$40,$C0,$80,0
BLK_ZiU	fcb	$60,$C0,0,0
BLK_ZiL	fcb	$80,$C0,$40,0
BLK_ZiD	fcb	$60,$C0,0,0
BLK_ZiR	fcb	$80,$C0,$40,0
BLK_LU	fcb	$E0,$80,0,0
BLK_LL	fcb	$80,$80,$C0,0
BLK_LD	fcb	$20,$E0,0,0
BLK_LR	fcb	$C0,$40,$40,0
BLK_LiU	fcb	$E0,$20,0,0
BLK_LiL	fcb	$C0,$80,$80,0
BLK_LiD	fcb	$80,$E0,0,0
BLK_LiR	fcb	$40,$40,$C0,0


* vanilla blocks. we never touch those.
BLK_van_squareU	fcb	$C0,$C0,0,0
BLK_van_squareL	fcb	$C0,$C0,0,0
BLK_van_squareD	fcb	$C0,$C0,0,0
BLK_van_squareR	fcb	$C0,$C0,0,0
BLK_van_teeU	fcb	$40,$E0,0,0
BLK_van_teeL	fcb	$40,$C0,$40,0
BLK_van_teeD	fcb	$E0,$40,0,0
BLK_van_teeR	fcb	$80,$C0,$80,0
BLK_van_longU	fcb	$F0,0,0,0
BLK_van_longL	fcb	$80,$80,$80,$80
BLK_van_longD	fcb	$F0,0,0,0
BLK_van_longR	fcb	$80,$80,$80,$80
BLK_van_ZU	fcb	$C0,$60,0,0
BLK_van_ZL	fcb	$40,$C0,$80,0
BLK_van_ZD	fcb	$C0,$60,0,0
BLK_van_ZR	fcb	$40,$C0,$80,0
BLK_van_ZiU	fcb	$60,$C0,0,0
BLK_van_ZiL	fcb	$80,$C0,$40,0
BLK_van_ZiD	fcb	$60,$C0,0,0
BLK_van_ZiR	fcb	$80,$C0,$40,0
BLK_van_LU	fcb	$E0,$80,0,0
BLK_van_LL	fcb	$80,$80,$C0,0
BLK_van_LD	fcb	$20,$E0,0,0
BLK_van_LR	fcb	$C0,$40,$40,0
BLK_van_LiU	fcb	$E0,$20,0,0
BLK_van_LiL	fcb	$C0,$80,$80,0
BLK_van_LiD	fcb	$80,$E0,0,0
BLK_van_LiR	fcb	$40,$40,$C0,0
	
* ================== */
* = LCD CHAR TABLE = */
* ================== */


Zero:	fcb	$00
	fcb	$00
	fcb	$7C	;01111100
	fcb	$A2	;10100010
	fcb	$92	;10010010
	fcb	$8A	;10001010
	fcb	$7C	;01111100
	fcb	$00
	
One:	fcb	$00
	fcb	$00
	fcb	$00
	fcb	$01
	fcb	$FE
	fcb	$42
	fcb	$00
	fcb	$00
	
Two:	fcb	$00
	fcb	$00
	fcb	$42
	fcb	$A2
	fcb	$92
	fcb	$8A
	fcb	$46
	fcb	$00
	
Three:	fcb	$00
	fcb	$00
	fcb	$8C
	fcb	$D2
	fcb	$A2
	fcb	$82
	fcb	$84
	fcb	$00
	
Four:	fcb	$00
	fcb	$00
	fcb	$08
	fcb	$FE
	fcb	$48
	fcb	$28
	fcb	$18
	fcb	$00
	
Five:	fcb	$00
	fcb	$00
	fcb	$9C
	fcb	$A2
	fcb	$A2
	fcb	$A2
	fcb	$E4
	fcb	$00
	
Six:	fcb	$00
	fcb	$00
	fcb	$0C
	fcb	$92
	fcb	$92
	fcb	$52
	fcb	$3C
	fcb	$00
	
Seven:	fcb	$00
	fcb	$00
	fcb	$C0
	fcb	$A0
	fcb	$90
	fcb	$8E
	fcb	$80
	fcb	$00
	
Eight:	fcb	$00
	fcb	$00
	fcb	$6C
	fcb	$92
	fcb	$92
	fcb	$92
	fcb	$6C
	fcb	$00
	
Nine:	fcb	$00
	fcb	$00
	fcb	$78
	fcb	$94
	fcb	$92
	fcb	$92
	fcb	$60
	fcb	$00
	
	org	$2500
NumTbl:	fdb	#Zero,#One,#Two,#Three,#Four,#Five,#Six,#Seven,#Eight,#Nine

* ===========
* = Vectors =
* ===========
	org	$62c
	fdb	ISR_Timer1
	
	org	$62a
	fdb	ISR_Timer2
