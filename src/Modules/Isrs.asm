;**** **** **** **** **** **** **** **** **** **** **** **** ****
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
; ASSERT:
; - Must NOT be called while Flag_Telemetry_Pending is cleared
; - Must NOT write to Temp7, Temp8
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
t0_int:
    push PSW
    mov  PSW, #10h                      ; Select register bank 2 for this interrupt

    dec  Temp1
    cjne Temp1, #(Temp_Storage - 1), t0_int_dshot_tlm_transition

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
; Tasks:
; - Decode DShot frame
; - Process new throttle value and update PWM registers
; - Schedule DShot telemetry
;
; NOTE: The ISR should be left as soon as possible. Instead of using loops,
;       often times more codespace is used since it saves valuable time.
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

    ; NOTE: Interrupts are not explicitly disabled. Assume higher priority
    ;       interrupts (Int0, Timer0) to be disabled at this point.
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

    ; Check that correct number (16) of pulses is received
    cjne Temp1, #16, t1_int_frame_fail  ; Read current pointer

    ; Decode transmitted data
    mov  Temp1, #0                      ; Set pointer
    mov  Temp2, DShot_Pwm_Thr           ; DShot pulse width criteria
    mov  Temp6, #0                      ; Reset timestamp

    ; Decode DShot data MSB nibble (4bit).
    ; Use more code space to save time (by not using loop)
    Decode_DShot_2Bit Temp5, t1_int_frame_fail
    Decode_DShot_2Bit Temp5, t1_int_frame_fail
    sjmp t1_int_decode_lsb              ; Continue with decoding LSB

t1_int_frame_fail:
    sjmp t1_int_outside_range

t1_int_decode_lsb:
    ; Decode DShot data LSB (8bit)
    Decode_DShot_2Bit Temp4, t1_int_outside_range
    Decode_DShot_2Bit Temp4, t1_int_outside_range
    Decode_DShot_2Bit Temp4, t1_int_outside_range
    Decode_DShot_2Bit Temp4, t1_int_outside_range
    sjmp t1_int_decode_checksum

t1_int_outside_range:
    inc  Rcp_Outside_Range_Cnt
    mov  A, Rcp_Outside_Range_Cnt
    jnz  t1_int_outside_range_check_limit
    dec  Rcp_Outside_Range_Cnt

t1_int_outside_range_check_limit:
    clr  C
    mov  A, Rcp_Outside_Range_Cnt
    subb A, #50                         ; Allow a given number of outside pulses
    jc   t1_int_exit_timeout            ; If outside limits - ignore first pulses

    ; RC pulse signal has not timed out, but pulses are not recognized as DShot
    setb Flag_Rcp_Stop                  ; Set pulse length to zero
    mov  DShot_Cmd, #0                  ; Reset DShot command
    mov  DShot_Cmd_Cnt, #0              ; Reset Dshot command counter

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
    jnb  Flag_Rcp_DShot_Inverted, t1_int_decode_checksum_xor_check
    cpl  A                              ; Invert checksum if using inverted DShot

t1_int_decode_checksum_xor_check:
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
    jz   t1_int_dshot_set_cmd           ; Clear DShot command when RC pulse is zero

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
    jnb  Flag_Pgm_Dir_Rev, t1_int_bidir_set_dir ; Check programmed direction
    cpl  C                              ; Reverse direction

t1_int_bidir_set_dir:
    mov  Flag_Rcp_Dir_Rev, C            ; Set rcp direction

    ; Multiply throttle value by 2
    clr  C
    rlca Temp4
    rlca Temp5

