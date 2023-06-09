;**** **** **** **** ****
;
; Bluejay digital ESC firmware for controlling brushless motors in multirotors
;
; Copyleft  2022-2023 Daniel Mosquera
; Copyright 2020-2022 Mathias Rasmussen
; Copyright 2011-2017 Steffen Skaug
;
; This file is part of Bluejay.
;
; Bluejay is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; Bluejay is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with Bluejay.  If not, see <http://www.gnu.org/licenses/>.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Interrupt handlers
;
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
    push PSW
    mov  PSW, #10h                      ; Select register bank 2 for this interrupt

    dec  Temp1
    cjne Temp1, #(Temp_Storage - 1),t0_int_dshot_tlm_transition

    inc  Temp1                          ; Set pointer to uncritical position

    ; If last pulse is high, telemetry is finished,
    ; otherwise wait for it to return to high
    jb   RTX_BIT, t0_int_dshot_tlm_finish

t0_int_dshot_tlm_transition:
    cpl  RTX_BIT                        ; Invert signal level

    mov  TL0, @Temp1                    ; Schedule next update

    pop  PSW
    reti

t0_int_dshot_tlm_finish:
    ; Configure RTX_PIN for digital input
    anl  RTX_MDOUT, #(NOT (1 SHL RTX_PIN)) ; Set RTX_PIN output mode to open-drain
    setb RTX_BIT                        ; Float high

    clr  IE_ET0                         ; Disable Timer0 interrupts

    mov  CKCON0, Temp8                  ; Restore regular DShot Timer0/1 clock settings
    mov  TMOD, #0AAh                    ; Timer0/1 gated by Int0/1

    clr  TCON_IE0                       ; Clear Int0 pending flag
    clr  TCON_IE1                       ; Clear Int1 pending flag

    mov  TL0, #0                        ; Reset Timer0 count
    setb IE_EX0                         ; Enable Int0 interrupts
    setb IE_EX1                         ; Enable Int1 interrupts

    clr  Flag_Telemetry_Pending         ; Mark that new telemetry packet may be created

    pop  PSW
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
    clr  IE_EX0                         ; Disable Int0 interrupts
    clr  TCON_TR1                       ; Stop Timer1
    mov  TL1, DShot_Timer_Preset        ; Reset sync timer

    push PSW
    mov  PSW, #8h                       ; Select register bank 1 for this interrupt
    push ACC
    push B

    ; Note: Interrupts are not explicitly disabled
    ; Assume higher priority interrupts (Int0, Timer0) to be disabled at this point
    clr  TMR2CN0_TR2                    ; Timer2 disabled
    mov  Temp2, TMR2L                   ; Read timer value
    mov  Temp3, TMR2H
    setb TMR2CN0_TR2                    ; Timer2 enabled

    ; Check frame time length
    clr  C
    mov  A, Temp2
    subb A, DShot_Frame_Start_L
    mov  Temp2, A
    mov  A, Temp3
    subb A, DShot_Frame_Start_H
    jnz  t1_int_frame_fail              ; Frame too long

    clr  C
    mov  A, Temp2
    subb A, DShot_Frame_Length_Thr
    jc   t1_int_frame_fail              ; Frame too short
    subb A, DShot_Frame_Length_Thr
    jnc  t1_int_frame_fail              ; Frame too long

    ; Check that correct number of pulses is received
    cjne Temp1, #16, t1_int_frame_fail  ; Read current pointer

    ; Decode transmitted data
    mov  Temp1, #0                      ; Set pointer
    mov  Temp2, DShot_Pwm_Thr           ; DShot pulse width criteria
    mov  Temp6, #0                      ; Reset timestamp

    ; Decode DShot data Msb. Use more code space to save time (by not using loop)
    Decode_DShot_2Bit Temp5, t1_int_frame_fail
    Decode_DShot_2Bit Temp5, t1_int_frame_fail
    sjmp t1_int_decode_lsb

t1_int_frame_fail:
    sjmp t1_int_outside_range

