;
;
        LIST            P=PIC12f675
        ERRORLEVEL      -302    ;SUPPRESS BANK SELECTION MESSAGES
        __CONFIG        01192H   ;XT OSC, WATCHDOG
;
INCLUDE P12F675.INC
;
;THE CONSTANTS
DEBNC_REL	EQU	02H
BEEP_LEN	EQU	02H	;beep length
;    
;
; define the bits in GPIO
VIDEO		EQU	0
M_LINE		EQU	0
BEEP		EQU	1
R_KEY		EQU	2
L_KEY		EQU	3
HIT		EQU	4
L2R		EQU	5
T2B		EQU	6
W_REQ		EQU	7
DO_IT		EQU	0
R_OUT		EQU	1
L_OUT		EQU	2
FIN		EQU	3
PLYR_2		EQU	4
FAST		EQU	5
;
; define the bytes
N_LINE		EQU	020H	;line counter in a block
CNT_1		EQU	021H	;short distance counter
X_POS		EQU	022H	;X location of the ball
Y_POS		EQU	023H	;Y location of the ball
Y_LINE		EQU	024H	;line pair number in the game field
BITS_1		EQU	025H	;(W_REQ,T2B,L2R,HIT,L_KEY,R_KEY,BEEP,M_LINE)
Y_L		EQU	026H	;y location of left bat
Y_L_OLD		EQU	027H	;previous y location of left bat
Y_R		EQU	028H	;y location of right bat
Y_R_OLD		EQU	029H	;previous y location of right bat
BCNT_1		EQU	02AH	;beep counter 1 (low)
BCNT_2		EQU	02BH	;beep counter 2 (high)
DEBNC_L		EQU	02CH	;key debounce counter left
DEBNC_R		EQU	02DH	;key debounce counter right
AD_L_OLD	EQU	02EH	;direct old AD value of left bat
AD_R_OLD	EQU	02FH	;direct old AD value of right bat
SPEED_R		EQU	030H	;speed of right bat
SPEED_L		EQU	031H	;speed of left bat
Y_BALL		EQU	032H	;y position of ball (changed by line_game)
X_BALL		EQU	033H	;x position of ball (changed by line_game)
LENGTH_R	EQU	034H	;length of right bat
X_SPEED		EQU	035H	;frame counter for X increment
Y_SPEED		EQU	036H	;frame counter for Y increment
SAVE_S		EQU	037H	;save byte for STATUS during synchronous part
SAVE_W		EQU	038H	;save byte for W during synchronous part
LFT_CHAR	EQU	039H	;temp for left character
RGT_CHAR	EQU	03AH	;temp for right character
SCORE		EQU	03BH	;temp byte for core
OLD_HIGH	EQU	03CH	;high score
LFT_SCR		EQU	03DH	;left score
RGT_SCR		EQU	03EH	;right score 
ADR_EE		EQU	03FH	;text pointer
ADR_TAB		EQU	040H	;temp for text routine
W_ADR		EQU	041H	;address for write in EEPROM
W_DAT		EQU	042H	;data for write in EEPROM
BITS_2		EQU	043H	;..,..,FAST,PLYR_2,FIN,L_OUT,R_OUT,DO_IT
SPEED		EQU	044H	;Speed preset value
CNT_2		EQU	045H	;counter in the asynchronous part
;
;
		org	0000H
		goto	init
;
		org	0004H
		goto	sync_blck
;
; initialize special function registers (machine parameters)
init:		bsf	STATUS,RP0	;bank 1
		movlw	032H		;only AN1 and AN2 are inputs (36H)
		movwf	TRISIO		;
		movlw	022H		;clock/32, AN1 and AN2 are analog (26H)
		movwf	ANSEL		;
		clrf	VRCON		;reference voltage off
		movlw	0D8H		;tmr0 internal clock, no prescaler
		movwf	OPTION_REG	;	
		bcf	STATUS,RP0	;bank 0
		clrf 	GPIO		;clear GPIO
		movlw	009H		;init ADCON0/left just./VDD=ref
		movwf	ADCON0		;AN1=input/converter on
		movlw	007H		;
		movwf	CMCON		;comparator off
; initialize general purpose registers (program parameters)
		bsf	BITS_1,M_LINE	;middle line on
		movlw	003H		;tables are in the upper 256 bytes
		movwf	PCLATH		;
		movlw	0AH		;y location left bat
		movwf	Y_L		;
		movwf	Y_R		;
		movlw	DEBNC_REL	;key debounce counters		
		movwf	DEBNC_L		;
		movwf	DEBNC_R		;
		clrf	BCNT_1		;beep length
		movlw	BEEP_LEN	;	
		movwf	BCNT_2		;
		bcf	BITS_1,BEEP	;
		movlw	0F0H		;
		movwf	LENGTH_R	;	
		bsf	INTCON,GIE	;global interrupt enable [1]
		bcf	BITS_1,W_REQ
		bcf	BITS_2,DO_IT
		movlw	SPEED
		movwf	X_SPEED
		movwf	Y_SPEED
		bcf	BITS_1,L_KEY
		bcf	BITS_1,R_KEY
		bcf	BITS_2,R_OUT
		bcf	BITS_2,L_OUT
		bsf	BITS_1,L2R
		movlw	020H
		movwf	SPEED
		bcf	BITS_2,FAST
;
;read the status of the switch at input 3 to see if we have a one or
;two player game
		bcf	BITS_2,PLYR_2	;default one player
		btfsc	GPIO,3		;test GPIO,3
		bsf	BITS_2,PLYR_2	;if 1 then one player
;	
;This call starts the synchronous subroutine. 
;The function of this routine is to generate the video signal, 
;To read the controls and the move the ball.
;A special part of the display area, located in the upper left corner 
;of the display is used to perform asynchronous tasks. By returning 
;to the asynchronous main program below.
;Before the return, it sets timer0 to generate an interrupt to be back in
;time.
		call	sync_blck
;
;when we return from this routine, the routine has set timer0 so that
;when timer0 overflows, we automatically, through the interrupt vector, 
;return to the routine.	
;
;The following part is the "asynchronous" main program. It controls the game
;set the score, switches from one player to the other etc.
;
;clear all text just to be sure
		clrf	ADR_EE		;pointer to first character
		movlw	06H		;
		movwf	CNT_2		;