t1_int_not_bidir:
    ; From here Temp5/Temp4 should be at most 3999 (4095-96)
    mov  A, Temp4                       ; Divide by 16 (12 to 8-bit)
    anl  A, #0F0h
    orl  A, Temp5                       ; NOTE: Assumes Temp5 to be 4-bit
    swap A
    mov  B, #5                          ; Divide by 5 (80 in total)
    div  AB
    mov  Temp3, A

    ; Align to 11 bits
    ;clr    C                           ; NOTE: Cleared by div

    rrca Temp5
    mov  A, Temp4
    rrc  A

    ; From here Temp5/Temp4 should be at most 1999 (4095-96) / 2
    ; Scale from 2000 to 2048
    add  A, Temp3
    mov  Temp4, A
    mov  A, Temp5
    addc A, #0
    mov  Temp5, A
    jnb  ACC.3, t1_int_not_bidir_do_not_boost ; Limit to 11-bit maximum
    mov  Temp4, #0FFh
    mov  Temp5, #07h

t1_int_not_bidir_do_not_boost:
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
    mov  B, #40                         ; NOTE: Stall count should be less than 6
    mul  AB

    add  A, Temp4                       ; Increase power when motor fails to start (stalling)
    mov  Temp4, A
    mov  A, Temp5
    addc A, #0
    mov  Temp5, A
    jnb  ACC.3, t1_int_startup_boosted  ; Limit to 11-bit maximum
    mov  Temp4, #0FFh
    mov  Temp5, #07h

t1_int_startup_boosted:
    ; Calculate and store 8-bit scaled down rc pulse in Temp2
    mov  A, Temp4
    anl  A, #0F8h
    orl  A, Temp5                       ; Assumes Temp5 to be 3-bit (11-bit RC pulse)
    swap A
    rl   A
    mov  Temp2, A

    jnz  t1_int_rcp_not_zero

    mov  A, Temp4                       ; Only set Rcp_Stop if all all 11 bits are zero
    jnz  t1_int_rcp_not_zero

    setb Flag_Rcp_Stop
    sjmp t1_int_zero_rcp_checked

t1_int_rcp_not_zero:
    mov  Rcp_Stop_Cnt, #0               ; Reset RC pulse stop counter
    clr  Flag_Rcp_Stop                  ; Pulse ready

t1_int_zero_rcp_checked:
    ; Decrement outside range counter
    mov  A, Rcp_Outside_Range_Cnt
    jz   t1_int_zero_rcp_checked_set_limit
    dec  Rcp_Outside_Range_Cnt

t1_int_zero_rcp_checked_set_limit:
    ; Set pwm limit
    clr  C
    mov  A, Pwm_Limit_Startup_n_Temp    ; Limit to the smallest
    mov  Temp6, A                       ; Store limit in Temp6
    subb A, Pwm_Limit_By_Rpm
    jc   t1_int_zero_rcp_checked_check_limit
    mov  Temp6, Pwm_Limit_By_Rpm

t1_int_zero_rcp_checked_check_limit:
    ; Check against limit
    clr  C
    mov  A, Temp6
    subb A, Temp2                       ; 8-bit rc pulse
    jnc  t1_int_dynamic_pwm

    ; Multiply limit by 8 for 11-bit pwm
    mov  A, Temp6
    mov  B, #8
    mul  AB
    ; Set limit
    mov  Temp4, A
    mov  Temp5, B

t1_int_dynamic_pwm:
    ; Dynamic PWM
    mov  A, Temp2

    ; Choose between 48khz and 24khz
    clr  C
    subb A, Throttle_48to24_Threshold
    jc   t1_int_run_24khz

    ; Choose between 96khz and 48khz
    clr  C
    subb A, Throttle_96to48_Threshold
    jc   t1_int_run_48khz


IF PWM_CENTERED == 0                    ;  Edge aligned PWM

t1_int_run_96khz:
    ; Scale pwm resolution and invert (duty cycle is defined inversely)
    ; Deadtime and 96khz
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

    ; Set PCA to work at 96khz (9bit pwm)
    mov  PCA0PWM, #81h
    mov  Temp2, A

    ; Set PCA to work at 24khz (11bit pwm)
    mov  PCA0PWM, #83h
    jmp t1_int_set_pwm