t1_int_decode_lsb:
    ; Decode DShot data Lsb
    Decode_DShot_2Bit Temp4, t1_int_outside_range
    Decode_DShot_2Bit Temp4, t1_int_outside_range
    Decode_DShot_2Bit Temp4, t1_int_outside_range
    Decode_DShot_2Bit Temp4, t1_int_outside_range
    sjmp t1_int_decode_checksum

t1_int_outside_range:
    inc  Rcp_Outside_Range_Cnt
    mov  A, Rcp_Outside_Range_Cnt
    jnz  ($+4)
    dec  Rcp_Outside_Range_Cnt

    clr  C
    mov  A, Rcp_Outside_Range_Cnt
    subb A, #50                         ; Allow a given number of outside pulses
    jc   t1_int_exit_timeout            ; If outside limits - ignore first pulses

    ; RCP signal has not timed out, but pulses are not recognized as DShot
    setb Flag_Rcp_Stop                  ; Set pulse length to zero
    mov  DShot_Cmd, #0                  ; Reset DShot command
    mov  DShot_Cmd_Cnt, #0

    ajmp t1_int_exit_no_tlm             ; Exit without resetting timeout

t1_int_exit_timeout:
    mov  Rcp_Timeout_Cntd, #10          ; Set timeout count
    ajmp t1_int_exit_no_tlm

t1_int_decode_checksum:
    ; Decode DShot data checksum
    Decode_DShot_2Bit Temp3, t1_int_outside_range
    Decode_DShot_2Bit Temp3, t1_int_outside_range

    ; XOR check (in inverted data, which is ok), only low nibble is considered
    mov  A, Temp4
    swap A
    xrl  A, Temp4
    xrl  A, Temp5
    xrl  A, Temp3
    jnb  Flag_Rcp_DShot_Inverted, ($+4)
    cpl  A                              ; Invert checksum if using inverted DShot
    anl  A, #0Fh
    jnz  t1_int_outside_range           ; XOR check

    ; Invert DShot data and subtract 96 (still 12 bits)
    clr  C
    mov  A, Temp4
    cpl  A
    mov  Temp3, A                       ; Store in case it is a DShot command
    subb A, #96
    mov  Temp4, A
    mov  A, Temp5
    cpl  A
    anl  A, #0Fh
    subb A, #0
    mov  Temp5, A
    jnc  t1_int_normal_range

    mov  A, Temp3                       ; Check for 0 or DShot command
    mov  Temp5, #0
    mov  Temp4, #0
    jz   t1_int_dshot_set_cmd           ; Clear DShot command when RCP is zero

    clr  C                              ; We are in the special DShot range
    rrc  A                              ; Shift tlm bit into carry
    jnc  t1_int_dshot_clear_cmd         ; Check for tlm bit set (if not telemetry,invalid command)

    cjne A, DShot_Cmd, t1_int_dshot_set_cmd

    inc  DShot_Cmd_Cnt
    sjmp t1_int_normal_range

t1_int_dshot_clear_cmd:
    clr  A

t1_int_dshot_set_cmd:
    mov  DShot_Cmd, A
    mov  DShot_Cmd_Cnt, #0

t1_int_normal_range:
    ; Check for bidirectional operation (0=stop, 96-2095->fwd, 2096-4095->rev)
    jnb  Flag_Pgm_Bidir, t1_int_not_bidir ; If not bidirectional operation - branch

    ; Subtract 2000 (still 12 bits)
    clr  C
    mov  A, Temp4
    subb A, #0D0h
    mov  B, A
    mov  A, Temp5
    subb A, #07h
    jc   t1_int_bidir_set               ; Is result is positive?
    mov  Temp4, B                       ; Yes - Use the subtracted value
    mov  Temp5, A

t1_int_bidir_set:
    jnb  Flag_Pgm_Dir_Rev, ($+4)        ; Check programmed direction
    cpl  C                              ; Reverse direction
    mov  Flag_Rcp_Dir_Rev, C            ; Set rcp direction

    clr  C                              ; Multiply throttle value by 2
    rlca Temp4
    rlca Temp5

