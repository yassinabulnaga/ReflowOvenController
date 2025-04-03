;============================================================================
;  "MAIN" CODE (Your Reflow Oven + Passcode + LCD) with minimal additions
;============================================================================
$NOLIST
$MODN76E003
$LIST

;===========================================================================
;  N76E003 pinout:
;                               -------
;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;===========================================================================

; Reset vector
org 0x0000
    ljmp main
    
; External interrupt 0 vector
org 0x0003
    reti

;-----------------------------------------------------------------------------
; CHANGED HERE: Timer/Counter 0 overflow interrupt vector (was "reti" before).
; We jump to the Super Mario Timer0_ISR used for the note generation.
;-----------------------------------------------------------------------------
org 0x000B
    ljmp Timer0_ISR    ; Replaces the original "reti"

; External interrupt 1 vector
org 0x0013
    reti

; Timer/Counter 1 overflow interrupt vector
org 0x001B
    reti

; Serial port receive/transmit interrupt vector
org 0x0023 
    reti
    
; Timer/Counter 2 overflow interrupt vector
org 0x002B
    ljmp Timer2_ISR

;===========================================================================
; MAIN CODE CONSTANTS / EQUATES
;===========================================================================
CLK  EQU 16600000 ; Microcontroller system oscillator frequency in Hz
BAUD EQU 115200   ; Baud rate of UART in bps

; Timer 1 is used for Baud
TIMER1_RELOAD EQU (0x100-(CLK/(16*BAUD)))

; Timer 2 is used for the pwm and seconds counter
; From PWM_demo.asm
TIMER2_RATE   EQU 100                            ; 100 Hz or 10 ms
TIMER2_RELOAD EQU (65536-(CLK/(16*TIMER2_RATE))) ; Need to change timer 2 input divide to 16 in T2MOD

; Temperature Calculation
RESISTOR_1 EQU 9990 ; kilo-ohms ; R1 should be bigger than R2
RESISTOR_2 EQU 33   ; kilo-ohms ; ratio R1/R2 is used
CONSTANT   EQU ((99900*RESISTOR_2)/RESISTOR_1)
COLD_TEMP  EQU 22  ; Celsius

; Abort Condition Checking
TIME_ERROR EQU 50 ; seconds
TEMP_ERROR EQU 60 ; Celsius

; Inputs
SHIFT_BUTTON      EQU P1.6
TEMP_SOAK_BUTTON  EQU PB4
TIME_SOAK_BUTTON  EQU PB3
TEMP_REFL_BUTTON  EQU PB2
TIME_REFL_BUTTON  EQU PB1
START_STOP_BUTTON EQU PB0     

; Outputs
PWM_OUT     EQU P1.0 ; Logic 1 = oven on ; Pin 15
SOUND_OUT   EQU P0.4 

; These 'equ' must match the hardware wiring for the LCD
LCD_RS EQU P1.3
LCD_E  EQU P1.4
LCD_D4 EQU P0.0
LCD_D5 EQU P0.1
LCD_D6 EQU P0.2
LCD_D7 EQU P0.3

;===========================================================================
; DATA SEGMENT
;===========================================================================
DSEG at 0x30
; For math32.inc
x:   ds 4
y:   ds 4
bcd: ds 5

; For ADC Reading / Temperature Calculation
VAL_LM4040: ds 2

; FSM / LCD Variables
pwm_counter: ds 1 ; Free running counter 0..100 for Timer2-based PWM
pwm:         ds 1 ; PWM percentage

runtime_sec: ds 1 ; total runtime of the entire reflow process
runtime_min: ds 1

FSM1_state:  ds 1
temp:        ds 1
sec:         ds 1
temp_soak:   ds 1
time_soak:   ds 1
temp_refl:   ds 1
time_refl:   ds 1

; bonus passcode entry variables
PASSCODE_LENGTH  EQU 4
passcode_buffer: ds 4
passcode_index:  ds 1
passcode_ptr:    ds 1
correct_passcode: db '1','2','3','4'

;===========================================================================
; BIT SEGMENT
;===========================================================================
BSEG
mf: dbit 1

; set to 1 every time a second has passed
s_flag: dbit 1

; set to 1 on first run through state 0
state_0_flag: dbit 1
active_flag:  dbit 1
error_flag:   dbit 1
done_flag:    dbit 1

; These five bit variables store the value of the pushbuttons after calling 'LCD_PB' below
PB0: dbit 1
PB1: dbit 1
PB2: dbit 1
PB3: dbit 1
PB4: dbit 1

;===========================================================================
; CODE SEGMENT
;===========================================================================
CSEG

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc)   ; A library of math functions
$include(macros.inc)   ; Macros from lecture slides / macros we have created ourselves
$LIST

;                 1234567890123456
setup_line1:  db 'Soak   XXXC XXXs', 0
setup_line2:  db 'Reflow XXXC XXXs', 0

active_line1: db 'State X     XXXC', 0
active_line2: db 'XX:XX       XXXs', 0

error_line1:  db 'Error! t = XX:XX', 0
error_line2:  db 'Oven Temp = XXXC', 0

done_line1:   db '  Oven Cooled!  ', 0
done_line2:   db 'Runtime  = XX:XX', 0


;===========================================================================
; Interrupts
;===========================================================================

;------------------------------------------------------------------------------
; Timer0_ISR is REDEFINED in the "Super Mario" section below. 
; Here in main code, we previously had "org 0x000B" with reti, replaced above.
;------------------------------------------------------------------------------

Timer1_ISR:
    reti