main_1:		movlw	046H		;load a blank
		call	write_char	;write to screen
		decfsz	CNT_2,1		;count down
		goto	main_1		;
;
;start the game
		movlw	0F9H		;F9 gives after an increment 00
		movwf	LFT_SCR		;F9+1=FA (A->0 en F+1=0) -> 00
		movwf	RGT_SCR		;
		btfss	BITS_2,PLYR_2	;if one player do not show left score
		goto	main_2		;
		movlw	000H		;display pointer to left score 
		movwf	ADR_EE		;
		movf	LFT_SCR,0	;clear left score
		call	inc_scr		;
		movwf	LFT_SCR		;
main_2:		movlw	004H		;display pointer to right score
		movwf	ADR_EE		;
		movf	RGT_SCR,0	;clear right score
		call	inc_scr		;
		movwf	RGT_SCR		;
		call	ball_inv	;ball to invisible position
main_3:		bsf	BITS_1,L2R	;ball moves left to right
		bcf	BITS_1,L_KEY	;reset left key
		movlw	02H		;arrow points left
		movwf	ADR_EE		;pointer to middle character group
		movlw	054H		;write left arrow
		call	write_char	;
		movlw	046H		;and a blank
		call	write_char	;
main_4:		btfss	BITS_1,L_KEY	;wait for left key
		goto	main_4		;
		bcf	BITS_1,L_KEY	;reset left key			
		bcf	BITS_1,R_KEY	;reset right key
		bsf	BITS_1,BEEP	;beep
		call	read_switch	;read the switch and adjust speed set
		movf	Y_L_OLD,0	;position ball to left bat
		addlw	0F8H		;center ball to bat
		movwf	Y_POS		;
		movlw	010H		;
		movwf	X_POS		;
		bcf	BITS_2,T2B	;ball moves top to bottom depending
		btfsc	SPEED_L,7	;on movement bat
		bsf	BITS_2,T2B	;
main_5:		bsf	BITS_2,DO_IT	;play game
		movlw	02H		;both arrows off
		movwf	ADR_EE		;pointer to first character group
		movlw	046H		;write two blanks
		call	write_char	;
		movlw	046H		;
		call	write_char	;
main_6:		btfsc	BITS_2,R_OUT	;test if the ball is right out
		goto	main_7		;if so goto main_7
		btfsc	BITS_2,L_OUT	;test if the ball is left out
		goto	main_12		;if so goto main_12
		goto	main_6		;keep on testing for ball out
main_7:		call	ball_inv	;ball to invisible position
		bcf	BITS_2,R_OUT	;reset out flag
		movlw	000H		;display pointer to first character
		movwf	ADR_EE		;group
		movf	LFT_SCR,0	;increment and display left score
		call	inc_scr		;
		movwf	LFT_SCR		;
		btfss	BITS_2,FIN	;test if score 50 is so skip
		goto	main_3		;if not left player is on the move
		movlw	02H		;write a W for left player
		movwf	ADR_EE		;pointer to left player
		movlw	05BH		;
		call	write_char	;
main_9:		goto	main_9		;infinte loop (wait for reset)
main_10:	btfss	BITS_2,PLYR_2	;skip if 2 player game		
		goto	main_3		;jump if single player game
		bcf	BITS_1,L2R	;ball moves right to left
		bcf	BITS_1,R_KEY	;reset right key
		movlw	02H		;arrow points right
		movwf	ADR_EE		;pointer to middle character group
		movlw	046H		;write blank
		call	write_char	;
		movlw	04D		;and an arrow right
		call	write_char	;
main_11:	btfss	BITS_1,R_KEY	;wait for right key
		goto	main_11		;
		bcf	BITS_1,R_KEY	;reset left key			
		bcf	BITS_1,L_KEY	;reset right key
		bsf	BITS_1,BEEP	;beep
		call	read_switch	;read the switch and adjust speed set
		movf	Y_R_OLD,0	;position ball to right bat
		addlw	0F8H		;adjust ball to center bat
		movwf	Y_POS		;
		movlw	051H		;
		movwf	X_POS		;
		bcf	BITS_2,T2B	;ball moves top to bottom depending
		btfsc	SPEED_R,7	;on movement bat
		bsf	BITS_2,T2B	;
		goto	main_5		;resume main branch		
main_12:	call	ball_inv	;ball to invisible position
		bcf	BITS_2,L_OUT	;reset out flag
		movlw	004H		;display pointer to right character
		movwf	ADR_EE		;group
		movf	RGT_SCR,0	;increment and display left score
		call	inc_scr		;
		movwf	RGT_SCR		;
		btfss	BITS_2,FIN	;test if score 50 is so skip
		goto	main_10		;if not right player is on the move
		movlw	03H		;write a W for right player
		movwf	ADR_EE		;pointer to right player
		movlw	05BH		;
		call	write_char	;
main_13:	goto	main_13		;infinte loop (wait for reset)
;
;
;start scanning the frames
;Each frame on the TV is sub divided into blocks. Each block displays a number
;of lines from one type. For example it can be that there is a block which
;dispays 10 blank lines, or there is a block which displays 3 vertical sync.

;lines. In the part of the program below this is realised. Each block of code
;represents a block of lines on the screen. First the number of lines of a 
;certain type is loaded, then the specific subroutine associated with that line
;is called that number of times. The progam then continues to the next block
;until finishes. The programming of the code looks a bit strange, but in this
;way it takes exactly the same amount of time for a block to loop or to skip
;to the next block. The overhead generated by this "dispatcher" is exactly
;8 machine cycles. 
;
;start block_1
;3 lines that generate the vertical sync pulse 
		movlw	003H		;number of lines in block_1
		movwf	N_LINE		;
		goto	block_1		;start first line
bloop_1:	nop			;add delay for all other lines
		goto	block_1	
block_1:	call	line_sync	;do the line
		decfsz	N_LINE,1	;decrement N_LINE
		goto	bloop_1		;another one if not finished
;
;start block_2						
;39 blank lines on the top of the screen. During these blank lines
;the routine returns to the main program after setting timer0, so that
;in time we return to this subroutine.
		movlw	027H		;number of lines in block_1
		movwf	N_LINE		;
		goto	block_2		;start first line
bloop_2:	nop			;add delay for all other lines
		goto	block_2	