t1_int_not_bidir:
    ; From here Temp5/Temp4 should be at most 3999 (4095-96)
    mov  A, Temp4                       ; Divide by 16 (12 to 8-bit)
    anl  A, #0F0h
    orl  A, Temp5                       ; Note: Assumes Temp5 to be 4-bit
    swap A
    mov  B, #5                          ; Divide by 5 (80 in total)
    div  AB
    mov  Temp3, A

    ; Align to 11 bits
    ;clr    C                       ; Note: Cleared by div
    rrca Temp5
    mov  A, Temp4
    rrc  A

    ; Scale from 2000 to 2048
    add  A, Temp3
    mov  Temp4, A
    mov  A, Temp5
    addc A, #0
    mov  Temp5, A
    jnb  ACC.3, ($+7)                   ; Limit to 11-bit maximum
    mov  Temp4, #0FFh
    mov  Temp5, #07h

    ; Do not boost when changing direction in bidirectional mode
    jb   Flag_Motor_Started, t1_int_startup_boosted

    ; Boost pwm during direct start
    jnb  Flag_Initial_Run_Phase, t1_int_startup_boosted

    mov  A, Temp5
    jnz  t1_int_stall_boost             ; Already more power than minimum at startup

    mov  Temp2, #Pgm_Startup_Power_Min  ; Read minimum startup power setting
    mov  B, @Temp2

    clr  C                              ; Set power to at least be minimum startup power
    mov  A, Temp4
    subb A, B
    jnc  t1_int_stall_boost
    mov  Temp4, B

t1_int_stall_boost:
    mov  A, Startup_Stall_Cnt           ; Check stall count
    jz   t1_int_startup_boosted
    mov  B, #40                         ; Note: Stall count should be less than 6
    mul  AB

    add  A, Temp4                       ; Add more power when failing to start motor (stalling)
    mov  Temp4, A
    mov  A, Temp5
    addc A, #0
    mov  Temp5, A
    jnb  ACC.3, ($+7)                   ; Limit to 11-bit maximum
    mov  Temp4, #0FFh
    mov  Temp5, #07h

t1_int_startup_boosted:
    ; Set 8-bit value
    mov  A, Temp4
    anl  A, #0F8h
    orl  A, Temp5                       ; Assumes Temp5 to be 3-bit (11-bit rcp)
    swap A
    rl   A
    mov  Temp2, A

    jnz  t1_int_rcp_not_zero

    mov  A, Temp4                       ; Only set Rcp_Stop if all all 11 bits are zero
    jnz  t1_int_rcp_not_zero

    setb Flag_Rcp_Stop
    sjmp t1_int_zero_rcp_checked

t1_int_rcp_not_zero:
    mov  Rcp_Stop_Cnt, #0               ; Reset rcp stop counter
    clr  Flag_Rcp_Stop                  ; Pulse ready

t1_int_zero_rcp_checked:
    ; Decrement outside range counter
    mov  A, Rcp_Outside_Range_Cnt
    jz   ($+4)
    dec  Rcp_Outside_Range_Cnt

    ; Set pwm limit
    clr  C
    mov  A, Pwm_Limit                   ; Limit to the smallest
    mov  Temp6, A                       ; Store limit in Temp6
    subb A, Pwm_Limit_By_Rpm
    jc   ($+4)
    mov  Temp6, Pwm_Limit_By_Rpm

    ; Check against limit
    clr  C
    mov  A, Temp6
    subb A, Temp2                       ; 8-bit rc pulse
    jnc  t1_int_scale_pwm_resolution

IF PWM_BITS_H == PWM_8_BIT              ; 8-bit pwm
    mov  A, Temp6
    mov  Temp2, A
ELSE
    mov  A, Temp6                       ; Multiply limit by 8 for 11-bit pwm
    mov  B, #8
    mul  AB
    mov  Temp4, A
    mov  Temp5, B
ENDIF

t1_int_scale_pwm_resolution:
; Scale pwm resolution and invert (duty cycle is defined inversely)
IF PWM_BITS_H == PWM_11_BIT
    mov  A, Temp5
    cpl  A
    anl  A, #7
    mov  Temp3, A
    mov  A, Temp4
    cpl  A
    mov  Temp2, A
ELSEIF PWM_BITS_H == PWM_10_BIT
    clr  C
    mov  A, Temp5
    rrc  A
    cpl  A
    anl  A, #3
    mov  Temp3, A
    mov  A, Temp4
    rrc  A
    cpl  A
    mov  Temp2, A
