cseg

;----------------------------------------------------------
; Takes 128 ADC measurements and averages the result
;----------------------------------------------------------
Average_ADC:
    Load_x(0)
    mov R5, #128
Sum_loop0:
    lcall Read_ADC
    mov y+3, #0
    mov y+2, #0
    mov y+1, R1
    mov y+0, R0
    lcall add32
    djnz R5, Sum_loop0
    Load_y(128)
    lcall div32
    ret

Read_ADC:
    clr ADCF
    setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete
    
    ; Read the ADC result and store in [R1, R0]
    mov a, ADCRL
    anl a, #0x0f
    mov R0, a
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, R0
    mov R0, A
	ret

;----------------------------------------------------------
; Send eight bit number via serial port, passed in 'a'.
;----------------------------------------------------------
SendToSerialPort mac
    mov a, %0
    lcall ?SendToSerialPort
endmac

?SendToSerialPort:
    mov b, #100
    div ab
    orl a, #0x30  ; Convert hundreds to ASCII
    lcall putchar ; Send to PuTTY/Python/Matlab
    mov a, b      ; Remainder is in register b
    mov b, #10
    div ab
    orl a, #0x30  ; Convert tens to ASCII
    lcall putchar ; Send to PuTTY/Python/Matlab
    mov a, b      ; Remainder is in register b
    orl a, #0x30  ; Convert ones to ASCII
    lcall putchar ; Send to PuTTY/Python/Matlab
    mov a, #'\r'
    lcall putchar
    mov a, #'\n'
    lcall putchar
    ret

;----------------------------------------------------------
; Eight bit number to display to LCD, passed in 'a'.
;----------------------------------------------------------
SendToLCD mac
    mov a, %0
    lcall ?SendToLCD
endmac

?SendToLCD:
    mov b, #100
    div ab
    orl a, #0x30     ; Convert hundreds to ASCII
    lcall ?WriteData ; Send to LCD
    mov a, b         ; Remainder is in register b
    mov b, #10
    div ab
    orl a, #0x30     ; Convert tens to ASCII
    lcall ?WriteData ; Send to LCD
    mov a, b         ; Remainder is in register b
    orl a, #0x30     ; Convert ones to ASCII
    lcall ?WriteData ; Send to LCD
    ret
