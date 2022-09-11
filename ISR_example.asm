; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 2kHz square wave at pin P1.1 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 2 on the LCD.  Also resets it to 
; zero if the 'BOOT' pushbutton connected to P4.5 is pressed.
$NOLIST
$MODLP51
$LIST

; There is a couple of typos in MODLP51 in the definition of the timer 0/1 reload
; special function registers (SFRs), so:

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

TIME_RATE_SECONDS       equ 1000


DEBOUNCE_DELAY	equ	50

RESET_BUTTON   equ P4.5
SOUND_BUTTON     equ P1.1


ENTER_BUTTON   equ P2.1
MOVE_BUTTON  equ P0.6
INCREMENT_TIME_BUTTON equ P0.3

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when half second has passed

;CLOCK
BCD_second:   ds 1 ;(seconds); The BCD counter incrememted in the ISR and displayed in the main loop
BCD_minute:   ds 1
BCD_hour:     ds 1


alarm_hour:  ds 1 		;the BCD counter is incremented in the ISR and displayed in the main loop
alarm_minute:   ds 1
sound_pos:   ds 1

subroutine:       ds 1		;setting "States" like cpen 211 sequential logic

CURSOR_POSITION:  ds 1


; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed

am_pm_flag:         dbit 1
alarm_ampm_flag:    dbit 1
sound_flag:         dbit 1
alarm_toggle_flag:	dbit 1
timer1_flag:        dbit 1

subroutine1_flag:   dbit 1




cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P3.2
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                     1234567890123456    <- This helps determine the location of the counter
Initial_Message:   db 'Time  00:00:00 A', 0
;Initial_Message:  	db 	'--:--:-- -M     ',  	0
Secondary_Message: db 'Alarm 00:00    A', 0
COLON_TIME:       db ':', 0

cursor_symbol:	db 	'^^', 0


HOUR_INDICATOR:	db 	'      ^^        ',		0 ;the indicator for when we want to change the hours
MIN_INDICATOR:	db	'         ^^     ',		0 ;""""" the minutes
SEC_INDICATOR:	db	'            ^^  ',		0 ;""""" the seconds

INITIAL_MESSAGE_ROW1: db 'Time    :  :    ', 0 ;message it displays after setting time
INITIAL_MESSAGE_ROW2: db 'Alarm 10:43:00 A', 0	; message it displayes after setting time

SECONDARY_MESSAGE_ROW1: db 'Alarm   :  :  A', 0 ; message it displayes after setting alarm

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Set autoreload value
	mov RH0, #high(TIMER0_RELOAD)
	mov RL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P1.1 ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	cpl SOUND_BUTTON 
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P1.0 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	
    ; The two registers used in the ISR must be saved in the stack
    push    acc
    push    psw

    ; Increment the 16-bit one mili second counter
    inc     Count1ms+0    ; Increment the low 8-bits first
    mov     a,  Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
    jnz     Timer2_ISR_incDone
    inc     Count1ms+1

Timer2_ISR_incDone:
    ; Check if [] second has passed
    mov     a,  Count1ms+0
    cjne    a,  #low(TIME_RATE_SECONDS),    Timer2_ISR_done ; Warning: this instruction changes the carry flag!
    mov     a,  Count1ms+1
    cjne    a,  #high(TIME_RATE_SECONDS),   Timer2_ISR_done

    ; toggle sound
  
   	mov 	a,	sound_pos
    cjne    a,  #0x0A,  Timer2_ISR_inDone_incSound
    mov     sound_pos,  #0x00
    sjmp    Timer2_ISR_inDone_incSound_done
    
Timer2_ISR_inDone_incSound:
    inc     sound_pos
Timer2_ISR_inDone_incSound_done:
    
   
    setb    half_seconds_flag 
    

    clr     a
    mov     Count1ms+0, a
    mov     Count1ms+1, a

    
    mov 	a, 	BCD_second
    cjne 	a, 	#0x59,     Timer2_ISR_incSecond
    mov 	a,	#0         
    da 		a
    mov 	BCD_second,    a

    ; check if alarm is up
    jnb     alarm_toggle_flag,  Timer2_ISR_skipAlarm
    lcall   Timer2_checkAlarm

Timer2_ISR_skipAlarm:
   
    mov		a,	BCD_minute
    cjne	a,	#0x59,     Timer2_ISR_incMinute
    mov 	a,  #0        
    da		a
    mov 	BCD_minute,    a
    mov 	a,  BCD_hour   ; reset hour, toggle am/pm
    jb 		am_pm_flag,	   Timer2_ISR_PM
    cjne 	a, 	#0x11, Timer2_ISR_incHour
    cjne 	a, 	#0x12, Timer2_ISR_AM11