t1_int_run_48khz:
    ; Scale pwm resolution and invert (duty cycle is defined inversely)
    ; Deadtime and 48khz
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

    ; Set PCA to work at 48khz (10bit pwm)
    mov  PCA0PWM, #82h
    jmp t1_int_set_pwm

t1_int_run_24khz:
    ; Scale pwm resolution and invert (duty cycle is defined inversely)
    ; No deadtime and 24khz
    mov  A, Temp5
    cpl  A
    anl  A, #7
    mov  Temp3, A
    mov  A, Temp4
    cpl  A

t1_int_set_pwm:
; Set PWM registers
; NOTE: Interrupts are not explicitly disabled. Assume higher priority
;       interrupts (Int0, Timer0) to be disabled at this point.
    ; Set power pwm auto-reload registers
    Set_Power_Pwm_Reg_L Temp2
    Set_Power_Pwm_Reg_H Temp3

ELSE                                    ; Center aligned PWM

t1_int_run_96khz:
    ; Scale pwm resolution and invert (duty cycle is defined inversely)
    ; Deadtime and 96khz
    mov  A, Temp2                       ; Temp2 already 8-bit
    cpl  A
    mov  Temp2, A
    mov  Temp3, #0

    ; Substract dead time from normal pwm and store as damping PWM
    ; Damping PWM duty cycle will be higher because numbers are inverted
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
    jnc  t1_int_max_braking_set_96khz

    clr  A                              ; Set to minimum value
    mov  Temp4, A
    mov  Temp5, A
    sjmp t1_int_set_pwm_96khz           ; Max braking is already zero - branch

t1_int_max_braking_set_96khz:
    clr  C
    mov  A, Temp4
    subb A, Pwm_Braking96_L
    mov  A, Temp5
    subb A, #0                          ; Is braking pwm more than maximum allowed braking? (Pwm_Braking96_H is 0, 8-bit)
    jc   t1_int_set_pwm_96khz           ; Yes - branch

    mov  Temp4, Pwm_Braking96_L         ; No - set desired braking instead
    mov  Temp5, #0                      ; Pwm_Braking96_H is 0, 8-bit

t1_int_set_pwm_96khz:
; Set PWM registers
; NOTE: Interrupts are not explicitly disabled. Assume higher priority
;       interrupts (Int0, Timer0) to be disabled at this point.
    ; Set PCA to work at 96khz (8bit pwm)
    mov  PCA0PWM, #80h

    ; Set power pwm auto-reload registers
    Set_Power_Pwm_Reg_H Temp2

    ; Set damp pwm auto-reload registers
    Set_Damp_Pwm_Reg_H Temp4
    jmp  t1_int_prepare_telemetry

t1_int_run_48khz:
    ; Scale pwm resolution and invert (duty cycle is defined inversely)
    ; Deadtime and 48khz
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

    ; Substract dead time from normal pwm and store as damping PWM
    ; Damping PWM duty cycle will be higher because numbers are inverted
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
    jnc  t1_int_max_braking_set_48khz

    clr  A                              ; Set to minimum value
    mov  Temp4, A
    mov  Temp5, A
    sjmp t1_int_set_pwm_48khz           ; Max braking is already zero - branch

t1_int_max_braking_set_48khz:
    clr  C
    mov  A, Temp4
    subb A, Pwm_Braking48_L
    mov  A, Temp5
    subb A, Pwm_Braking48_H             ; Is braking pwm more than maximum allowed braking?
    jc   t1_int_set_pwm_48khz           ; Yes - branch

    mov  Temp4, Pwm_Braking48_L         ; No - set desired braking instead
    mov  Temp5, Pwm_Braking48_H

