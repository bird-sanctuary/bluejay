;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Interrupt handlers
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Timer0 interrupt routine (High priority)
;
; Generate DShot telemetry signal
;
; Requirements:
; - Must NOT be called while Flag_Telemetry_Pending is cleared
; - Must NOT write to Temp7, Temp8
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
t0_int:
    push    PSW
    mov PSW, #10h                   ; Select register bank 2 for this interrupt

    dec Temp1
    cjne    Temp1, #(Temp_Storage - 1), t0_int_dshot_tlm_transition

    inc Temp1                   ; Set pointer to uncritical position

    ; If last pulse is high, telemetry is finished,
    ; otherwise wait for it to return to high
    jb  RTX_BIT, t0_int_dshot_tlm_finish

t0_int_dshot_tlm_transition:
    cpl RTX_BIT                 ; Invert signal level

    mov TL0, @Temp1             ; Schedule next update

    pop PSW
    reti

t0_int_dshot_tlm_finish:
    ; Configure RTX_PIN for digital input
    anl RTX_MDOUT, #(NOT (1 SHL RTX_PIN))   ; Set RTX_PIN output mode to open-drain
    setb    RTX_BIT                 ; Float high

    clr IE_ET0                  ; Disable Timer0 interrupts

    mov CKCON0, Temp8               ; Restore regular DShot Timer0/1 clock settings
    mov TMOD, #0AAh             ; Timer0/1 gated by Int0/1

    clr TCON_IE0                    ; Clear Int0 pending flag
    clr TCON_IE1                    ; Clear Int1 pending flag

    mov TL0, #0                 ; Reset Timer0 count
    setb    IE_EX1                  ; Enable Int1 interrupts

    clr Flag_Telemetry_Pending      ; Mark that new telemetry packet may be created

    pop PSW
    reti


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Int0 interrupt routine (High priority)
;
; Read and store DShot pwm dominant bit time in XRAM
; Resets Timer1 to continue reading bits. When Timer1 triggers
; the end of the frame is being signaled so it can be processed there.
;
; Requirements: Int0 shall be enabled in Int1 isr
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
int0_int:
    push    ACC
    mov A, TL0                      ; Read DShot dominant bit time
    mov TL1, DShot_Timer_Preset     ; Reset sync timer

    ; Temp1 in register bank 1 points to pwm timings
    push    PSW
    mov PSW, #8h

    ; Detect bad frame because of DShot bit count overflow.
    ; Avoid dirting XRAM and DShot noise (low probability but
    ; still possible) problematic corner cases.
    cjne Temp1, #17, int0_int_add_bit_time
    sjmp int0_int_end

int0_int_add_bit_time:
    ; Store bit time in external memory
    movx    @Temp1, A
    inc Temp1

int0_int_end:
    pop PSW
    pop ACC
    reti


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Int1 interrupt routine
;
; Used to know when RC pulse frame starts:
; When a dshot frame starts it sets DShot_Frame_Start,
; disables Int1, and enables Int0.
; From here next stage is:
;   - in Int0, frame bit lenghts are read from timer0 and stored in XRAM.
;
; Requirements: No PSW instructions or Temp/Acc registers
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
int1_int:
    ; Frame start is detected, so:
    ; - Int1 is not needed anymore until next frame processing
    ; - Now start timer1 to count bit timings when int0 interrupts are triggered
    ; - Also Enable Int0 interrupts from here
    clr IE_EX1                  ; Disable Int1 interrupts
    mov TH1, DShot_Timer_Preset ; Reset Timer1
    mov TL1, DShot_Timer_Preset ; Sync Timer1
    setb    TCON_TR1            ; Start Timer1
    setb    IE_EX0              ; Enable Int0 interrupts

    ; Note: Interrupts are not explicitly disabled, assuming higher priority interrupts:
    ; - Timer0 to be disabled at this point because it cannot be sending telemetry:
    ; Or dshot frame is being received or telemetry is being sent
    clr TMR2CN0_TR2             	; Timer2 disabled
    mov DShot_Frame_Start_L, TMR2L  ; Read timer value
    mov DShot_Frame_Start_H, TMR2H
    setb    TMR2CN0_TR2             ; Timer2 enabled

	reti


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Timer1 interrupt routine
;
; Decode DShot frame
; Process new throttle value and update pwm registers
; Schedule DShot telemetry
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
t1_int:
    push    PSW
    mov PSW, #8h                    ; Select register bank 1 for this interrupt
    push    ACC

    ; Check that DSHOT rcpulse state machine state is done to load new rcpulse
    mov A, DShot_rcpulse_stm_state
    jz t1_int_decode

    ; Configure RTX_PIN for digital output
    clr    RTX_BIT                 ; Default to high level
    orl RTX_MDOUT, #(1 SHL RTX_PIN) ; Set output mode to push-pull
    setb    RTX_BIT                 ; Default to high level
    ; Configure RTX_PIN for digital input
    anl RTX_MDOUT, #(NOT (1 SHL RTX_PIN))   ; Set RTX_PIN output mode to open-drain

    jmp dshot_rcpulse_stm