Timer2_ISR_AM11:
    cpl		am_pm_flag
    sjmp 	Timer2_ISR_incHour
Timer2_ISR_PM:
    cjne	a, 	#0x12, Timer2_ISR_PM12
    mov		a, 	#1
    da		a
    mov		BCD_hour, 	a
    sjmp	Timer2_ISR_done
Timer2_ISR_PM12:
    cjne 	a, 	#0x11, Timer2_ISR_incHour
    cpl		am_pm_flag
    mov 	a,	#0
    da		a
    mov 	BCD_hour,	a
    sjmp    Timer2_ISR_done
Timer2_ISR_incSecond:
    add 	a, 	#0x01
    da 		a
    mov 	BCD_second, a
    sjmp	Timer2_ISR_done
Timer2_ISR_incMinute:
    add		a, 	#0x01
    da		a
    mov		BCD_minute, a
    sjmp	Timer2_ISR_done
Timer2_ISR_incHour:
    add		a, 	#0x01
    da		a
    mov 	BCD_hour,	a
    sjmp	Timer2_ISR_done
Timer2_ISR_done:
    pop psw
    pop acc
    reti

Timer2_checkAlarm:
  
    mov     a,  BCD_hour
    cjne    a,  alarm_hour, Timer2_checkAlarm_done
    mov     a,  BCD_minute
    inc 	a
    da		a
    cjne    a,  alarm_minute,  Timer2_checkAlarm_done
    jb      am_pm_flag,	Timer2_checkAlarm_pm
    jb      alarm_ampm_flag,    Timer2_checkAlarm_done
    setb    TR0
    mov     sound_pos,  #0x00
    setb    timer1_flag
    sjmp    Timer2_checkAlarm_done
Timer2_checkAlarm_pm:
    jnb     alarm_ampm_flag,    Timer2_checkAlarm_done
    setb    TR0
    mov     sound_pos,  #0x00
    setb    timer1_flag
    sjmp    Timer2_checkAlarm_done
Timer2_checkAlarm_done:
    ret
	

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
main:
	; Initialization
    mov SP, #0x7F
    lcall Timer0_Init
    lcall Timer2_Init
   
    mov P0M0, #0
    mov P0M1, #0
    setb EA   
    lcall LCD_4BIT
  
    setb half_seconds_flag
    
    ; set initial message
    Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
    
	; initialize time
    mov     a,  #0x00
    da      a
    mov     BCD_second,     a
    mov     BCD_minute,     a
    mov     BCD_hour,       a
    clr     am_pm_flag
    mov     alarm_hour,     a
    mov     a,  #0x01
    da      a
   ; mov     alarm_min,      a
    clr     alarm_ampm_flag
    
    
	
	;initializing state
	mov subroutine, #0x00
	
	