ELSEIF PWM_BITS_H == PWM_9_BIT
    mov  B, Temp5
    mov  A, Temp4
    mov  C, B.0
    rrc  A
    mov  C, B.1
    rrc  A
    cpl  A
    mov  Temp2, A
    mov  A, Temp5
    rr   A
    rr   A
    cpl  A
    anl  A, #1
    mov  Temp3, A
ELSEIF PWM_BITS_H == PWM_8_BIT
    mov  A, Temp2                       ; Temp2 already 8-bit
    cpl  A
    mov  Temp2, A
    mov  Temp3, #0
ENDIF

; 11-bit effective dithering of 8/9/10-bit pwm
IF PWM_BITS_H == PWM_8_BIT or PWM_BITS_H == PWM_9_BIT or PWM_BITS_H == PWM_10_BIT
    jnb  Flag_Dithering, t1_int_set_pwm

    mov  A, Temp4                       ; 11-bit low byte
    cpl  A
    anl  A, #((1 SHL (3 - PWM_BITS_H)) - 1); Get index into dithering pattern table

    add  A, #Dithering_Patterns
    mov  Temp1, A                       ; Reuse DShot pwm pointer since it is not currently in use.
    mov  A, @Temp1                      ; Retrieve pattern
    rl   A                              ; Rotate pattern
    mov  @Temp1, A                      ; Store pattern

    jnb  ACC.0, t1_int_set_pwm          ; Increment if bit is set

    mov  A, Temp2
    add  A, #1
    mov  Temp2, A
    jnz  t1_int_set_pwm
IF PWM_BITS_H != PWM_8_BIT
    mov  A, Temp3
    addc A, #0
    mov  Temp3, A
    jnb  ACC.PWM_BITS_H, t1_int_set_pwm
    dec  Temp3                          ; Reset on overflow
ENDIF
    dec  Temp2
ENDIF

t1_int_set_pwm:
; Set pwm registers
IF DEADTIME != 0
    ; Subtract dead time from normal pwm and store as damping pwm
    ; Damping pwm duty cycle will be higher because numbers are inverted
    clr  C
    mov  A, Temp2                       ; Skew damping FET timing
IF MCU_TYPE == MCU_BB1
    subb A, #((DEADTIME + 1) SHR 1)
ELSE
    subb A, #(DEADTIME)
ENDIF
    mov  Temp4, A
    mov  A, Temp3
    subb A, #0
    mov  Temp5, A
    jnc  t1_int_max_braking_set

    clr  A                              ; Set to minimum value
    mov  Temp4, A
    mov  Temp5, A
    sjmp t1_int_pwm_braking_set         ; Max braking is already zero - branch

t1_int_max_braking_set:
    clr  C
    mov  A, Temp4
    subb A, Pwm_Braking_L
    mov  A, Temp5
    subb A, Pwm_Braking_H               ; Is braking pwm more than maximum allowed braking?
    jc   t1_int_pwm_braking_set         ; Yes - branch
    mov  Temp4, Pwm_Braking_L           ; No - set desired braking instead
    mov  Temp5, Pwm_Braking_H

t1_int_pwm_braking_set:
ENDIF

; Note: Interrupts are not explicitly disabled
; Assume higher priority interrupts (Int0, Timer0) to be disabled at this point
IF PWM_BITS_H != PWM_8_BIT
    ; Set power pwm auto-reload registers
    Set_Power_Pwm_Reg_L Temp2
    Set_Power_Pwm_Reg_H Temp3
ELSE
    Set_Power_Pwm_Reg_H Temp2
ENDIF

IF DEADTIME != 0
    ; Set damp pwm auto-reload registers
IF PWM_BITS_H != PWM_8_BIT
    Set_Damp_Pwm_Reg_L Temp4
    Set_Damp_Pwm_Reg_H Temp5
ELSE
    Set_Damp_Pwm_Reg_H Temp4