t1_int_decode:
    clr IE_EX0                  	; Disable Int0 interrupts
    clr TCON_TR1                    ; Stop Timer1

    mov Temp7, #0
    ; Check that correct number of bits is received
    cjne    Temp1, #16, t1_int_frame_fail   ; Read current pointer

    ; Note: Interrupts are not explicitly disabled
    ; Assume higher priority interrupts (Int0, Timer0) to be disabled at this point
    clr TMR2CN0_TR2             ; Timer2 disabled
    mov Temp2, TMR2L                ; Read timer value
    mov Temp3, TMR2H
    setb    TMR2CN0_TR2             ; Timer2 enabled

    mov Temp7, #1
    ; Check frame time length
    clr C
    mov A, Temp2
    subb    A, DShot_Frame_Start_L
    mov Temp2, A
    mov A, Temp3
    subb    A, DShot_Frame_Start_H
    jnz t1_int_frame_fail           ; Frame too long

    mov Temp7, #2
    clr C
    mov A, Temp2
    subb    A, DShot_Frame_Length_Thr
    jc  t1_int_frame_fail           ; Frame too short
    subb    A, DShot_Frame_Length_Thr
    jnc t1_int_frame_fail           ; Frame too long

    mov Temp7, #3
    ; Decode transmitted data
    mov Temp1, #0                   ; Set pointer
    mov Temp2, DShot_Pwm_Thr        ; DShot pulse width criteria
    mov Temp6, #0                   ; Reset timestamp

    mov Temp7, #4
    ; Decode DShot data Msb. Use more code space to save time (by not using loop)
    Decode_DShot_2Bit   Temp5, t1_int_frame_fail
    Decode_DShot_2Bit   Temp5, t1_int_frame_fail
    sjmp    t1_int_decode_lsb

t1_int_frame_fail:
    sjmp    t1_int_outside_range

t1_int_decode_lsb:
    ; Decode DShot data Lsb
    Decode_DShot_2Bit   Temp4, t1_int_outside_range
    Decode_DShot_2Bit   Temp4, t1_int_outside_range
    Decode_DShot_2Bit   Temp4, t1_int_outside_range
    Decode_DShot_2Bit   Temp4, t1_int_outside_range
    sjmp    t1_int_decode_checksum

t1_int_outside_range:
    ; Increase dshot error counter, no matter it overflows
    inc DShot_Err_Counter

    ; Increase outside range counter
    inc Rcp_Outside_Range_Cnt
    mov A, Rcp_Outside_Range_Cnt
    jnz ($+4)
    dec Rcp_Outside_Range_Cnt

    clr C
    mov A, Rcp_Outside_Range_Cnt
    subb    A, #50                  ; Allow a given number of outside pulses
    jc  t1_int_exit_timeout         ; If outside limits - ignore first pulses

    ; RCP signal has not timed out, but pulses are not recognized as DShot
    setb    Flag_Rcp_Stop               ; Set pulse length to zero
    mov DShot_Cmd, #0               ; Reset DShot command
    mov DShot_Cmd_Cnt, #0

    ajmp    t1_int_exit_no_tlm          ; Exit without resetting timeout

t1_int_exit_timeout:
    mov Rcp_Timeout_Cntd, #10       ; Set timeout count
    ajmp    t1_int_exit_no_tlm

t1_int_decode_checksum:
    ; Decode DShot data checksum
    Decode_DShot_2Bit   Temp3, t1_int_outside_range
    Decode_DShot_2Bit   Temp3, t1_int_outside_range

    ; XOR check (in inverted data, which is ok), only low nibble is considered
    mov A, Temp4
    swap    A
    xrl A, Temp4
    xrl A, Temp5
    xrl A, Temp3
    jnb Flag_Rcp_DShot_Inverted, ($+4)
    cpl A                       ; Invert checksum if using inverted DShot
    anl A, #0Fh
    jnz t1_int_outside_range        ; XOR check