block_2:	goto	line_asyn	;do the line
line_asyn_ret:	decfsz	N_LINE,1	;decrement N_LINE
		goto	bloop_2		;another one if not finished
;
;start block_3
;14 lines in total. This routine calles the line_txt routine 7 times.
;but since every call generates two (identical) lines on the screen
;it results in 14 lines
		movlw	007H		;number of lines in block_1
		movwf	N_LINE		;
		goto	block_3		;start first line
bloop_3:	nop			;add delay for all other lines
		goto	block_3	
block_3:	call	line_txt	;do the line
		decfsz	N_LINE,1	;decrement N_LINE
		goto	bloop_3		;another one if not finished
;
;start block_4
;2 lines in total. In line_AD two lines are displayed. during the first line
;the left potentiometer is samples, during the second line the right.
		movlw	001H		;number of lines in block_1
		movwf	N_LINE		;
		goto	block_4		;start first line
bloop_4:	nop			;add delay for all other lines
		goto	block_4	
block_4:	call	line_AD		;do the line
		decfsz	N_LINE,1	;decrement N_LINE
		goto	bloop_4		;another one if not finished
;
;start block_5
;6 lines. The line_compute calculates the new ball positon. It is called 6 
;times to realise a reasonable ball speed
		movlw	006H		;number of lines in block_1
		movwf	N_LINE		;
		goto	block_5		;start first line
bloop_5:	nop			;add delay for all other lines
		goto	block_5	
block_5:	goto	line_compute	;do the line
block_5_ret:	decfsz	N_LINE,1	;decrement N_LINE
		goto	bloop_5		;another one if not finished
;
;start block_6
;5 lines form the upper bar above the game area
		movlw	005H		;number of lines in block_1
		movwf	N_LINE		;
		goto	block_6		;start first line
bloop_6:	nop			;add delay for all other lines
		goto	block_6	
block_6:	call	line_bar	;do the line
		decfsz	N_LINE,1	;decrement N_LINE
		goto	bloop_6		;another one if not finished
;
;start block_7
;216 lines of game field generated by 108 calls to the line_game routine
;which generates 2 lines per call.
		movlw	06CH		;number of lines in block_1
		movwf	N_LINE		;
		goto	block_7		;start first line
bloop_7:	nop			;add delay for all other lines
		goto	block_7	
block_7:	call	line_game	;do the line
		decfsz	N_LINE,1	;decrement N_LINE
		goto	bloop_7		;another one if not finished
;
;start block_8
;5 lines forming the lower bar below the game field						
		movlw	005H		;number of lines in block_1
		movwf	N_LINE		;
		goto	block_8		;start first line
bloop_8:	nop			;add delay for all other lines
		goto	block_8	
block_8:	call	line_bar	;do the line
		decfsz	N_LINE,1	;decrement N_LINE
		goto	bloop_8		;another one if not finished
;
;start block_9
;22 blank lines at the bottom of the screen						
		movlw	016H		;number of lines in block_1
		movwf	N_LINE		;
		goto	block_9		;start first line
bloop_9:	nop			;add delay for all other lines
		goto	block_9	
block_9:	call	line_blank	;do the line
		decfsz	N_LINE,1	;decrement N_LINE
		goto	bloop_9		;another one if not finished
;
;we have now written: 3+39+14+2+6+5+216+5+22=312 lines
;
;and jump back to the first block.
		movlw	003H		;number of lines in block_1	
		movwf	N_LINE		;
;		movlw	020H
;		movwf	X_BALL
;		movwf	Y_BALL

		goto	block_1
;		
;
line_sync:  	bcf	GPIO,VIDEO	;black_2_sync [4]
		bsf	STATUS,RP0	;
		bcf	TRISIO,VIDEO	;
		bcf	STATUS,RP0	;
		nop			;[1]
		movlw	059H		;sync delay [272]
		call	delay		;
		call	H_sync		;[25]
		movlw	01H		;delay [8]
		call 	delay		;
		return			;[2]+[8]
;		
;
line_blank:  	call	H_sync		;[25]
		nop			;wait for end of line [1]
		movlw	05DH		;delay [284]
		call 	delay		;
		return			;[2]+[8]
;		
;
line_asyn: 	call	H_sync		;[25]
		movlw	0C0H		;reset TMR0 [1]
		movwf	TMR0		;[1]
		movf	SAVE_S,0	;restore STATUS register [1]
		movwf	STATUS		;[1]
		movf	SAVE_W,0	;restore W [1] 
		bcf	INTCON,T0IF	;clear timer0 interrupt flag [1]
		bsf	INTCON,T0IE	;enable timer0 interrupt [1]
		retfie			;return to asynchronous part [2]
					;asynchronous part [63]
sync_blck:	movwf	SAVE_W		;save W [1]
		movf	STATUS,0	;save STATUS [1]
		movwf	SAVE_S		;[1]
		bcf	STATUS,RP0	;make sure we are in bank 0 [1]
		movlw	043H		;delay [206]
		call 	delay		;
		bsf	STATUS,RP0	;This is a nice moment to clear [1] 
		clrf	EEADR		;the EEPROM address [1]
		bcf	STATUS,RP0	;[1]
		goto	line_asyn_ret	;[2]+[8]
;		
;
line_compute:  	call	H_sync		;[25]
					;The next two blocks are the original
					;move routine. It has been included
		 			;(two times) in this routine to reduce
					;subroutine nesting
		btfss	BITS_2,DO_IT	;are we movin ?
		goto	move_2		;no	
		call	x_move		;53
		call	y_move		;20
move_1:		goto	move_3		;2
move_2:		nop			;
		nop			;
		movlw	015H		;
		call	delay		;
		goto	move_1		;
move_3:		movf	X_POS,0		;1
		movwf	X_BALL		;1
		movf	Y_POS,0		;1
		movwf	Y_BALL		;1
					;
		btfss	BITS_2,DO_IT	;are we movin ?
		goto	move_5		;no	
		call	x_move		;53
		call	y_move		;20
move_4:		goto	move_6		;2
move_5:		nop			;
		nop			;
		movlw	015H		;
		call	delay		;
		goto	move_4		;