Timer2_ISR:
    clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in the ISR.
    push psw
    push acc
	
    inc pwm_counter
    clr c
    mov a, pwm
    subb a, pwm_counter   ; If pwm_counter <= pwm then c=1
    cpl c
    mov PWM_OUT, c
	
    mov a, pwm_counter
    cjne a, #100, Timer2_ISR_done
    mov pwm_counter, #0
    inc sec             ; increment seconds counter
    setb s_flag

    inc runtime_sec
    mov a, runtime_sec
    cjne a, #60, Timer2_ISR_done
    mov runtime_sec, #0
    inc runtime_min

Timer2_ISR_done:
    pop acc
    pop psw
    reti

;===========================================================================
; Initializations
;===========================================================================
Init_All:
    lcall Init_Pins
    Wait_Milli_Seconds(#5)
    lcall Init_Timer0
    lcall Init_Timer1
    lcall Init_Timer2
    lcall Init_ADC
    lcall Init_Variables
    setb EA ; Enable global interrupts
    ret

Init_Pins:
    ; Configure all the pins for bidirectional I/O
    mov	P3M1, #0x00
    mov	P3M2, #0x00
    mov	P1M1, #0x00
    mov	P1M2, #0x00
    mov	P0M1, #0x00
    mov	P0M2, #0x00
    ret

Init_Timer0:
    ; We do not configure Timer0 here in the main code
    ; The Mario code will configure it when needed.
    ret

Init_Timer1:
	orl	CKCON, #0x10        ; CLK is the input for timer 1
	orl	PCON, #0x80         ; Bit SMOD = 1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F         ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20         ; Timer 1 Mode 2 (8-bit auto-reload)
	mov	TH1, #TIMER1_RELOAD
	setb TR1
	ret

Init_Timer2:
    ; Initialize timer 2 for periodic 100 Hz interrupts
    mov T2CON, #0         ; Stop timer/counter, autoreload mode.
    mov TH2, #high(TIMER2_RELOAD)
    mov TL2, #low(TIMER2_RELOAD)
    mov T2MOD, #0b1010_0000 ; Enable timer 2 autoreload; clock divider = 16
    mov RCMP2H, #high(TIMER2_RELOAD)
    mov RCMP2L, #low(TIMER2_RELOAD)
    mov pwm_counter, #0
    orl EIE, #0x80       ; Enable timer 2 interrupt (ET2 = 1)
    setb TR2            ; Start timer 2
    ret

Init_ADC:
    ; Initialize pins used by the ADC (P1.1, P1.7) as input, etc.
    orl	P1M1, #0b10000010
    anl	P1M2, #0b01111101
    ; Initialize and start the ADC:
    anl ADCCON0, #0xF0
    orl ADCCON0, #0x07   ; default channel 7
    mov AINDIDS, #0x00
    orl AINDIDS, #0b10000001  ; Activate AIN0 and AIN7 
    orl ADCCON1, #0x01   ; Enable ADC
    ret

Init_Variables:
    mov pwm_counter, #0
    mov pwm, #0
    mov runtime_sec, #0
    mov runtime_min, #0
    mov FSM1_state,  #8    ; Start in passcode entry state
    mov sec, #0
    clr s_flag
    clr state_0_flag
    clr active_flag
    clr error_flag
    clr done_flag
    mov passcode_index, #0
    mov passcode_ptr,  #passcode_buffer
    ret
Create_Flame:
    WriteCommand(#0x48) ; Memory location for first byte of custom character 1
    WriteData(#0x04)    ;   *  
    WriteData(#0x08)    ;  *  
    WriteData(#0x0A)    ;  * *  
    WriteData(#0x0C)    ;  **  
    WriteData(#0x1F)    ; *****  
    WriteData(#0x17)    ; * ***  
    WriteData(#0x13)    ; *    **  
    WriteData(#0x0E)    ;  ***  
    ret

Create_Snowflake:
    WriteCommand(#0x40) ; Memory location for first byte of custom character 0
    WriteData(#0x0A)    ; *   *  
    WriteData(#0x04)    ;   *  
    WriteData(#0x15)    ;*  *  *  
    WriteData(#0x0E)    ;  ***  
    WriteData(#0x15)    ;*  *  *  
    WriteData(#0x04)    ;   *  
    WriteData(#0x0A)    ; *   *  
    WriteData(#0x00)    ;     
    ret



;===========================================================================
; LCD Icon Display Routines
;===========================================================================
; These routines display a flame when in the reflow state (FSM1_state=4)
; and a snowflake in every other state.

Display_Temperature_Icon:
    mov A, FSM1_state
    cjne A, #5, Display_Flame  ; If state ≠ 4 (not reflow), show Snowflake
    ljmp Display_Snowflake             ; Otherwise, show Flame

Display_Snowflake:
    Set_Cursor(1, 9)   ; Set cursor to desired position (adjust as needed)
    Display_char (#0)   ; Display custom character 0 (snowflake)
    ret

Display_Flame:
    Set_Cursor(1, 9)   ; Set cursor to desired position (adjust as needed)
    Display_char (#1)   ; Display custom character 1 (flame)
    ret

LCD_Clear:
    mov A, #0x01           ; Command to clear display (HD44780)
    lcall LCD_SendCommand
    ; Optionally, you can add extra delay or write spaces to both lines if needed:
    Wait_Milli_Seconds(#2) ; Wait ~2ms for clear command to complete
    ret
; --- Additional strings for passcode display ---
passcode_prompt:  db 'Enter Passcode: ',0
passcode_fail:    db 'Wrong Passcode',0
passcode_fail2:   db 'Try Again',0
blank_line:       db '                ',0

; --- LCD Routines (if not already in your LCD_4bit.inc) ---
;    (Included in your code. Shown for completeness if needed.)

;===========================================================================
; Passcode & FSM code
;===========================================================================

Display_Passcode_Info:
    lcall LCD_Clear
    Set_Cursor(1,1)
    Send_Constant_String(#passcode_prompt)
    Set_Cursor(2,1)
    Send_Constant_String(#blank_line)
    ret

FSM1_state_passcode:
    mov pwm, #0
    lcall Display_Passcode_Info
Passcode_Wait:
    lcall LCD_PB
    jnb PB4, Passcode_Button1
    jnb PB3, Passcode_Button2
    jnb PB2, Passcode_Button3
    jnb PB1, Passcode_Button4
    jnb PB0, Passcode_Return
    sjmp Passcode_Wait

Passcode_Button1:
    mov A, #'1'
    lcall Save_Passcode_Digit
    sjmp Passcode_Wait
Passcode_Button2:
    mov A, #'2'
    lcall Save_Passcode_Digit
    sjmp Passcode_Wait
Passcode_Button3:
    mov A, #'3'
    lcall Save_Passcode_Digit
    sjmp Passcode_Wait
Passcode_Button4:
    mov A, #'4'
    lcall Save_Passcode_Digit
    sjmp Passcode_Wait

Passcode_Return:
    Wait_Milli_Seconds(#200)     
    lcall Check_Passcode
    mov A, FSM1_state
    cjne A, #8, Exit_Passcode_Return
    sjmp FSM1_state_passcode
Exit_Passcode_Return:
    ret

Save_Passcode_Digit:
    Wait_Milli_Seconds(#200)
    push ACC
    mov A, passcode_index
    cjne A, #PASSCODE_LENGTH, Save_Digit_OK
    pop ACC
    ret
Save_Digit_OK:
    pop ACC
    mov R0, passcode_ptr
    mov @R0, A
    inc passcode_ptr
    inc passcode_index
    lcall Update_Passcode_Display
    ret

Update_Passcode_Display:
    Set_Cursor(2,1)
    Send_Constant_String(#blank_line)
    Set_Cursor(2,1)
    mov R6, passcode_index
Update_Passcode_Display_Loop:
    cjne R6, #0, Display_Asterisk
    ret
Display_Asterisk:
    mov A, #'*'
    lcall ?WriteData
    djnz R6, Update_Passcode_Display_Loop
    ret

Check_Passcode:
    mov A, passcode_index
    cjne A, #PASSCODE_LENGTH, Passcode_Failed
    mov R0, #passcode_buffer
    mov DPTR, #correct_passcode
    mov R2, #PASSCODE_LENGTH
Check_Loop:
    clr A
    movc A, @A+DPTR
    mov B, @R0
    cjne A, B, Passcode_Failed
    inc DPTR
    inc R0
    djnz R2, Check_Loop
    ; correct
    mov FSM1_state, #0
    mov passcode_index, #0
    mov passcode_ptr, #passcode_buffer
    lcall LCD_Clear
    lcall Display_Setup_Info
    ret

Passcode_Failed:
    Set_Cursor(1,1)
    Send_Constant_String(#passcode_fail)
    Set_Cursor(2,1)
    Send_Constant_String(#passcode_fail2)
    mov passcode_index, #0
    mov passcode_ptr, #passcode_buffer
    ; Wait ~2 seconds total
    mov R7, #20
pf_loop:
    Wait_Milli_Seconds(#100)
    djnz R7, pf_loop
    ret

;-----------------------------------------------------------
LCD_SendCommand:
    ; Example 4-bit command routine, shown if needed.
    ret

;===========================================================================
; Main Function
;===========================================================================
main:
    mov sp, #07FH
    lcall Init_All
    lcall LCD_4BIT

    ; Loads variables from flash memory
    lcall Load_Variables
    lcall Display_Setup_Info

Forever:
    lcall LCD_PB
    lcall FSM1
    jnb s_flag, s_flag_check
    lcall Read_Temperature
    SendToSerialPort(temp)
    clr s_flag
s_flag_check:
    ljmp Forever

;===========================================================================
; Finite State Machine (FSM1) with Passcode Feature
;===========================================================================
FSM1:
    mov A, FSM1_state
    cjne A, #8, FSM1_not_passcode
    ljmp FSM1_state_passcode

FSM1_not_passcode:
    cjne A, #0, FSM1_state1

;--- RESTING STATE (State 0) ---
FSM1_state0:
    mov pwm, #0
    mov sec, #0
    mov runtime_sec, #0
    mov runtime_min, #0
    lcall Update_Variables
    jb state_0_flag, Not_First_Time
    lcall Display_Setup_Info
    setb state_0_flag
Not_First_Time:
    lcall Display_Setup_Info2
    jb START_STOP_BUTTON, FSM1_state0_done
    Wait_Milli_Seconds(#50)
    jb START_STOP_BUTTON, FSM1_state0_done
check_release0:
    lcall LCD_PB
    jnb START_STOP_BUTTON, check_release0
    mov FSM1_state, #1
    lcall Display_Active_Info
    mov sec, #0    
FSM1_state0_done:
    ljmp FSM2

;--- RAMP TO SOAK (State 1) ---
FSM1_state1:
    cjne A, #1, FSM1_state2
    mov pwm, #100
    mov A, #TIME_ERROR
    clr C
    subb A, runtime_sec
    jnc FSM1_error_checked
    mov A, #TEMP_ERROR
    clr C
    subb A, temp
    jc FSM1_error_checked
    mov FSM1_state, #6
    ljmp FSM2
FSM1_error_checked:
    mov A, temp_soak
    clr C
    subb A, temp
    jnc FSM1_state1_done
    mov FSM1_state, #2
    mov sec, #0
FSM1_state1_done:
    ljmp FSM2

;--- SOAK (State 2) ---
FSM1_state2:
    cjne A, #2, FSM1_state3
    mov pwm, #20
    mov A, time_soak
    clr C
    subb A, sec
    jnc FSM1_state2_done
    mov FSM1_state, #3
    mov sec, #0    
FSM1_state2_done:
    ljmp FSM2

;--- RAMP TO REFLOW (State 3) ---
FSM1_state3:
    cjne A, #3, FSM1_state4
    mov pwm, #100
    mov A, temp_refl
    clr C
    subb A, temp
    jnc FSM1_state3_done
    mov FSM1_state, #4
    mov sec, #0
FSM1_state3_done:
    ljmp FSM2

;--- REFLOW (State 4) ---
FSM1_state4:
    cjne A, #4, FSM1_state5
    mov pwm, #20
    mov A, time_refl
    clr C
    subb A, sec
    jnc FSM1_state4_done
    mov FSM1_state, #5
    mov sec, #0
FSM1_state4_done:
    ljmp FSM2

;--- COOL DOWN (State 5) ---
FSM1_state5:
    cjne A, #5, FSM1_state6
    mov pwm, #0
    mov A, temp
    clr C
    subb A, #60
    jnc FSM1_state5_done
    mov FSM1_state, #7
FSM1_state5_done:
    ljmp FSM2

;--- ERROR (State 6) ---
FSM1_state6:
    cjne A, #6, FSM1_state7
    mov pwm, #0
    jb START_STOP_BUTTON, FSM1_state6_done
    Wait_Milli_Seconds(#50)
    jb START_STOP_BUTTON, FSM1_state6_done
check_release:
    lcall LCD_PB
    jnb START_STOP_BUTTON, check_release
    mov FSM1_state, #0
    clr state_0_flag
    clr active_flag
    clr error_flag
    clr done_flag
FSM1_state6_done:
    ljmp FSM2

;--- DONE (State 7) ---
FSM1_state7:
    mov pwm, #0
    jb START_STOP_BUTTON, FSM1_state7_done
    Wait_Milli_Seconds(#50)
    jb START_STOP_BUTTON, FSM1_state7_done
check_release1:
    lcall LCD_PB
    jnb START_STOP_BUTTON, check_release1 
    mov FSM1_state, #0
    clr state_0_flag
    clr active_flag
    clr error_flag
    clr done_flag
FSM1_state7_done:
    ljmp FSM2

;--- Common Post-State Code (FSM2) ---
FSM2:
    mov A, FSM1_state
    cjne A, #0, FSM2_not_state0
    ljmp FSM2_done
FSM2_not_state0:
    cjne A, #6, FSM2_no_error
    jb error_flag, Not_First_Time1
    lcall Display_Error_Info
    setb error_flag
Not_First_Time1:
    lcall Display_Error_Info2
    ljmp FSM2_done
FSM2_no_error:
    cjne A, #7, FSM2_Not_Done
    jb done_flag, Not_First_Time2
    lcall Display_Done_Info
    setb done_flag

    ;---------------------------------------------------------
    ; ADDED HERE: Once we first enter the DONE state,
    ; call the Mario tune subroutine to play the song *once*.
    ;---------------------------------------------------------

Not_First_Time2:
    ljmp FSM2_done
FSM2_Not_Done:
    jb active_flag, Not_First_Time3
    lcall Display_Active_Info
    setb active_flag
    lcall Play_Mario_Once
Not_First_Time3:
    lcall Display_Active_Info2
    jb START_STOP_BUTTON, FSM2_done
    Wait_Milli_Seconds(#50)
    jb START_STOP_BUTTON, FSM2_done
check_release2:
    lcall LCD_PB
    jnb START_STOP_BUTTON, check_release2 
    mov FSM1_state, #0
    clr state_0_flag
    clr active_flag
    clr error_flag
    clr done_flag
FSM2_done:
    ret


;===========================================================================
; LCD Display Routines
;===========================================================================
Display_Setup_Info:
    Set_Cursor(1, 1)
    Send_Constant_String(#setup_line1)
    Set_Cursor(2, 1)
    Send_Constant_String(#setup_line2)
    ret

Display_Setup_Info2:
    Set_Cursor(1, 8)
    SendToLCD(temp_soak)
    Set_Cursor(1, 13)
    SendToLCD(time_soak)
    Set_Cursor(2, 8)
    SendToLCD(temp_refl)
    Set_Cursor(2, 13)
    SendToLCD(time_refl)
    ret

Display_Error_Info:
    Set_Cursor(1, 1)
    Send_Constant_String(#error_line1)
    Set_Cursor(2, 1)
    Send_Constant_String(#error_line2)
    ret

Display_Error_Info2:
    Set_Cursor(2, 13)
    SendToLCD(temp)
    Set_Cursor(1, 12)
    mov a, runtime_min
    mov b, #10
    div ab
    orl a, #0x30
    lcall ?WriteData
    mov a, b
    orl a, #0x30
    lcall ?WriteData
    Set_Cursor(1, 15)
    mov a, runtime_sec
    mov b, #10
    div ab
    orl a, #0x30
    lcall ?WriteData
    mov a, b
    orl a, #0x30
    lcall ?WriteData
    ret

Display_Done_Info:
    Set_Cursor(1, 1)
    Send_Constant_String(#done_line1)
    Set_Cursor(2, 1)
    Send_Constant_String(#done_line2)
    Set_Cursor(2, 12)
    mov a, runtime_min
    mov b, #10
    div ab
    orl a, #0x30
    lcall ?WriteData
    mov a, b
    orl a, #0x30
    lcall ?WriteData
    Set_Cursor(2, 15)
    mov a, runtime_sec
    mov b, #10
    div ab
    orl a, #0x30
    lcall ?WriteData
    mov a, b
    orl a, #0x30
    lcall ?WriteData
    ret

Display_Active_Info:
    Set_Cursor(1, 1)
    Send_Constant_String(#active_line1)
    Set_Cursor(2, 1)
    Send_Constant_String(#active_line2)
    ret

Display_Active_Info2:
    Set_Cursor(1, 7)
    mov a, FSM1_state
    orl a, #0x30
    lcall ?WriteData
    Set_Cursor(1, 13)
    SendToLCD(temp)
    Set_Cursor(2, 13)
    SendToLCD(sec)
    Set_Cursor(2, 1)
    mov a, runtime_min
    mov b, #10
    div ab
    orl a, #0x30
    lcall ?WriteData
    mov a, b
    orl a, #0x30
    lcall ?WriteData
    Set_Cursor(2, 4)
    mov a, runtime_sec
    mov b, #10
    div ab
    orl a, #0x30
    lcall ?WriteData
    mov a, b
    orl a, #0x30
    lcall ?WriteData
    ret

    lcall Display_Temperature_Icon

;===========================================================================
; Updates variables with Push Buttons
;===========================================================================
Change_8bit_Variable MAC
    jb %0, %2
check%M:
    lcall LCD_PB
    jnb %0, check%M
    jb SHIFT_BUTTON, skip%Mb
    dec %1
    ljmp skip%Ma
skip%Mb:
    inc %1
skip%Ma:
ENDMAC

Update_Variables:
    Change_8bit_Variable(TEMP_SOAK_BUTTON, temp_soak, update_temp_soak)
    Set_Cursor(1, 8)
    SendToLCD(temp_soak)
    lcall Save_Variables
update_temp_soak:
    Change_8bit_Variable(TIME_SOAK_BUTTON, time_soak, update_time_soak)
    Set_Cursor(1, 13)
    SendToLCD(time_soak)
    lcall Save_Variables
update_time_soak:
    Change_8bit_Variable(TEMP_REFL_BUTTON, temp_refl, update_temp_refl)
    Set_Cursor(2, 8)
    SendToLCD(temp_refl)
    lcall Save_Variables
update_temp_refl:
    Change_8bit_Variable(TIME_REFL_BUTTON, time_refl, update_time_refl)
    Set_Cursor(2, 13)
    SendToLCD(time_refl)
    lcall Save_Variables
update_time_refl:
    ret

;===========================================================================
; Reads Push Buttons (LCD_PB routine)
;===========================================================================
LCD_PB:
    setb PB0
    setb PB1
    setb PB2
    setb PB3
    setb PB4
    setb P1.5
    clr P0.0
    clr P0.1
    clr P0.2
    clr P0.3
    clr P1.3
    jb P1.5, LCD_PB_Done
    Wait_Milli_Seconds(#50)
    jb P1.5, LCD_PB_Done
    setb P0.0
    setb P0.1
    setb P0.2
    setb P0.3
    setb P1.3
    clr P1.3
    mov c, P1.5
    mov PB4, c
    setb P1.3
    clr P0.0
    mov c, P1.5
    mov PB3, c
    setb P0.0
    clr P0.1
    mov c, P1.5
    mov PB2, c
    setb P0.1
    clr P0.2
    mov c, P1.5
    mov PB1, c
    setb P0.2
    clr P0.3
    mov c, P1.5
    mov PB0, c
    setb P0.3
LCD_PB_Done:
    ret

;===========================================================================
; Get the temperature from the ADC
;===========================================================================
Read_Temperature:
    anl ADCCON0, #0xF0
    orl ADCCON0, #0x00   ; Channel 0
    lcall Average_ADC
    mov VAL_LM4040+0, R0 
    mov VAL_LM4040+1, R1
    anl ADCCON0, #0xF0
    orl ADCCON0, #0x07   ; Channel 7
    lcall Average_ADC
    mov x+0, R0
    mov x+1, R1
    mov x+2, #0
    mov x+3, #0
    Load_y(CONSTANT)
    lcall mul32
    mov y+0, VAL_LM4040+0
    mov y+1, VAL_LM4040+1
    mov y+2, #0
    mov y+3, #0
    lcall div32
    Load_y(COLD_TEMP)
    lcall add32
    mov temp, x+0
    ret

;===========================================================================
; Stores/Loads variables in Flash memory
;===========================================================================
PAGE_ERASE_AP   EQU 00100010b
BYTE_PROGRAM_AP EQU 00100001b

Save_Variables:
    CLR EA
    MOV TA, #0aah
    MOV TA, #55h
    ORL CHPCON, #00000001b
    MOV TA, #0aah
    MOV TA, #55h
    ORL IAPUEN, #00000001b
    MOV IAPCN, #PAGE_ERASE_AP
    MOV IAPAH, #3fh
    MOV IAPAL, #80h
    MOV IAPFD, #0FFh
    MOV TA, #0aah
    MOV TA, #55h
    ORL IAPTRG, #00000001b
    MOV IAPCN, #BYTE_PROGRAM_AP
    MOV IAPAH, #3fh
    MOV IAPAL, #80h
    MOV IAPFD, temp_soak
    MOV TA, #0aah
    MOV TA, #55h
    ORL IAPTRG,#00000001b
    MOV IAPAL, #81h
    MOV IAPFD, time_soak
    MOV TA, #0aah
    MOV TA, #55h
    ORL IAPTRG,#00000001b
    MOV IAPAL, #82h
    MOV IAPFD, temp_refl
    MOV TA, #0aah
    MOV TA, #55h
    ORL IAPTRG,#00000001b
    MOV IAPAL, #83h
    MOV IAPFD, time_refl
    MOV TA, #0aah
    MOV TA, #55h
    ORL IAPTRG,#00000001b
    MOV IAPAL,#84h
    MOV IAPFD, #55h
    MOV TA, #0aah
    MOV TA, #55h
    ORL IAPTRG, #00000001b
    MOV IAPAL, #85h
    MOV IAPFD, #0aah
    MOV TA, #0aah
    MOV TA, #55h
    ORL IAPTRG, #00000001b
    MOV TA, #0aah
    MOV TA, #55h
    ANL IAPUEN, #11111110b
    MOV TA, #0aah
    MOV TA, #55h
    ANL CHPCON, #11111110b
    setb EA
    ret

Load_Variables:
    mov dptr, #0x3f84
    clr a
    movc a, @a+dptr
    cjne a, #0x55, Load_Defaults
    inc dptr
    clr a
    movc a, @a+dptr
    cjne a, #0xaa, Load_Defaults
    mov dptr, #0x3f80
    clr a
    movc a, @a+dptr
    mov temp_soak, a
    inc dptr
    clr a
    movc a, @a+dptr
    mov time_soak, a
    inc dptr
    clr a
    movc a, @a+dptr
    mov temp_refl, a
    inc dptr
    clr a
    movc a, @a+dptr
    mov time_refl, a
    ret

Load_Defaults:
    mov temp_soak, #150
    mov time_soak, #60
    mov temp_refl, #230
    mov time_refl, #30
    ret

putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

;============================================================================
;  SUPER MARIO CODE (modified to be a subroutine "Play_Mario_Once")
;============================================================================

;-------------------------------
; I/O Pin Definitions and Constants for Mario code
;-------------------------------
; We'll pick an available pin for SOUND_OUT. 
; The original code used P1.7, but your main code uses P1.7 for ADC input.
; So, let's define SOUND_OUT = P3.1 (an unused pin on N76E003).
; Adjust your hardware wiring accordingly (speaker on P3.1).
; If you prefer a different free pin, just change it here.
;-------------------------------

;-------------------------------
; Internal RAM Variables for Mario notes
; Place them in unused data addresses above 0x50 to avoid overlap.
;-------------------------------
DSEG at 0x50
NoteReloadL: DS 1
NoteReloadH: DS 1
NoteDuration: DS 1

;-------------------------------
; The code segment for Mario
;-------------------------------
CSEG

; We rely on the fact that the main code has: org 0x000B -> ljmp Timer0_ISR
; That means the Timer0 ISR will jump here:
Timer0_ISR:
    CLR   TR0
    MOV   A, NoteReloadH
    MOV   TH0, A
    MOV   A, NoteReloadL
    MOV   TL0, A
    SETB  TR0
    CPL   SOUND_OUT
    RETI

;-------------------------------------------------------------------------
; "Play_Mario_Once" subroutine: sets up Timer0 and plays the entire tune
; exactly once, then returns to caller.
;-------------------------------------------------------------------------
Play_Mario_Once:
    ; Initialize Timer0 & I/O for speaker
    LCALL Mario_Init

    ; Display the word "sound" on the LCD if desired, or skip
    ; (We'll skip LCD display here to avoid interfering with your reflow LCD)
    ; Now play the entire sequence from the Song table exactly once.
    ; The original code had an infinite loop. We'll convert it so that
    ; it returns after the final note (the 0,0,0).
    MOV   DPTR, #Song     ; point to the song table in code
    SETB  EA              ; ensure interrupts are enabled
Loop_Notes:
    ; fetch next note:
    LCALL NextNote
    CJNE  A, #0, Play_Note
    ; if A=0 => means we got the 'end marker' (0,0,0).  Stop & return
    CLR   TR0             ; turn off Timer0
    CLR   SOUND_OUT
    RET

Play_Note:
    ; A holds the note duration now in NoteDuration
    ; Timer0 is already running from last note fetch, so:
    MOV   R2, NoteDuration
    LCALL WaitmilliSec
    CLR   TR0
    CLR   SOUND_OUT
    MOV   R2, #50  ; 50 ms gap
    LCALL WaitmilliSec
    SETB  TR0
    SJMP  Loop_Notes


;-------------------------------
; Mario_Init: sets up the speaker pin, timer0, etc.
;-------------------------------
Mario_Init:
    ; Make sure P3.1 is push-pull output
    ; You already set P3M1,P3M2 = 0 in Init_Pins, so P3 is push-pull. 
    CLR   SOUND_OUT
    ; Timer0 config
    ; We'll do (Mode 1) 16-bit, no prescaler
    ORL   CKCON, #0x08     ; Timer0 clock = sysclk/1
    MOV   A, TMOD
    ANL   A, #0xF0         ; clear T0 config
    ORL   A, #0x01         ; T0 = Mode1, 16-bit
    MOV   TMOD, A
    CLR   TR0
    CLR   TF0
    SETB  ET0              ; Enable T0 interrupt
    MOV   R2, #50
    LCALL WaitmilliSec
    RET

;-------------------------------
; WaitmilliSec: same routine as in Mario code
; We can reuse or rename. We'll keep it local to Mario.
; Parameter: R2 = # of ms
;-------------------------------
WaitmilliSec:
    PUSH  AR0
    PUSH  AR1
Delay_Loop_m:
    MOV   R1, #40
Inner_Loop_m:
    MOV   R0, #104
Wait_R0_m:
    DJNZ  R0, Wait_R0_m
    DJNZ  R1, Inner_Loop_m
    DJNZ  R2, Delay_Loop_m
    POP   AR1
    POP   AR0
    RET

;-------------------------------
; NextNote: from the Mario code, but we adapt so it returns with A=0 if
;           the next note is the end marker (0,0,0).
; Format of each note: [ReloadHigh][ReloadLow][Duration]
; If Duration=0 => end of song
;-------------------------------
NextNote:
    CLR   A
    MOVC  A, @A+DPTR       ; fetch reload high
    MOV   NoteReloadH, A
    INC   DPTR
    CLR   A
    MOVC  A, @A+DPTR       ; fetch reload low
    MOV   NoteReloadL, A
    INC   DPTR
    CLR   A
    MOVC  A, @A+DPTR       ; duration
    INC   DPTR
    MOV   NoteDuration, A
    JZ    EndOfSong        ; if 0 => end marker
    ; not zero => load Timer0 registers
    MOV   TH0, NoteReloadH
    MOV   TL0, NoteReloadL
    SETB  TR0
    MOV   A, NoteDuration  ; Return note duration in A
    RET

EndOfSong:
    ; Return A=0 to indicate end of song
    CLR A
    RET

;-------------------------------
; The Song data from the original code
; We place it at a high address so as not to collide with your main code.
;-------------------------------
org 0x4000
Song:
;-----------------------------------
; Measure 1:  ^E   ^E   ^E
    DB  0xCE, 0x89, 150   ; ^E  (E5 ≈659 Hz)
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xCE, 0x89, 150   ; ^E

; Measure 2:  ^C   ^E   ^G   G
    DB  0xC2, 0x06, 150   ; ^C  (C5 ≈523 Hz)
    DB  0xCE, 0x89, 150   ; ^E  (E5)
    DB  0xD6, 0x66, 150   ; ^G  (G5 ≈784 Hz)
    DB  0xAD, 0x4B, 150   ; G   (G4 ≈392 Hz)

;-----------------------------------
; Measure 3:  ^C   G    E
    DB  0xC2, 0x06, 150   ; ^C  (C5)
    DB  0xAD, 0x4B, 150   ; G   (G4)
    DB  0x9D, 0x0A, 150   ; E   (E4 ≈330 Hz)

; Measure 4:  A    B    Bb   A
    DB  0xB6, 0x50, 150   ; A   (A4 =440 Hz)
    DB  0xBE, 0x54, 150   ; B   (B4 ≈494 Hz)
    DB  0xBA, 0x72, 150   ; Bb  (Bb4 ≈466 Hz)
    DB  0xB6, 0x50, 150   ; A   (A4)

; Measure 5:  G    ^E   ^G   ^A
    DB  0xAD, 0x4B, 150   ; G   (G4)
    DB  0xCE, 0x89, 150   ; ^E  (E5)
    DB  0xD6, 0x66, 150   ; ^G  (G5)
    DB  0xDB, 0x28, 150   ; ^A  (A5 =880 Hz)

; Measure 6:  ^F   ^G   ^E   ^C   ^D   B
    DB  0xD1, 0x69, 150   ; ^F  (F5 ≈698 Hz)
    DB  0xD6, 0x66, 150   ; ^G  (G5)
    DB  0xCE, 0x89, 150   ; ^E  (E5)
    DB  0xC2, 0x06, 150   ; ^C  (C5)
    DB  0xC8, 0xCB, 150   ; ^D  (D5 ≈587 Hz)
    DB  0xBE, 0x54, 150   ; B   (B4)

;-----------------------------------
; (Repeat the above two measures for the next two blocks)
; Measure 7:  ^C   G    E
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xAD, 0x4B, 150   ; G
    DB  0x9D, 0x0A, 150   ; E

; Measure 8:  A    B    Bb   A
    DB  0xB6, 0x50, 150   ; A
    DB  0xBE, 0x54, 150   ; B
    DB  0xBA, 0x72, 150   ; Bb
    DB  0xB6, 0x50, 150   ; A

; Measure 9:  G    ^E   ^G   ^A
    DB  0xAD, 0x4B, 150   ; G
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xD6, 0x66, 150   ; ^G
    DB  0xDB, 0x28, 150   ; ^A

; Measure 10: ^F   ^G   ^E   ^C   ^D   B
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xD6, 0x66, 150   ; ^G
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC8, 0xCB, 150   ; ^D
    DB  0xBE, 0x54, 150   ; B

;-----------------------------------
; Measure 11:  ^G   ^F#  ^F   ^D   ^E
    DB  0xD6, 0x66, 150   ; ^G  (G5)
    DB  0xD4, 0x32, 150   ; ^F# (F#5 ≈740 Hz)
    DB  0xD1, 0x69, 150   ; ^F  (F5)
    DB  0xC8, 0xCB, 150   ; ^D  (D5)
    DB  0xCE, 0x89, 150   ; ^E  (E5)

; Measure 12:  G    A    ^C
    DB  0xAD, 0x4B, 150   ; G   (G4)
    DB  0xB6, 0x50, 150   ; A   (A4)
    DB  0xC2, 0x06, 150   ; ^C  (C5)

; Measure 13:  A    ^C   ^D
    DB  0xB6, 0x50, 150   ; A   (A4)
    DB  0xC2, 0x06, 150   ; ^C  (C5)
    DB  0xC8, 0xCB, 150   ; ^D  (D5)

; Measure 14:  ^G   ^F#  ^F   ^D   ^E
    DB  0xD6, 0x66, 150   ; ^G
    DB  0xD4, 0x32, 150   ; ^F#
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xC8, 0xCB, 150   ; ^D
    DB  0xCE, 0x89, 150   ; ^E

; Measure 15:  *C   *C   *C
    DB  0x08, 0x48, 150   ; *C  (C3 ≈131 Hz)
    DB  0x08, 0x48, 150   ; *C
    DB  0x08, 0x48, 150   ; *C

;-----------------------------------
; Measure 16:  ^G   ^F#  ^F   ^D   ^E
    DB  0xD6, 0x66, 150   ; ^G
    DB  0xD4, 0x32, 150   ; ^F#
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xC8, 0xCB, 150   ; ^D
    DB  0xCE, 0x89, 150   ; ^E

; Measure 17:  G    A    ^C
    DB  0xAD, 0x4B, 150   ; G
    DB  0xB6, 0x50, 150   ; A
    DB  0xC2, 0x06, 150   ; ^C

; Measure 18:  A    ^C   ^D
    DB  0xB6, 0x50, 150   ; A
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC8, 0xCB, 150   ; ^D

; Measure 19:  ^D#  ^D   ^C
    DB  0xCB, 0xE2, 150   ; ^D# (≈622 Hz)
    DB  0xC8, 0xCB, 150   ; ^D
    DB  0xC2, 0x06, 150   ; ^C

;-----------------------------------
; Measure 20:  ^C   ^C   ^C
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC2, 0x06, 150   ; ^C

; Measure 21:  ^C   ^D   ^E   ^C   A    G
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC8, 0xCB, 150   ; ^D
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xB6, 0x50, 150   ; A
    DB  0xAD, 0x4B, 150   ; G

; Measure 22:  ^C   ^C   ^C
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC2, 0x06, 150   ; ^C

; Measure 23:  ^C   ^D   ^E
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC8, 0xCB, 150   ; ^D
    DB  0xCE, 0x89, 150   ; ^E

; Measure 24:  ^C   ^C   ^C
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC2, 0x06, 150   ; ^C

; Measure 25:  ^C   ^D   ^E   ^C   A    G
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC8, 0xCB, 150   ; ^D
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xB6, 0x50, 150   ; A
    DB  0xAD, 0x4B, 150   ; G

; Measure 26:  ^E   ^E   ^E
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xCE, 0x89, 150   ; ^E

; Measure 27:  ^C   ^E   ^G   G
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xD6, 0x66, 150   ; ^G
    DB  0xAD, 0x4B, 150   ; G

;-----------------------------------
; Measure 28:  ^C   G    E
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xAD, 0x4B, 150   ; G
    DB  0x9D, 0x0A, 150   ; E

; Measure 29:  A    B    Bb   A
    DB  0xB6, 0x50, 150   ; A
    DB  0xBE, 0x54, 150   ; B
    DB  0xBA, 0x72, 150   ; Bb
    DB  0xB6, 0x50, 150   ; A

; Measure 30:  G    ^E   ^G   ^A
    DB  0xAD, 0x4B, 150   ; G
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xD6, 0x66, 150   ; ^G
    DB  0xDB, 0x28, 150   ; ^A

; Measure 31:  ^F   ^G   ^E   ^C   ^D   B
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xD6, 0x66, 150   ; ^G
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xC8, 0xCB, 150   ; ^D
    DB  0xBE, 0x54, 150   ; B

;-----------------------------------
; Measure 32:  ^E-^C   G
; Here the “–” is taken as a tie: split into two 75 ms notes.
    DB  0xCE, 0x89, 75    ; ^E (first half)
    DB  0xC2, 0x06, 75    ; ^C (second half)
    DB  0xAD, 0x4B, 150   ; G

; Measure 33:  G    A    ^F   ^F   A
    DB  0xAD, 0x4B, 150   ; G
    DB  0xB6, 0x50, 150   ; A
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xB6, 0x50, 150   ; A

; Measure 34:  B    ^A   ^A   ^A   ^G   ^F
    DB  0xBE, 0x54, 150   ; B
    DB  0xDB, 0x28, 150   ; ^A
    DB  0xDB, 0x28, 150   ; ^A
    DB  0xDB, 0x28, 150   ; ^A
    DB  0xD6, 0x66, 150   ; ^G
    DB  0xD1, 0x69, 150   ; ^F

; Measure 35:  ^E   ^C   A   G
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xB6, 0x50, 150   ; A
    DB  0xAD, 0x4B, 150   ; G

;-----------------------------------
; Measure 36:  ^E-^C   G
; Again, a tied pair:
    DB  0xCE, 0x89, 75    ; ^E (first half)
    DB  0xC2, 0x06, 75    ; ^C (second half)
    DB  0xAD, 0x4B, 150   ; G

; Measure 37:  G    A    ^F   ^F   A
    DB  0xAD, 0x4B, 150   ; G
    DB  0xB6, 0x50, 150   ; A
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xB6, 0x50, 150   ; A

; Measure 38:  B    ^F   ^F   ^F   ^E   ^D   ^C
    DB  0xBE, 0x54, 150   ; B
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xD1, 0x69, 150   ; ^F
    DB  0xCE, 0x89, 150   ; ^E
    DB  0xC8, 0xCB, 150   ; ^D
    DB  0xC2, 0x06, 150   ; ^C

; Measure 39:  G   E   C
    DB  0xAD, 0x4B, 150   ; G
    DB  0x9D, 0x0A, 150   ; E
    DB  0x83, 0xE1, 150   ; C   (C4)

;-----------------------------------
; Measure 40:  ^C   G   E
    DB  0xC2, 0x06, 150   ; ^C
    DB  0xAD, 0x4B, 150   ; G
    DB  0x9D, 0x0A, 150   ; E

; Measure 41:  A   B   A
    DB  0xB6, 0x50, 150   ; A
    DB  0xBE, 0x54, 150   ; B
    DB  0xB6, 0x50, 150   ; A

; Measure 42:  G#   Bb   G#
    DB  0xB1, 0x8C, 150   ; G# (G#4 ≈415 Hz)
    DB  0xBA, 0x72, 150   ; Bb  (Bb4)
    DB  0xB1, 0x8C, 150   ; G# 

; Measure 43:  G - F# - G
; Here the “-” indicates that the notes are connected (played legato);
; we treat each note with the default duration.
    DB  0xAD, 0x4B, 150   ; G  (G4)
    DB  0xA8, 0x02, 150   ; F# (F#4 ≈370 Hz)
    DB  0xAD, 0x4B, 150   ; G  (G4)

; End marker: three zero bytes resets the song pointer.
    DB  0, 0, 0
END