ENDIF
ENDIF

    mov  Rcp_Timeout_Cntd, #10          ; Set timeout count

    ; Prepare DShot telemetry
    jnb  Flag_Rcp_DShot_Inverted, t1_int_exit_no_tlm ; Only send telemetry for inverted DShot
    jnb  Flag_Telemetry_Pending, t1_int_exit_no_tlm ; Check if telemetry packet is ready

    ; Prepare Timer0 for sending telemetry data
    mov  CKCON0, #01h                   ; Timer0 is system clock divided by 4
    mov  TMOD, #0A2h                    ; Timer0 runs free not gated by Int0

    ; Configure RTX_PIN for digital output
    setb RTX_BIT                        ; Default to high level
    orl  RTX_MDOUT, #(1 SHL RTX_PIN)    ; Set output mode to push-pull

    mov  Temp1, #0                      ; Set pointer to start

    ; Note: Delay must be large enough to ensure port is ready for output
    mov  TL0, DShot_GCR_Start_Delay     ; Telemetry will begin after this delay
    clr  TCON_TF0                       ; Clear Timer0 overflow flag
    setb IE_ET0                         ; Enable Timer0 interrupts

    sjmp t1_int_exit_no_int

t1_int_exit_no_tlm:
    mov  Temp1, #0                      ; Set pointer to start
    mov  TL0, #0                        ; Reset Timer0
    setb IE_EX0                         ; Enable Int0 interrupts
    setb IE_EX1                         ; Enable Int1 interrupts

t1_int_exit_no_int:
    pop  B                              ; Restore preserved registers
    pop  ACC
    pop  PSW
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
    clr  TMR2CN0_TF2H                   ; Clear interrupt flag
    inc  Timer2_X                       ; Increment extended byte
    setb Flag_32ms_Elapsed              ; Set 32ms elapsed flag

    ; Check RC pulse timeout counter
    mov  A, Rcp_Timeout_Cntd            ; RC pulse timeout count zero?
    jnz  t2_int_rcp_timeout_decrement
    setb Flag_Rcp_Stop                  ; If zero -> Set rcp stop in case of timeout
    sjmp t2_int_flag_rcp_stop_check

t2_int_rcp_timeout_decrement:
    dec  Rcp_Timeout_Cntd               ; No - decrement

t2_int_flag_rcp_stop_check:
    ; If rc pulse is not zero
    jnb  Flag_Rcp_Stop, t2_int_exit     ; If rc pulse is not zero don't increment rcp stop counter

    ; Increment Rcp_Stop_Cnt clipping it to 255
    mov  A, Rcp_Stop_Cnt
    inc  A
    jz   ($+4)
    inc  Rcp_Stop_Cnt

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Return from timer2
;**** **** **** **** **** **** **** **** **** **** **** **** ****
t2_int_exit:
    pop  ACC                            ; Restore preserved registers
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
    clr  IE_EA                          ; Disable all interrupts
    anl  EIE1, #7Fh                     ; Disable Timer3 interrupts
    anl  TMR3CN0, #07Fh                 ; Clear Timer3 interrupt flag
    mov  TMR3RLL, #0FAh                 ; Short delay to avoid re-loading regular delay
    mov  TMR3RLH, #0FFh
    clr  Flag_Timer3_Pending            ; Flag that timer has wrapped
    setb IE_EA                          ; Enable all interrupts
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
    push ACC
    mov  A, TL0                         ; Read pwm for DShot immediately
    mov  TL1, DShot_Timer_Preset        ; Reset sync timer

; Temp1 in register bank 1 points to pwm timings
    push PSW
    mov  PSW, #8h
    movx @Temp1, A                      ; Store pwm in external memory
    inc  Temp1
    pop  PSW

    pop  ACC
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
    clr  IE_EX1                         ; Disable Int1 interrupts
    setb TCON_TR1                       ; Start Timer1

    ; Note: Interrupts are not explicitly disabled, assuming higher priority interrupts:
    ; - Timer0 to be disabled at this point
    ; - Int0 to not trigger for valid DShot signal
    clr  TMR2CN0_TR2                    ; Timer2 disabled
    mov  DShot_Frame_Start_L, TMR2L     ; Read timer value
    mov  DShot_Frame_Start_H, TMR2H
    setb TMR2CN0_TR2                    ; Timer2 enabled
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