move_6:		movf	X_POS,0		;1
		movwf	X_BALL		;1
		movf	Y_POS,0		;1
		movwf	Y_BALL		;1
					;	
		call	delay4x
		movlw	026H		;delay [119]
		call 	delay		;
		goto	block_5_ret	;[2]+[8]
;		
;
line_bar:  	call	H_sync		;[25]
		movlw	00FH		;wait for white bar [50]
		call	delay		;
		bsf	STATUS,RP0	;black_2_white [3]
		bcf	TRISIO,VIDEO	;
		bcf	STATUS,RP0	;
		movlw	045H		;white bar [212]
		call	delay		;
		bsf	STATUS,RP0	;white_2_black [3]
		bsf	TRISIO,VIDEO	;
		bcf	STATUS,RP0	;
		clrf	Y_LINE		;clear the line counter for the game
		nop			;field [3]
						nop			;
		movlw	003H		;wait till end line [17]
		call	delay		;
		return			;[2] + [8] overhead
;		
;This routine generates the game field. every call to this routine generates
;two lines. In the first line the two bats and the dotted center line is drawn.
;In the second line the ball is drawn. In this way there can be a zero disance
;between the bat and the ball. 
line_game:	call	H_sync		;[25]
		movlw	00EH		;delay [50]
		call	delay		;
		bsf	STATUS,RP0	;do left bat [13]
		decf	Y_L,1		;
		movf	Y_L,0		
		andlw	0F0H		;
		btfss	STATUS,Z	;
		goto	line_game_3	;
		bcf	TRISIO,0	;
line_game_3:	nop			;
		nop			;
		nop			;
;		nop			;
		bsf	TRISIO,0	;
		bsf	STATUS,RP0	;
		nop			;[2]
		nop			;
		movlw	015H		;[68]	
		call 	delay		;
		call	service_ee	;[20]
		bsf	STATUS,RP0	;bank 1            [9]
		btfss	BITS_1,M_LINE	;middle line on ?
		goto	line_game_1	;no
		btfss	Y_LINE,2	;make middle-line
line_game_1:	goto	line_game_2	;
		bcf	TRISIO,0	;pixel on
line_game_2:	nop			;
		bsf	TRISIO,0	;pixel off
		bsf	STATUS,RP0	;bank 0

		movlw	01EH		;[83]
		call	delay		;
		nop
		bsf	STATUS,RP0	;do left bat [13]
		decf	Y_R,1		;
		movf	Y_R,0		;	
		andwf	LENGTH_R,0	;
		btfss	STATUS,Z	;
		goto	line_game_4	;
		bcf	TRISIO,0	;
line_game_4:	nop			;
;		nop			;
		nop			;
		nop			;
		bsf	TRISIO,0	;
		bsf	STATUS,RP0	;

		movlw	008H		;[35]
		call	delay		;
					;second line
		call	H_sync		;[25]
		incf	Y_LINE,1	;wait for end of line [1]
		decf	Y_BALL,1	;see if we have to write the ball 
		movf	Y_BALL,0	;in tis line
		andlw	0FCH		;
		btfss	STATUS,Z	;skip if yes
		goto	line_game_5	;jump if no
		movf	X_BALL,0	;
		call	delay		;
		bsf	STATUS,RP0	;video on
		bcf	TRISIO,VIDEO	;
		call	delay4x		;
		bsf	TRISIO,VIDEO	;
		bcf	STATUS,RP0	;
		movf	X_BALL,0	;
		nop			;
		nop			;
		sublw	056H		;	
		call	delay		;
		return			;
line_game_5:	movlw	05BH		;
		call	delay		;
		return			;
;
;		
;This line routine determines the value of the left and right "bat" 
;potentiometers. It also measures the direction and speed of the potmeter
;changes and detects pressing of the keys. a call to the routine
;actually produces 2 lines on the screen. During the first line the left
;potmeter is processed and during the second line the right potmeter is 
;processed. Each of the two lines starts with generating a h-synch pulse.
;After this the apropriate analog input is selected. For the first line this
;is more complicated than for the other. This is caused by the fact that
;IO pin 1 which is connected to the left potmeter is also used to output
;the audio signal. This means that this pin is digtal output for most of the 
;time and only during this line shortly changed to input (this causes a slight
;50Hz rattle in the audio signal). About 12 us is allowed for the sample and
;hold capacitor to charge. Next the AD conversion is started. After about
;20us conversion time, the output becomes available in ADRESH. next  
;complicated piece of code starts which detects if the key was pressed.
;In this case ADRESH reads 0FFH. Debounce counters DEBNC_L and DEBNC_R are 
;used to debounce the key. If a valid key is detected the corresponding
;R_KEY and L_KEY flags are set. If the key was not pressed, ADRESH is devided
;by two and transferred to Y_L and Y_R. These values are also saved in Y_L_OLD
;and Y_R_OLD. This is nescessary because when the key is pressed, the
;saved value is used as Y_L and Y_R values. The direction and speed from the
;potmeters are calculated by calculationg the differene between the previous
;and present value if ADRESH and transferred in SPEED_L and SPEED_R.
;
line_AD:				;first do the left bat in first line
		call	H_sync		;[25]
					;
		bsf	STATUS,RP0	;bank 1 [6] in total
		movlw	037H		;make pin 2 analog input
		movwf	TRISIO		;note that since line is black,
		movlw	026H		;TRISIO,0 is 1
		movwf	ANSEL		;
		bcf	STATUS,RP0	;bank 0
					;
		movlw	012H		;delay [59] to charge sample and hold 
		call	delay		;capacitor ca 12us
		bsf	ADCON0,GO	;start conversion [1]
					;
		bsf	STATUS,RP0	;bank 1 [6] in total
		movlw	033H		;make pin 2 digital output again
		movwf	TRISIO		;note that since line is black,
		movlw	022H		;TRISIO,0 is 1
		movwf	ANSEL		;
		bcf	STATUS,RP0	;bank 0
					;
		movlw	020H		;delay [101] for conversion ca. 20us
		call 	delay		;
					;the next block deals with the right
					;key, it is [21] cycles
		movf	Y_L_OLD,0	;just in case the key was pressed
		movwf	Y_L		;copy the old value in the current
		movf	ADRESH,0	;is the key pressed ? (=FFH)
		xorlw	0FFH		;
		btfss	STATUS,Z	;skip if pressed
		goto	line_AD_5	;
		movf	DEBNC_L,0	;check if debounce counter already 0
		btfsc	STATUS,Z	;skip if not yet 0
		goto	line_AD_4	;
		decfsz	DEBNC_L,1	;decrement debounce counter
		goto	line_AD_3	;
		bsf	BITS_1,L_KEY	;set key pressed flag
		goto	line_AD_2	;