loop:

	clr c
	mov a, subroutine
	

	
	jb ENTER_BUTTON, subroutine0
	Wait_Milli_Seconds(#DEBOUNCE_DELAY)
    jb      ENTER_BUTTON,    subroutine0
    jnb     ENTER_BUTTON,    $
    
    ;jb state1_flag, state0
    ljmp subroutine1

subroutine0_a1:
	ljmp subroutine0_a
	
subroutine0:

	jb ENTER_BUTTON, subroutine0_a1
	Wait_Milli_Seconds(#DEBOUNCE_DELAY)
    jb      ENTER_BUTTON,    subroutine0_a1
    jnb     ENTER_BUTTON,    $
    
   
    
   
    Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
    mov     a,      #0x00
    mov     subroutine,   a
    ljmp    subroutine0_d

subroutine1:
	
	Set_Cursor(1, 1)
    Send_Constant_String(#INITIAL_MESSAGE_ROW1)
    
    Set_Cursor(1, 7)
    Display_BCD(BCD_hour)
    Set_Cursor(1, 10)
    Display_BCD(BCD_minute)
    Set_Cursor(1, 13)
    Display_BCD(BCD_second)
    Set_Cursor(1, 16)
   
    Display_char(#'A')
    
    Set_Cursor(2, 1)
    Send_Constant_String(#INITIAL_MESSAGE_ROW2)
    jb      ENTER_BUTTON,       subroutine1aa
    Wait_Milli_Seconds(#DEBOUNCE_DELAY)
    jb      ENTER_BUTTON,       subroutine1aa
    jnb     ENTER_BUTTON,       $
    
    ljmp subroutine2  
    
subroutine1aa:
	ljmp subroutine1
subroutine0_a:

	jb      MOVE_BUTTON,       subroutine0_b
    Wait_Milli_Seconds(#DEBOUNCE_DELAY)
    jb      MOVE_BUTTON,       subroutine0_b
    jnb     MOVE_BUTTON,       $

    mov     a,  CURSOR_POSITION
    cjne    a,  #0x02,  subroutine0_a_inc
    mov     CURSOR_POSITION,  #0x00
    ljmp    subroutine0_d
    

subroutine0_a_inc:

	inc     CURSOR_POSITION
    ljmp    subroutine0_d

subroutine0_b:

	jb      INCREMENT_TIME_BUTTON,       subroutine0_c
    Wait_Milli_Seconds(#DEBOUNCE_DELAY)
    jb      INCREMENT_TIME_BUTTON,       subroutine0_c
    jnb     INCREMENT_TIME_BUTTON,       $
 
    clr     c
    mov     a,  CURSOR_POSITION
    jz      subroutine0_b_setHours
    subb    a,  #0x01
    jz      subroutine0_b_setMinutes
  
    clr     TR2
    clr     a
    mov     Count1ms+0, a
    mov     Count1ms+1, a
    mov     BCD_second, #0x00
    setb    TR2
    sjmp    subroutine0_d
	

subroutine0_b_setHours:


    mov 	a,  BCD_hour   
    jb 		am_pm_flag,	   subroutine0_b_setHours_PM
    cjne 	a, 	#0x11,     subroutine0_b_setHours_incHour
    cjne 	a, 	#0x12,     subroutine0_b_setHours_AM11

subroutine0_b_setHours_AM11:

	cpl		am_pm_flag
    sjmp 	subroutine0_b_setHours_incHour

subroutine0_b_setHours_PM:

	cjne	a, 	#0x12, subroutine0_b_setHours_PM12
    mov		a, 	#1
    da		a
    mov		BCD_hour, 	a
    sjmp	subroutine0_d

subroutine0_b_setHours_PM12:

	cjne 	a, 	#0x11, subroutine0_b_setHours_incHour
    cpl		am_pm_flag
    mov 	a,	#0
    da		a
    mov 	BCD_hour,	a
    sjmp    subroutine0_d

subroutine0_b_setHours_incHour:

	add		a, 	#0x01
    da		a
    mov 	BCD_hour,	a
    sjmp    subroutine0_d

subroutine0_b_setMinutes:

	; increment minutes
    mov     a,  BCD_minute
    cjne    a,  #0x59,  subroutine0_b_setMinutes_inc
    mov     BCD_minute, #0x00
    sjmp    subroutine0_d

subroutine0_b_setMinutes_inc:

	add     a, 	#0x01
    da		a
    mov		BCD_minute,	a
    sjmp    subroutine0_d

subroutine0_c:

	jb		half_seconds_flag,	subroutine0_d
    ljmp	loop

subroutine0_d:

	clr    	half_seconds_flag

    Set_Cursor(2, 1)
    clr     c
    mov     a,  CURSOR_POSITION
    jz      subroutine0_d_setHours
    subb    a,  #0x01
    jz      subroutine0_d_setMinutes
    Send_Constant_String(#SEC_INDICATOR)
    sjmp    subroutine0_d_display
    
    
subroutine0_d_setHours:

	Send_Constant_String(#HOUR_INDICATOR)
    sjmp    subroutine0_d_display

subroutine0_d_setMinutes:  

    Send_Constant_String(#MIN_INDICATOR)
    sjmp	subroutine0_d_display
    
subroutine0_d_display:

	; display rest
    Set_Cursor(1, 7)
    Display_BCD(BCD_hour)
    Set_Cursor(1, 10)	
    Display_BCD(BCD_minute)
    Set_Cursor(1, 13)
    Display_BCD(BCD_second)
    Set_Cursor(1, 16)
    jb 		am_pm_flag, subroutine0_setpm
    Display_char(#'A')
    
    ljmp	subroutine2

subroutine0_setpm:

	Display_char(#'P')
	
	clr subroutine1_flag
	
    ljmp    loop
    
 ; setting the alarm clock now
 ; re use code above, but change subroutines and variable names
 subroutine2_a1:
	ljmp subroutine2_a
	
 subroutine2:

	jb ENTER_BUTTON, subroutine2_a1
	Wait_Milli_Seconds(#DEBOUNCE_DELAY)
    jb      ENTER_BUTTON,    subroutine2_a1
    jnb     ENTER_BUTTON,    $
    
  
    Set_Cursor(1, 1)
    Send_Constant_String(#Secondary_Message)
    mov     a,      #0x00
   
    ljmp    subroutine2_d
    
 subroutine2_a:

	jb      MOVE_BUTTON,       subroutine2_b
    Wait_Milli_Seconds(#DEBOUNCE_DELAY)
    jb      MOVE_BUTTON,       subroutine2_b
    jnb     MOVE_BUTTON,       $
  
    mov     a,  CURSOR_POSITION
    cjne    a,  #0x02,  subroutine2_a_inc
    mov     CURSOR_POSITION,  #0x00
    ljmp    subroutine2_d
    

subroutine2_a_inc:

	inc     CURSOR_POSITION
    ljmp    subroutine0_d

subroutine2_b:

	jb      INCREMENT_TIME_BUTTON,       subroutine2_c
    Wait_Milli_Seconds(#DEBOUNCE_DELAY)
    jb      INCREMENT_TIME_BUTTON,       subroutine2_c
    jnb     INCREMENT_TIME_BUTTON,       $
 
    clr     c
    mov     a,  CURSOR_POSITION
    jz      subroutine2_b_setHours
    subb    a,  #0x01
    jz      subroutine2_b_setMinutes
   
    clr     TR2
    clr     a
    mov     Count1ms+0, a
    mov     Count1ms+1, a
    mov     BCD_second, #0x00
    setb    TR2
    sjmp    subroutine2_d
	

subroutine2_b_setHours:

	; increment hours
    mov 	a,  BCD_hour   
    jb 		am_pm_flag,	   subroutine2_b_setHours_PM
    cjne 	a, 	#0x11,     subroutine2_b_setHours_incHour
    cjne 	a, 	#0x12,     subroutine2_b_setHours_AM11

subroutine2_b_setHours_AM11:

	cpl		am_pm_flag
    sjmp 	subroutine2_b_setHours_incHour

subroutine2_b_setHours_PM:

	cjne	a, 	#0x12, subroutine2_b_setHours_PM12
    mov		a, 	#1
    da		a
    mov		BCD_hour, 	a
    sjmp	subroutine2_d

subroutine2_b_setHours_PM12:

	cjne 	a, 	#0x11, subroutine2_b_setHours_incHour
    cpl		am_pm_flag
    mov 	a,	#0
    da		a
    mov 	BCD_hour,	a
    sjmp    subroutine2_d

subroutine2_b_setHours_incHour:

	add		a, 	#0x01
    da		a
    mov 	BCD_hour,	a
    sjmp    subroutine2_d

subroutine2_b_setMinutes:

	; increment minutes
    mov     a,  BCD_minute
    cjne    a,  #0x59,  subroutine2_b_setMinutes_inc
    mov     BCD_minute, #0x00
    sjmp    subroutine2_d

subroutine2_b_setMinutes_inc:

	add     a, 	#0x01
    da		a
    mov		BCD_minute,	a
    sjmp    subroutine2_d

subroutine2_c:

	jb		half_seconds_flag,	subroutine2_d
    ljmp	loop

subroutine2_d:

	clr    	half_seconds_flag
  
    Set_Cursor(2, 1)
    clr     c
    mov     a,  CURSOR_POSITION
    jz      subroutine2_d_setHours
    subb    a,  #0x01
    jz      subroutine2_d_setMinutes
  
    sjmp    subroutine2_d_display
    
    
subroutine2_d_setHours:

	Send_Constant_String(#HOUR_INDICATOR)
    sjmp    subroutine2_d_display

subroutine2_d_setMinutes:  

    Send_Constant_String(#MIN_INDICATOR)
    sjmp	subroutine2_d_display
    
subroutine2_d_display:


    Set_Cursor(1, 7)
    Display_BCD(alarm_hour)
    Set_Cursor(1, 10)
    Display_BCD(alarm_minute)
    Set_Cursor(1, 13)
    
    Set_Cursor(1, 16)

    Display_char(#'A')
    
    ljmp	subroutine2_everything
    
subroutine2_everything:

	Set_Cursor(1, 1)
	Send_Constant_String(#Initial_Message)
	Set_Cursor(2, 1) 
	Send_Constant_String(#Secondary_Message)
	Set_Cursor(1, 7)
    Display_BCD(BCD_hour)
    Set_Cursor(1, 10)
    Display_BCD(BCD_minute)
    Set_Cursor(1, 13)
    Display_BCD(BCD_second)
    
    Set_Cursor(2, 7)
    Display_BCD(alarm_hour)
    Set_Cursor(2, 10)
    Display_BCD(alarm_minute)
    
	ljmp subroutine2_setpm
   
subroutine2_setpm:

	Display_char(#'P')
	
	clr subroutine1_flag
	
    ljmp    loop  
	 
END