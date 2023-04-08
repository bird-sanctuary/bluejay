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
    setb    IE_EX0                  ; Enable Int0 interrupts
    setb    IE_EX1                  ; Enable Int1 interrupts

    clr Flag_Telemetry_Pending      ; Mark that new telemetry packet may be created

    pop PSW
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
    clr IE_EX0                  ; Disable Int0 interrupts
    clr TCON_TR1                    ; Stop Timer1
    mov TL1, DShot_Timer_Preset     ; Reset sync timer

    push    PSW
    mov PSW, #8h                    ; Select register bank 1 for this interrupt
    push    ACC
    push    B

    ; Note: Interrupts are not explicitly disabled
    ; Assume higher priority interrupts (Int0, Timer0) to be disabled at this point
    clr TMR2CN0_TR2             ; Timer2 disabled
    mov Temp2, TMR2L                ; Read timer value
    mov Temp3, TMR2H
    setb    TMR2CN0_TR2             ; Timer2 enabled

    ; Check frame time length
    clr C
    mov A, Temp2
    subb    A, DShot_Frame_Start_L
    mov Temp2, A
    mov A, Temp3
    subb    A, DShot_Frame_Start_H
    jnz t1_int_frame_fail           ; Frame too long

    clr C
    mov A, Temp2
    subb    A, DShot_Frame_Length_Thr
    jc  t1_int_frame_fail           ; Frame too short
    subb    A, DShot_Frame_Length_Thr
    jnc t1_int_frame_fail           ; Frame too long

    ; Check that correct number of pulses is received
    cjne    Temp1, #16, t1_int_frame_fail   ; Read current pointer

    ; Decode transmitted data
    mov Temp1, #0                   ; Set pointer
    mov Temp2, DShot_Pwm_Thr        ; DShot pulse width criteria
    mov Temp6, #0                   ; Reset timestamp

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
    ; Check that DSHOT rcpulse state machine state is done to load new rcpulse
    mov A, DShot_rcpulse_stm_state
    cjne A, #DSHOT_RCPULSE_STATE_DONE, t1_int_rcpulse_stm_ready

    ; Kick dshot rcpulse state machine
    mov DShot_rcpulse_stm_pwm_t4, Temp4
    mov DShot_rcpulse_stm_pwm_t5, Temp5
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_START

t1_int_rcpulse_stm_ready:
    mov Rcp_Timeout_Cntd, #10       ; Set timeout count

    ; Check DShot telemetry has to be sent
    jnb Flag_Rcp_DShot_Inverted, t1_int_exit_no_tlm ; Only send telemetry for inverted DShot
    jnb Flag_Telemetry_Pending, t1_int_exit_no_tlm  ; Check if telemetry packet is ready

    ; Prepare Timer0 for sending telemetry data
    mov CKCON0, #01h                ; Timer0 is system clock divided by 4
    mov TMOD, #0A2h             ; Timer0 runs free not gated by Int0

    ; Configure RTX_PIN for digital output
    setb    RTX_BIT                 ; Default to high level
    orl RTX_MDOUT, #(1 SHL RTX_PIN) ; Set output mode to push-pull

    mov Temp1, #0                   ; Set pointer to start

    ; Note: Delay must be large enough to ensure port is ready for output
    mov TL0, DShot_GCR_Start_Delay  ; Telemetry will begin after this delay
    clr TCON_TF0                    ; Clear Timer0 overflow flag
    setb    IE_ET0                  ; Enable Timer0 interrupts

    sjmp    t1_int_exit_no_int

t1_int_exit_no_tlm:
    mov Temp1, #0                   ; Set pointer to start
    mov TL0, #0                 ; Reset Timer0
    setb    IE_EX0                  ; Enable Int0 interrupts
    setb    IE_EX1                  ; Enable Int1 interrupts

t1_int_exit_no_int:
    pop B                       ; Restore preserved registers
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

t2_int_check_demag_error_cycle_flag:
    ; Check demag error cycle flag, and clear it
    jbc Flag_Demag_Error_Cycle, t2_int_check_demag_error_cycle_inc

    ; During this 32ms cycle there were no demag errors, so clear the counter
    mov Demag_Error_Time_Counter, #0
    sjmp t2_int_check_rcpulse_timeout_counter

t2_int_check_demag_error_cycle_inc:
	; During this 32ms cycle there were demag errors, so increase the counter
	inc Demag_Error_Time_Counter

t2_int_check_rcpulse_timeout_counter:
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
; Int0 interrupt routine (High priority)
;
; Read and store DShot pwm signal for decoding
;
; Requirements: No PSW instructions
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
int0_int:
    push    ACC
    mov A, TL0                  ; Read pwm for DShot immediately
    mov TL1, DShot_Timer_Preset     ; Reset sync timer

    ; Temp1 in register bank 1 points to pwm timings
    push    PSW
    mov PSW, #8h
    movx    @Temp1, A                   ; Store pwm in external memory
    inc Temp1
    pop PSW

    pop ACC
    reti


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Int1 interrupt routine
;
; Used for RC pulse timing
;
; Requirements: No PSW instructions or Temp/Acc registers
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
int1_int:
    clr IE_EX1                  ; Disable Int1 interrupts
    setb    TCON_TR1                    ; Start Timer1

    ; Note: Interrupts are not explicitly disabled, assuming higher priority interrupts:
    ; - Timer0 to be disabled at this point
    ; - Int0 to not trigger for valid DShot signal
    clr TMR2CN0_TR2             ; Timer2 disabled
    mov DShot_Frame_Start_L, TMR2L  ; Read timer value
    mov DShot_Frame_Start_H, TMR2H
    setb    TMR2CN0_TR2             ; Timer2 enabled
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