line_AD_5:	movlw	DEBNC_REL	;reload debounce counter
		movwf	DEBNC_L		;
		movf	AD_L_OLD,0	;calculate the speed of the bat
		SUBWF	ADRESH,0	;
		movwf	SPEED_L		;
		movf	ADRESH,0	;
		movwf	AD_L_OLD	;
		bcf	STATUS,C	;process the AD value from potmeter
		rrf	ADRESH,0	;devide by 2 and add 010H
		addlw	010H		;
		movwf	Y_L		;
		movwf	Y_L_OLD		;		
		goto	line_AD_1	;this set of delays serves to make
line_AD_4:	goto	line_AD_3	;the delay in all of the branches
line_AD_3:	goto	line_AD_2	;in the previous code the same
line_AD_2:	nop			;	
		goto	line_AD_6	;
line_AD_6:	goto	line_AD_7	;
line_AD_7:	goto	line_AD_1	;
					;
line_AD_1:	movlw	020H		;[101]
		call 	delay		;
					;now the right bat in the second line
		call	H_sync		;[25]
					;
		movlw	005H		;select pin 1 for AD converter
		movwf	ADCON0		;[2]
					;
		movlw	012H		;delay [59] to charge sample and hold 
		call	delay		;capacitor ca 12us
		bsf	ADCON0,GO	;start conversion [1]
					;
		movlw	020H		;delay [101] for conversion ca. 20us
		call 	delay		;
					;
		movlw	009H		;select pin 2 again for AD converter
		movwf	ADCON0		;[2]
					;the next block deals with the right
					;key, it is [21] cycles
		movf	Y_R_OLD,0	;just in case the key was pressed
		movwf	Y_R		;copy the old value in the current
		movf	ADRESH,0	;is the key pressed ? (=FFH)
		xorlw	0FFH		;
		btfss	STATUS,Z	;skip if pressed
		goto	line_AD_15	;
		movf	DEBNC_R,0	;check if debounce counter already 0
		btfsc	STATUS,Z	;skip if not yet 0
		goto	line_AD_14	;
		decfsz	DEBNC_R,1	;decrement debounce counter
		goto	line_AD_13	;
		bsf	BITS_1,R_KEY	;set key pressed flag
		goto	line_AD_12	;
line_AD_15:	movlw	DEBNC_REL	;reload debounce counter
		movwf	DEBNC_R		;
		movf	AD_R_OLD,0	;calculate the speed of the bat
		SUBWF	ADRESH,0	;
		movwf	SPEED_R		;
		movf	ADRESH,0	;
		movwf	AD_R_OLD	;
		bcf	STATUS,C	;process the AD value from potmeter
		rrf	ADRESH,0	;devide by 2 and add 010H
		addlw	010H		;
		movwf	Y_R		;
		movwf	Y_R_OLD		;		
		goto	line_AD_11	;this set of delays serves to make
line_AD_14:	goto	line_AD_13	;the delay in all of the branches
line_AD_13:	goto	line_AD_12	;in the previous code the same
line_AD_12:	nop			;	
		goto	line_AD_16	;
line_AD_16:	goto	line_AD_17	;
line_AD_17:	goto	line_AD_11	;
					;
line_AD_11:	nop			;[1]
		movlw	01CH		;[98]
		call 	delay		;
		nop
		btfsc	BITS_2,PLYR_2	;if there is only one player, the
		goto	line_AD_18	;right bat position is linked to the
		movf	Y_POS,0		;position of the ball
		addlw	08H		;
		movwf	Y_R		;
		movwf	Y_R_OLD		;
		goto	line_AD_19	;
line_AD_18:	call	delay4x		;make up for additional delay
		nop			;
line_AD_19:	return			;[2]+[8]
;
;
;This routine checks is the bal hits the bat(s).Only the y coordinate
;is checked. The y coordinate of the bat is supplied in W on call.
;In this way we decide between right or left bat on call. If hit bit
;BITS_1.HIT is set. This routine takes INCLUDING THE CALL [16] cycles.
hit:		bsf	BITS_1,HIT	;
		subwf	Y_BALL,0	; W := y_ball - W	
		addlw	0FH		; W := W + 3
		movwf	CNT_1		; CNT_1 := W
		btfss	CNT_1,7		; check if positive
		goto	hit_1		;
		bcf	BITS_1,HIT	;
hit_1:		movlw	012H		; W := 18 (dec, 15+3)
		subwf	CNT_1,1		; CNT_1 := CNT_1 - W
		btfsc	CNT_1,7		; check if negative
		goto	hit_2		;	
		bcf	BITS_1,HIT	;
hit_2:		return			; 
;
;
;This routine takes care of the left-2-right moment of the ball. 
;first the ball position is incremented. Next we check if the x coordinate
;of the ball coincides with the position of the left bat. If so we check
;if the ball actually touches the bat. This is done in routine hit.
;If we touch the bat, the direction of the ball is inverted by clearing
;bit L2R. Finally we check if the ball has passed the bat and reached the
;end position. The routine takes (INCLUDING THE CALL [41] machine cycles)
X_L2R:		incf	X_POS,1		;increment x position
		movf	X_POS,0		;are we at the location of right bat?
		xorlw	051H		;
		btfss	STATUS,Z	;
		goto	X_L2R_1		;no
		movf	Y_R,0		;yes, is the bat in front of the bal?
		call	hit		;
		btfss	BITS_1,HIT	;
		goto	X_L2R_2		;no
		bsf	BITS_1,BEEP	;
		bcf	BITS_1,L2R	;go from right to left
		goto	X_L2R_3		;
X_L2R_1:	nop			;make up for the differences in delay
		nop			;in the different branches, and
		movlw	04H		;continue with X_L2R.
		call	delay		;
X_L2R_2:	nop			;
		nop			;
		nop			;
