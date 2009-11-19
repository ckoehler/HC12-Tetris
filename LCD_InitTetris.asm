PORTG	equ	$0828	;Expanded Address of Command
DDRG	equ	$082A
PORTH	equ	$0829	;Expanded Address of Data
DDRH	equ	$082B

BIT_0	equ	1	;/RESET
BIT_1	equ	2	;/READ
BIT_2	equ	4	;/WRITE
BIT_3	equ	8	;/CS
BIT_4	equ	16	;A0

	org	$1000
	
	jsr	LCD_INIT
	jsr	Square
	swi
	
Square:	psha
	pshx
	ldaa	#$46
	jsr	LCD_Command
	ldaa	#$00
	jsr	LCD_Data
	ldaa	#$00
	jsr	LCD_Data
	
	ldaa	#$42
	jsr	LCD_Command
	ldx	#8
Square1:	ldaa	#$FF
	jsr	LCD_Data
	dex
	bne	Square1
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
	
	ldaa	#$4F	;Curser auto inc AP+1
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
	
*Turn on Display	
	ldaa	#$59
	jsr	LCD_Command	;Display On
	ldaa	#%01010100	;Layer 1,2 on layer 3,4, curser off
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
	