t1_int_rcpulse_stm_load:
	; Set timeout count
    mov Rcp_Timeout_Cntd, #10

    ; Kick dshot rcpulse state machine
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_START

	; Configure timer to process rcpulse every 120 clk ticks
    mov TL1, #(155) 			; Sync Timer1
    mov TH1, #(155) 			; Reset Timer1
    setb    TCON_TR1            ; Start Timer1

    sjmp t1_int_exit_no_int

t1_int_rcpulse_stm_ready:
;    ; Check DShot telemetry has to be sent
;    jnb Flag_Rcp_DShot_Inverted, t1_int_exit_no_tlm ; Only send telemetry for inverted DShot
;    jnb Flag_Telemetry_Pending, t1_int_exit_no_tlm  ; Check if telemetry packet is ready
;
;    ; Prepare Timer0 for sending telemetry data
;    mov CKCON0, #01h                ; Timer0/1 is system clock divided by 4
;    mov TMOD, #0A2h             ; Timer0 runs free not gated by Int0
;
;    ; Configure RTX_PIN for digital output
;    setb    RTX_BIT                 ; Default to high level
;    orl RTX_MDOUT, #(1 SHL RTX_PIN) ; Set output mode to push-pull
;
;    mov Temp1, #0                   ; Set pointer to start
;
;    ; Note: Delay must be large enough to ensure port is ready for output
;    mov TL0, DShot_GCR_Start_Delay  ; Telemetry will begin after this delay
;    clr TCON_TF0                    ; Clear Timer0 overflow flag
;    setb    IE_ET0                  ; Enable Timer0 interrupts
;
;    sjmp    t1_int_exit_no_int

t1_int_exit_no_tlm:
	; Capture new frame
    mov Temp1, #0                   ; Set pointer to start
    mov TL0, #0                 	; Reset Timer0
    setb    IE_EX1                  ; Enable Int1 interrupts

t1_int_exit_no_int:
    ; Restore preserved registers
    pop ACC
    pop PSW
    reti


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Timer2 interrupt routine
;
; Update RC pulse timeout and stop counters
; Happens every 32ms
;
; Requirements: No PSW instructions or Temp registers
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
t2_int:
    push ACC
    clr TMR2CN0_TF2H                        ; Clear interrupt flag
    inc Timer2_X                            ; Increment extended byte
    setb Flag_32ms_Elapsed                  ; Set 32ms elapsed flag

    ; Check RC pulse timeout counter
    mov A, Rcp_Timeout_Cntd                 ; RC pulse timeout count zero?
    jnz t2_int_rcp_timeout_decrement
    setb Flag_Rcp_Stop                      ; If zero -> Set rcp stop in case of timeout
    sjmp t2_int_flag_rcp_stop_check

t2_int_rcp_timeout_decrement:
    dec Rcp_Timeout_Cntd                    ; No - decrement

t2_int_flag_rcp_stop_check:
    ; If rc pulse is not zero
    jnb Flag_Rcp_Stop, t2_int_exit          ; If rc pulse is not zero don't increment rcp stop counter

    ; Increment Rcp_Stop_Cnt clipping it to 255
    mov A, Rcp_Stop_Cnt
    inc A
    jz ($+4)
    inc Rcp_Stop_Cnt

; **************   Return from timer2 **********
t2_int_exit:
    pop ACC                     ; Restore preserved registers
    reti


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Timer3 interrupt routine
;
; Used for commutation timing
;
; Requirements: No PSW instructions or Temp/Acc/B registers
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
t3_int:
    clr IE_EA                   ; Disable all interrupts
    anl EIE1, #7Fh              ; Disable Timer3 interrupts
    anl TMR3CN0, #07Fh              ; Clear Timer3 interrupt flag
    mov TMR3RLL, #0FAh              ; Short delay to avoid re-loading regular delay
    mov TMR3RLH, #0FFh
    clr Flag_Timer3_Pending         ; Flag that timer has wrapped
    setb    IE_EA                   ; Enable all interrupts
    reti


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; PCA interrupt routine
;
; Update pwm registers according to PCA clock signal
;
; Requirements: No PSW instructions or Temp registers
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
pca_int:
    reti