X_L2R_3:	movf	X_POS,0		;are we at the right end position ?
		xorlw	055H		;
		btfss	STATUS,Z	;
		goto	X_L2R_4		;no
		bsf	BITS_1,BEEP	;yes, do beep and some other things
		bcf	BITS_2,DO_IT	;stop the game
		bsf	BITS_2,R_OUT	;right out
		goto	X_L2R_5		;
X_L2R_4:	call	delay4x		;make up for differences in delay
X_L2R_5:	return			;
;
;
;This routine takes care of the right-2-left movement of the ball. 
;It is identical to the previous routine with some variables exchanged.
;first the ball position is decremented. Next we check if the x coordinate
;of the ball coincides with the position of the right bat. If so we check
;if the ball actually touches the bat. This is done in routine hit.
;If we touch the bat, the direction of the ball is inverted by setting
;bit R2L. Finally we check if the ball has passed the bat and reached the
;end position. The routine takes (INCLUDING THE CALL [41] machine cycles)
X_R2L:		decf	X_POS,1		;increment x position
		movf	X_POS,0		;are we at the location of right bat?
		xorlw	00FH		;
		btfss	STATUS,Z	;
		goto	X_R2L_1		;no
		movf	Y_L,0		;yes, is the bat in front of the bal?
		call	hit		;
		btfss	BITS_1,HIT	;
		goto	X_R2L_2		;no
		bsf	BITS_1,BEEP	;
		bsf	BITS_1,L2R	;go from left to right
		goto	X_R2L_3		;
X_R2L_1:	nop			;make up for differences in delay
		nop			;in the different branches, and 
		movlw	04H		;continue with X_R2L_3
		call	delay		;
X_R2L_2:	nop			;
		nop			;
		nop			;
X_R2L_3:	movf	X_POS,0		;are we at the right end position ?
		xorlw	00BH		;
		btfss	STATUS,Z	;
		goto	X_R2L_4		;no
		bsf	BITS_1,BEEP	;yes, do beep and some other things
		bcf	BITS_2,DO_IT	;stop game
		bsf	BITS_2,L_OUT	;
		goto	X_R2L_5		;
X_R2L_4:	call	delay4x		;make up for differences in delay
X_R2L_5:	return			;
;
;
;this routine takes care of the movement of the ball in the x direction.
;every call to the routine the X_SPEED counter is decremented. When it 
;reaches zero the routine checkes if the ball is moving from left to right
;(L2R flag set) of from right to left (R2L flag not set). The appropiate
;routine is executed. The routine takes (INCLUDING CALL) [53] cycles
x_move:		decfsz	X_SPEED,1	;decrement call counter if not 
		goto	x_move_1	;zero return if zero do ball move
		movf	SPEED,0		;restore call counter
		movwf	X_SPEED		;
		btfss	BITS_1,L2R	;if L2R set call X_L2R if not 
		goto	x_move_2	;call R2L
		call	X_L2R		;
		goto	x_move_3	;
x_move_2:	call	X_R2L		;
		nop			;
x_move_3:	return			;
x_move_1:	movlw	0DH		;compensate for delay if we didn't 
		call	delay		;have to do anything
		goto	x_move_3	;
;
;
y_move:		decfsz	Y_SPEED,1	;
		goto	y_move_2	;
		movf	SPEED,0		;
		movwf	Y_SPEED		;

		btfss	BITS_1,T2B	;
		goto	y_move_1	;

		nop			;
		incf	Y_POS,1		;
		movf	Y_POS,0		;
		xorlw	06CH		;
		btfss	STATUS,Z	;
		goto	y_move_3	;
		bcf	BITS_1,T2B	;
		bsf	BITS_1,BEEP	;
		goto	y_move_4	;

y_move_1:	decf	Y_POS,1		;
		movf	Y_POS,0		;
		xorlw	004H		;
		btfss	STATUS,Z	;
		goto	y_move_3	;
		bsf	BITS_1,T2B	;
		bsf	BITS_1,BEEP	;
		goto	y_move_4	;

y_move_2:	nop
		nop
		movlw	01H
		call	delay

y_move_3:	nop
		nop
		nop
y_move_4:	return
;
;
line_txt:	call	H_sync		;[25]
		movlw	014H		;delay till first character group
		call	delay		;[65]
		call	two_char	;first group of characters [45]
		movlw	04H		;delay [17]
		call	delay		;
		call	two_char	;middle group of characters [45]
		movlw	04H		;delay [17]
		call	delay		;
		call	two_char	;third group of characters [45]
		bsf	STATUS,RP0	;[1] reset EEADR to beginning of
		decf	EEADR,1		;[1]	
		decf	EEADR,1		;[1]
		decf	EEADR,1		;[1] this line two write a second
		decf	EEADR,1		;[1] line
		decf	EEADR,1		;[1]
		decf	EEADR,1		;[1]
		bcf	STATUS,RP0	;[1]
		movlw	010H		;delay between groups
		call	delay		;[53]
					;second line
		call	H_sync		;[25]
		movlw	014H		;delay till first character group
		call	delay		;[65]
		call	two_char	;first group of characters [45]
		movlw	04H		;delay [17]
		call	delay		;
		call	two_char	;middle group of characters [45]
		movlw	04H		;delay [17]
		call	delay		;
		call	two_char	;second group of characters [45]
		nop			;[1]	
		movlw	00FH		;delay between groups
		call	delay		;[50]
		return			;[10]
;
;
two_char:	bsf	STATUS,RP0	;bank 1
		bsf	EECON1,RD	;initiate a read cycle (character 1)
		movf	EEDATA,0	;get character
;		movlw	057H
		movwf	LFT_CHAR	;store in a temp
		incf	EEADR,1		;next character
		bsf	EECON1,RD	;initiate a read cycle (character 2)
		movf	EEDATA,0	;get character