t1_int_set_pwm_48khz:
; Set PWM registers
; NOTE: Interrupts are not explicitly disabled. Assume higher priority
;       interrupts (Int0, Timer0) to be disabled at this point.
    ; Set PCA to work at 48khz (9bit pwm)
    mov  PCA0PWM, #81h

    ; Set power pwm auto-reload registers
    Set_Power_Pwm_Reg_L Temp2
    Set_Power_Pwm_Reg_H Temp3

    ; Set damp pwm auto-reload registers
    Set_Damp_Pwm_Reg_L Temp4
    Set_Damp_Pwm_Reg_H Temp5
    jmp  t1_int_prepare_telemetry

t1_int_run_24khz:
    ; Scale pwm resolution and invert (duty cycle is defined inversely)
    ; Deadtime and 24khz
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

    ; Substract dead time from normal pwm and store as damping PWM
    ; Damping PWM duty cycle will be higher because numbers are inverted
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
    jnc  t1_int_max_braking_set_24khz

    clr  A                              ; Set to minimum value
    mov  Temp4, A
    mov  Temp5, A
    jmp t1_int_set_pwm_24khz            ; Max braking is already zero - branch

t1_int_max_braking_set_24khz:
    clr  C
    mov  A, Temp4
    subb A, Pwm_Braking24_L
    mov  A, Temp5
    subb A, Pwm_Braking24_H             ; Is braking pwm more than maximum allowed braking?
    jc   t1_int_set_pwm_24khz           ; Yes - branch

    mov  Temp4, Pwm_Braking24_L         ; No - set desired braking instead
    mov  Temp5, Pwm_Braking24_H

t1_int_set_pwm_24khz:
; Set PWM registers
; NOTE: Interrupts are not explicitly disabled. Assume higher priority
;       interrupts (Int0, Timer0) to be disabled at this point.
    ; Set PCA to work at 24khz (10bit pwm)
    mov  PCA0PWM, #82h

    ; Set power pwm auto-reload registers
    Set_Power_Pwm_Reg_L Temp2
    Set_Power_Pwm_Reg_H Temp3

    ; Set damp pwm auto-reload registers
    Set_Damp_Pwm_Reg_L Temp4
    Set_Damp_Pwm_Reg_H Temp5

ENDIF                                   ; Edge/center aligned pwm


t1_int_prepare_telemetry:
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

    ; NOTE: Delay must be large enough to ensure port is ready for output
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
; Happens every 32ms before arming and every 16 ms after arming (on 48MHz MCUs)
;
; Tasks:
; - Update RC pulse timeout
; - Update stop counters
;
; ASSERT:
; - No PSW instructions
; - Mp usage of Temp registers
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
t2_int:
    push ACC                            ; Preserve registers
    clr  TMR2CN0_TF2H                   ; Clear interrupt flag
    inc  Timer2_X                       ; Increment extended byte
    setb Flag_16ms_Elapsed              ; Set 16ms elapsed flag

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
    jz   t2_int_exit
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
; Tasks:
; - Commutation timing
;
; ASSERT:
; - No PSW instructions
; - No usage of Temp/Acc/B registers
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
; Tasks:
;  - Read and store DShot PWM signal for decoding
;
; ASSERT:
; - No PSW instructions
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
int0_int:
    push ACC
    mov  A, TL0                         ; Read PWM for DShot immediately
    mov  TL1, DShot_Timer_Preset        ; Reset sync timer

    ; Temp1 in register bank 1 points to PWM timings
    push PSW
    mov  PSW, #8h
    movx @Temp1, A                      ; Store PWM in external memory
    inc  Temp1
    pop  PSW

    pop  ACC
    reti

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Int1 interrupt routine
;
; Tasks:
; - RC pulse timing
;
; ASSERT:
; - No PSW instructions
; - No Temp/Acc registers
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
int1_int:
    clr  IE_EX1                         ; Disable Int1 interrupts
    setb TCON_TR1                       ; Start Timer1

    ; NOTE: Interrupts are not explicitly disabled, assuming higher priority
    ;       interrupts:
    ;       - Timer0 to be disabled at this point
    ;       - Int0 to not trigger for valid DShot signal
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