;		movlw	000H
		movwf	RGT_CHAR	;store in a temp
		incf	EEADR,1		;next character
		bcf	STATUS,RP0	;bank 0
					;
		bsf	GPIO,0		;prepare output for white
		bsf	STATUS,RP0	;bank 1
		rlf	LFT_CHAR,1	;bit 1      of left character
		rlf	TRISIO,1	;to output
		rlf	LFT_CHAR,1	;bit 2
		rlf	TRISIO,1	;to output
		rlf	LFT_CHAR,1	;bit 3
		rlf	TRISIO,1	;to output
		rlf	LFT_CHAR,1	;bit 4
		rlf	TRISIO,1	;to output
		rlf	LFT_CHAR,1	;bit 5
		rlf	TRISIO,1	;to output
		nop			;adjust length last pixel
		bsf	TRISIO,0	;output to tristate again (black)
		nop
		nop
		rlf	RGT_CHAR,1	;bit 1      of right character
		rlf	TRISIO,1	;to output
		rlf	RGT_CHAR,1	;bit 2
		rlf	TRISIO,1	;to output
		rlf	RGT_CHAR,1	;bit 3
		rlf	TRISIO,1	;to output
		rlf	RGT_CHAR,1	;bit 4
		rlf	TRISIO,1	;to output
		rlf	RGT_CHAR,1	;bit 5
		rlf	TRISIO,1	;to output
		nop			;adjust length last pixel
		bsf	TRISIO,0	;output to tristate again (black)
		bcf	STATUS,RP0	;bank 0 again
		nop
		nop
		return 			;[43] without call
;
;
H_sync:  	bcf	GPIO,VIDEO	;black_2_sync [4]
		bsf	STATUS,RP0	;
		bcf	TRISIO,VIDEO	;
		bcf	STATUS,RP0	;
do_beep:	btfss	BITS_1,BEEP	;see if we need to beep
		goto	do_beep_5	;no
		decfsz	BCNT_1,1	;decrement BCNT_1
		goto	do_beep_4	;not zero yet
		decfsz	BCNT_2,1	;decrement BCNT_2
		goto	do_beep_2	;not zero yet
do_beep_1:	bcf	BITS_1,BEEP	;beep finished, clear up things
		movlw	BEEP_LEN	;
		movwf	BCNT_2		;
		goto	do_beep_3	;finished some extra code for timing
do_beep_2:	bcf	GPIO,2		;copy bit to output
		btfss	BCNT_1,3	; 
		goto	do_beep_3	;
		bsf	GPIO,2		;
do_beep_3:	nop			;delays to get timing right
		nop			;
		bsf	STATUS,RP0	;sync_2_black [4]
		bsf	TRISIO,VIDEO	;
		bcf	STATUS,RP0	;
		bsf	GPIO,VIDEO	;
		return			;
do_beep_4:	goto	do_beep_2	;
do_beep_5:	nop			;
		goto	do_beep_1	;
;
;
;this will cause a delay (INCLUDING THE MOVELW AND THE CALL) of 5+3n cycles
delay:		movwf	CNT_1
delay1:		decfsz	CNT_1,1
		goto	delay1
		return
;
;
;this routine replaces a 4 NOP delay
delay4x:	return
;
;
;There was a problem with writing to the eeprom. A write to eeprom 
;takes about 5 ms to complete. If we do this in the aynchronous part,
;the asynchronous part is over before the write is complete. immediately
;after the asynchronous part the text lines are displayed. This also
;access the eeprom and a conflict occures. The solution is that the 
;asynchronous part generates a write request which is services by a piece of
;code which is executed in the synchronous part (during a emty piece in the
;game field). from the synchronous point of view this piece of code does
;nothing but just represents a delay of 20 cycles (including call)
service_ee:	btfss	BITS_1,W_REQ	;is write request flag set (in
		goto	service_ee_2	;asynchronous part ?
		bsf	STATUS,RP0	;bank 1
		movf	W_ADR,0		;copy addres to eeprom register 
		movwf	EEADR		;
		movf	W_DAT,0		;copy data to eeprom register
		movwf	EEDATA		;
		bsf	EECON1,WREN	;enable writing in eeprom
		movlw	055H		;initiate write sequence
		movwf	EECON2		;
		movlw	0AAH		;
		movwf	EECON2		;
		bsf	EECON1,WR	;
		bcf	EECON1,WREN	;disable writing
		bcf	BITS_1,W_REQ	;reset request flag
		bcf	STATUS,RP0	;bank 0 again
service_ee_1:	return			;		
service_ee_2:	movlw	02H		;compensate delay
		call	delay		;
		goto	service_ee_1	;goto return
;
;
;This routine is part of the main program.
;This routine writes a byte to the eeprom. The data is in w on call,
;it is returned in w on return. The address is in ADR_EE, this adress
;is incremented by 6 on return. Since the synchronous display routines
;access the eeprom, an interrupt to these routines is disabled during the
;write sequence.
write_ee:	btfsc	BITS_1,W_REQ	;wait till W_REQ is reset
		goto	write_ee	;
		movwf	W_DAT		;store data to be written
		movf	ADR_EE,0	;store addres to be written
		movwf	W_ADR		;
		movlw	006H		;increment write addres by 6
		addwf	ADR_EE,1	;write it back to ADR_EE
		movf	W_DAT,0		;copy data written back to w
		bsf	BITS_1,W_REQ	;tell the syncronous part to write
		return			;
;
;
;This routine is part of the main program. it writes a character to eeprom.
;On call the character code (the entry addres in table char_gen) is in w.
;The location in eeprom is in ADR_EE, on return ADR_EE points to 
;next character. It uses the character ROM table char_gen. 
write_char:	movwf	ADR_TAB		;save table address in ADR_TAB
write_char_1:	movf	ADR_TAB,0	;w=ADR_TAB
		call	char_gen	;w=@(w)
		incf	ADR_TAB,1	;ADR_TAB=ADR_TAB+1		
		call	write_ee	;write it in eeprom
		andlw	001H		;
		btfsc	STATUS,Z	;skip if ready	
		goto	write_char_1	;do next row
		movlw	029H		;adjust ADR_EE to next character
		subwf	ADR_EE,1	;
		return
;
;
inc_scr:	bcf	BITS_2,FIN	;not finished to begin with
		movwf	SCORE		;store W in SCORE
		incf	SCORE,1		;SCORE = SCORE + 1
		movf	SCORE,0		;W = score
		andlw	0FH		;label lower nibble
		xorlw	0AH		;is it equal to 0A ?
		btfss	STATUS,Z	;skip if SCORE = *A
		goto	inc_scr_3	;if not end with displaying score
		movf	SCORE,0		;W = score
		andlw	0F0H		;clear lowest nibble
		addlw	010H		;add 10
		movwf	SCORE		;save w in SCORE
		xorlw	050H		;is score equal to 50 ?
		btfsc	STATUS,Z	;skip if not yet finished
		goto	inc_scr_2	;score was 50 so finished
		movf	SCORE,0		;W = score
		subwf	OLD_HIGH,1	;OLD_HIGH = OLD_HIGH - W
		btfsc	OLD_HIGH,7	;skip if >0 (no new high score)
		goto	inc_scr_1	;there was a new high score
		movf	SCORE,0		;restore high score W = score
		addwf	OLD_HIGH,1	;OLD_HIGH = OLD_HIGH + SCORE
		goto	inc_scr_3	;finished
inc_scr_1:	movf	SCORE,0		;W = SCORE
		movwf	OLD_HIGH	;OLD_HIGH = SCORE
		swapf	OLD_HIGH,0	;W = swapped(OLD_HIGH)
		andlw	00FH		;label lower nibble	
		call	speed_table	;translate in speed
		movwf	SPEED		;it becomes the new speed
		goto 	inc_scr_3	;finish by displaying the score
inc_scr_2:	bsf	BITS_2,FIN	;the end of the game
inc_scr_3:	swapf	SCORE,0		;display higher score nibble
		andlw	00FH		;
		call	dig_tab		;translate to character code
		call	write_char	;display
		movf	SCORE,0		;display lower score nibble
		andlw	00FH		;
		call	dig_tab		;translate to character code
		call	write_char	;display
		movf	SCORE,0		;exit with SCORE in w again
		return
;
;
;This routine is part of the min program
;it places the ball on an invisible position
ball_inv	movlw	005H		;ball out of view
		movwf	X_POS		;
		movlw	040H		;
		movwf	Y_POS		;	
		return			;
;
;
read_switch:	bcf	BITS_2,FAST	;default slow set
		btfss	GPIO,3		;if input is 1 it remains slow 
		bsf	BITS_2,FAST	;if input is 0 it becomes fast
		swapf	OLD_HIGH,0	;W = swapped(OLD_HIGH)
		andlw	00FH		;label lower nibble	
		call	speed_table	;translate in speed
		movwf	SPEED		;it becomes the new speed
		return
;
;
		org	0381
speed_table	btfsc	BITS_2,FAST	;fast set ot slow set ?
		goto	speed_table_1	;goto fast set
		addwf	PCL,1		;first normal set		
		retlw	012H		;"0*"
		retlw	010H		;"1*"
		retlw	008H		;"2*"
		retlw	007H		;"3*"
		retlw	006H		;"4*"
		retlw	008H		;"5*"
speed_table_1:	addwf	PCL,1		;now fast set		
		retlw	007H		;"0*"
		retlw	006H		;"1*"
		retlw	006H		;"2*"
		retlw	006H		;"3*"
		retlw	006H		;"4*"
		retlw	006H		;"5*"
;
;
		org	0391
dig_tab:	addwf	PCL,1		;
		retlw	000H		;"0"
		retlw	007H		;"1"
		retlw	00EH		;"2"
		retlw	015H		;"3"
		retlw	01CH		;"4"
		retlw	023H		;"5"
		retlw	02AH		;"6"
		retlw	031H		;"7"
		retlw	038H		;"8"
		retlw	03FH		;"9"
;
;
		org	039CH
char_gen:	addwf	PCL,1		;
					;"0" @(00)
		retlw	088H		;
		retlw	070H		;
		retlw	060H		;
		retlw	050H		;
		retlw	030H		;
		retlw	070H		;
		retlw	089H		;

					;"1" @(07)
		retlw	0D8H		;
		retlw	098H		;
		retlw	0D8H		;
		retlw	0D8H		;
		retlw	0D8H		;
		retlw	0D8H		;
		retlw	089H		;
					;"2" @(0E)
		retlw	088H		;
		retlw	070H		;
		retlw	0F0H		;
		retlw	0E8H		;
		retlw	0D8H		;
		retlw	0B8H		;
		retlw	001H		;
					;"3" @(15)
		retlw	000H		;
		retlw	0E8H		;
		retlw	0D8H		;
		retlw	0E8H		;
		retlw	0F0H		;
		retlw	070H		;
		retlw	089H		;
					;"4" @(1C)
		retlw	0E8H		;
		retlw	0C8H		;
		retlw	0A8H		;
		retlw	068H		;
		retlw	000H		;
		retlw	0E8H		;
		retlw	0E9H		;
					;"5" @(23)
		retlw	000H		;
		retlw	078H		;
		retlw	008H		;
		retlw	0F0H		;
		retlw	0F0H		;
		retlw	070H		;
		retlw	089H		;
					;"6" @(2A)
		retlw	0C8H		;
		retlw	0B8H		;
		retlw	078H		;
		retlw	008H		;
		retlw	070H		;
		retlw	070H		;
		retlw	089H		;
					;"7" @(31)
		retlw	000H		;
		retlw	0F0H		;
		retlw	0E8H		;
		retlw	0D8H		;
		retlw	0D8H		;
		retlw	0D8H		;
		retlw	0D9H		;
					;"8" @(38)
		retlw	088H		;
		retlw	070H		;
		retlw	070H		;
		retlw	088H		;
		retlw	070H		;
		retlw	070H		;
		retlw	089H		;
					;"9" @(3F)
		retlw	088H		;
		retlw	070H		;
		retlw	070H		;
		retlw	080H		;
		retlw	0F0H		;
		retlw	0E8H		;
		retlw	099H		;
					;" " @(46)
		retlw	0F8H		;
		retlw	0F8H		;
		retlw	0F8H		;
		retlw	0F8H		;
		retlw	0F8H		;
		retlw	0F8H		;
		retlw	0F9H		;
					;"->" @(4D)
		retlw	0B8H		;
		retlw	0D8H		;
		retlw	0E8H		;
		retlw	000H		;
		retlw	0E8H		;
		retlw	0D8H		;
		retlw	0B9H		;
					;"<-" @(54)
		retlw	0E8H		;
		retlw	0D8H		;
		retlw	0B8H		;
		retlw	000H		;
		retlw	0B8H		;
		retlw	0D8H		;
		retlw	0E9H		;
					;"W" @(5B)
		retlw	070H		;
		retlw	070H		;
		retlw	070H		;
		retlw	050H		;
		retlw	050H		;
		retlw	050H		;
		retlw	0A9H		;	
        END

