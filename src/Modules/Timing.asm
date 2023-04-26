;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Timing
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Initialize timing
;
; Part of initialization before motor start
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
initialize_timing:
    ; Initialize commutation period to 7.5ms (~1330 erpm)
    mov Comm_Period4x_L, #00h
    mov Comm_Period4x_H, #0F0h

    ; Start timer to run freely
	mov TMR3CN0, #0				; Disable timer3 and clear flags
    mov TMR3L, #0 				; Setup next wait time
    mov TMR3H, #4
	mov TMR3CN0, #4				; Enable timer3 and clear flags
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Calculate next commutation period
;
; Measure the duration of current commutation period,
; and update Comm_Period4x by averaging a fraction of it.
;
; Note: Comm_Period4x holds the average weighted time of the last 4
; commutations. This routine Removes one the fraction of that time
; and adds the same fraction of the new commutation time. Depending
; on the spinning speed it uses some or other dividers of the formula:
; Comm_Period4x = Comm_Period4x - (Comm_Period4x / (16 or 4)) + (Comm_Period / (4 or 1))
; Normal regime:
; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 16) + (Comm_Period / 4)
; During startup:
; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 4) + (Comm_Period / 1)
;
; Simple example using 16 and 4 divisors:
; - Let commutation time be constant.
; - Comm_Period = 64
; - Then Comm_Period4x = 256 (Comm_Period * 4)
; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 16) + Comm_Period / 4
; Comm_Period4x = 256 - (256 / 16) + (64 / 4)
; Comm_Period4x = 256 - 16 + 16
; Comm_Period4x = 256
;
; Called immediately after each commutation
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
calc_next_comm_period:
    ; Read commutation time into Temp3:2:1
    clr IE_EA
    clr TMR2CN0_TR2                 ; Timer2 disabled
    mov Temp1, TMR2L                ; Load Timer2 value
    mov Temp2, TMR2H
    mov Temp3, Timer2_X
    jnb TMR2CN0_TF2H, ($+4)         ; Check if interrupt is pending
    inc Temp3                       ; If it is pending, then timer has already wrapped
    setb    TMR2CN0_TR2             ; Timer2 enabled
    setb    IE_EA

IF MCU_TYPE >= 1
    ; Divide time by 2 on 48MHz MCUs
    clr C
    rrca    Temp3
    rrca    Temp2
    rrca    Temp1
ENDIF

    jnb  Flag_Startup_Phase, calc_next_comm_normal

calc_next_comm_startup:
    ; Calculate this commutation time
    mov Temp4, Prev_Comm_L
    mov Temp5, Prev_Comm_H
    mov Temp6, Prev_Comm_X
    mov Prev_Comm_L, Temp1          ; Store timestamp as previous commutation
    mov Prev_Comm_H, Temp2
    mov Prev_Comm_X, Temp3          ; Store extended timestamp as previous commutation

    clr C
    mov A, Temp1
    subb    A, Temp4                ; Calculate the new commutation time
    mov A, Temp2
    subb    A, Temp5
    mov A, Temp3
    subb    A, Temp6                ; Calculate the new extended commutation time
IF MCU_TYPE >= 1
    anl A, #7Fh
ENDIF
    jz  calc_next_comm_startup_no_zero_cross

    ; Extended byte is not zero, so commutation time is above 0xFFFF
    mov Comm_Period4x_L, #0FFh
    mov Comm_Period4x_H, #0FFh
    ajmp    calc_next_comm_done

calc_next_comm_startup_no_zero_cross:
    ; Extended byte = 0, so commutation time fits within two bytes
    mov Temp7, Prev_Prev_Comm_L
    mov Temp8, Prev_Prev_Comm_H
    mov Prev_Prev_Comm_L, Temp4
    mov Prev_Prev_Comm_H, Temp5

    ; Calculate the new commutation time based upon the two last commutations (to reduce sensitivity to offset)
    clr C
    mov A, Temp1
    subb    A, Temp7
    mov Temp1, A
    mov A, Temp2
    subb    A, Temp8
    mov Temp2, A

    ; Comm_Period4x holds the time of 4 commutations
    mov Temp3, Comm_Period4x_L
    mov Temp4, Comm_Period4x_H

    ; Update Comm_Period4x from 1 new commutation period
    ; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 4) + (Comm_Period / 1)

    ; Divide Temp4:3 by 4 and store in Temp6:5
    Divide_By_4 Temp4, Temp3, Temp6, Temp5

    ; Comm_Period / 1 does not need to be divided
    sjmp calc_next_comm_average_and_update

calc_next_comm_normal:
    ; Calculate this commutation time and store in Temp2:1
    clr C
    mov A, Temp1
    subb    A, Prev_Comm_L          ; Calculate the new commutation time
    mov Prev_Comm_L, Temp1          ; Save timestamp as previous commutation
    mov Temp1, A                    ; Store commutation period in Temp1 (lo byte)
    mov A, Temp2
    subb    A, Prev_Comm_H
    mov Prev_Comm_H, Temp2          ; Save timestamp as previous commutation
IF MCU_TYPE >= 1
    anl A, #7Fh
ENDIF
    mov Temp2, A                    ; Store commutation period in Temp2 (hi byte)

    ; Comm_Period4x holds the time of 4 commutations
    mov Temp3, Comm_Period4x_L
    mov Temp4, Comm_Period4x_H

    ; Update Comm_Period4x from 1/4 new commutation period
    ; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 16) + (Comm_Period / 4)

    ; Divide Temp4:3 by 16 and store in Temp6:5
    Divide_By_16 Temp4, Temp3, Temp6, Temp5

    ; Divide Temp2:1 by 4 and store in Temp2:1
    Divide_By_4 Temp2, Temp1, Temp2, Temp1

calc_next_comm_average_and_update:
    ; Comm_Period4x = Comm_Period4x - (Comm_Period4x / (16 or 4)) + (Comm_Period / (4 or 1))

    ; Temp6/5: Comm_Period4x divided by (16 or 4)
    clr C                           ; Subtract a fraction
    mov A, Temp3                    ; Comm_Period4x_L
    subb    A, Temp5
    mov Temp3, A
    mov A, Temp4                    ; Comm_Period4x_H
    subb    A, Temp6
    mov Temp4, A

    ; Temp2/1: This commutation period divided by (4 or 1)
    mov A, Temp3                    ; Add the divided new time
    add A, Temp1
    mov Comm_Period4x_L, A
    mov A, Temp4
    addc    A, Temp2
    mov Comm_Period4x_H, A

    jnc calc_next_comm_done         ; Is period larger than 0xffff?
    mov Comm_Period4x_L, #0FFh      ; Yes - Set commutation period registers to very slow timing (0xffff)
    mov Comm_Period4x_H, #0FFh

calc_next_comm_done:
    ; C = Comm_Period4x_H < 2 (above ~160k erpm)
    clr C
    mov A, Comm_Period4x_H
    subb    A, #2
    mov Flag_High_Rpm, C

calc_next_comm_15deg:
    ; Commutation period: 360 deg / 6 runs = 60 deg
    ; 60 deg / 4 = 15 deg

    ; Load current commutation timing and compute 15 deg timing
    ; Divide Comm_Period4x by 16 (Comm_Period1x divided by 4) and store in Temp4/3
    Divide_By_16    Comm_Period4x_H, Comm_Period4x_L, Temp4, Temp3

    ; Subtract timing reduction
    clr C
    mov A, Temp3
    subb    A, #2                       ; Set timing reduction
    mov Temp6, A
    mov A, Temp4
    subb    A, #0
    mov Temp7, A

    jc  calc_next_comm_15deg_set_min    ; Check that result is still positive
    jnz calc_next_comm_period_exit      ; Check that result is still above minimum
    mov A, Temp6
    jnz calc_next_comm_period_exit

calc_next_comm_15deg_set_min:
    mov Temp6, #1                       ; Set minimum waiting time (Timers cannot wait for a delay of 0)
    mov Temp7, #0

calc_next_comm_period_exit:



;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait advance timing
;
; Waits for the advance timing to elapse
;
; WARNING: Be VERY careful if using temp6 and temp7 registers. They are passed over this routine
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_advance_timing:
    ; If it has not already, we wait here for the Wt_Adv_Start_ delay to elapse.
    Wait_For_Timer3

    ; At this point Timer3 has (already) wrapped and been reloaded with the Wt_Comm_2_Zc_ delay.
    ; In case this delay has also elapsed, Timer3 has been reloaded with a short delay any number of times.
    ; - The interrupt flag is set and the pending flag will clear immediately after enabling the interrupt.

	mov TMR3CN0, #0				; Disable timer3 and clear flags
    mov TMR3L, Wt_Zc_Scan_Tout_L 	; Setup next wait time
    mov TMR3H, Wt_Zc_Scan_Tout_H
	mov TMR3CN0, #4				; Enable timer3 and clear flags


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Calculate new wait times
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
calc_new_wait_times:
    mov Temp1, #Pgm_Comm_Timing     ; Load commutation timing setting
    mov A, @Temp1
    mov Temp8, A                    ; Store in Temp8

    clr C
    clr A
    subb    A, Temp6                    ; Negate
    mov Temp1, A
    clr A
    subb    A, Temp7
    mov Temp2, A
IF MCU_TYPE >= 1
    clr C
    rlca    Temp1                   ; Multiply by 2
    rlca    Temp2
ENDIF

    ; Temp2/1 = 15deg Timer2 period

    jb  Flag_High_Rpm, calc_new_wait_times_fast ; Branch if high rpm

    ; Load programmed commutation timing
    jnb Flag_Startup_Phase, adjust_comm_timing

    mov Temp8, #3                   ; Set dedicated timing during startup
    sjmp    load_comm_timing_done

adjust_comm_timing:
    ; Adjust commutation timing according to demag metric
    clr C
    mov A, Demag_Detected_Metric        ; Check demag metric
    subb    A, #130
    jc  load_comm_timing_done

    inc Temp8                   ; Increase timing (if metric 130 or above)

    subb    A, #30
    jc  ($+3)

    inc Temp8                   ; Increase timing again (if metric 160 or above)

    clr C
    mov A, Temp8                    ; Limit timing to max
    subb    A, #6
    jc  ($+4)

    mov Temp8, #5                   ; Set timing to max (if timing 6 or above)

load_comm_timing_done:
    ; Temp2:1 = 15deg Timer2 period
    mov A, Temp1                    ; Copy values
    mov Temp3, A
    mov A, Temp2
    mov Temp4, A

    ; Temp6:5 = (15deg Timer2 period) / 2
    setb    C                       ; Negative numbers - set carry
    mov A, Temp2                    ; Store 7.5deg in Temp5/6 (15deg / 2)
    rrc A
    mov Temp6, A
    mov A, Temp1
    rrc A
    mov Temp5, A

    mov Wt_Comm_2_Zc_L, Temp5   ; Set 7.5deg time for zero cross scan delay
    mov Wt_Comm_2_Zc_H, Temp6
    mov Wt_Zc_Scan_Tout_L, Temp1   ; Set 15deg time for zero cross scan timeout
    mov Wt_Zc_Scan_Tout_H, Temp2

    clr C
    mov A, Temp8                    ; (Temp8 has Pgm_Comm_Timing)
    subb    A, #3                   ; Is timing normal?
    jz  store_times_decrease        ; Yes - branch

    mov A, Temp8
    jb  ACC.0, adjust_timing_two_steps; If an odd number - branch

    ; Commutation timing setting is 2 or 4
    mov A, Temp1                    ; Store 22.5deg in Temp2:1 (15deg + 7.5deg)
    add A, Temp5
    mov Temp1, A
    mov A, Temp2
    addc    A, Temp6
    mov Temp2, A

	; Store 7.5deg in Temp4:3
    mov A, Temp5
    mov Temp3, A
    mov A, Temp6
    mov Temp4, A

    sjmp    store_times_up_or_down

adjust_timing_two_steps:
    ; Commutation timing setting is 1 or 5
    mov A, Temp1                    ; Store 30deg in Temp1/2 (15deg + 15deg)
    setb    C                       ; Add 1 to final result (Temp1/2 * 2 + 1)
    addc    A, Temp1
    mov Temp1, A
    mov A, Temp2
    addc    A, Temp2
    mov Temp2, A

	; Store minimum time (0deg) in Temp3/4
    mov Temp3, #-1
    mov Temp4, #-1

store_times_up_or_down:
    clr C
    mov A, Temp8
    subb    A, #3                   ; Is timing higher than normal?
    jc  store_times_decrease        ; No - branch

store_times_increase:
	; New commutation time (~60deg) divided by 4 (~15deg nominal)
    mov Wt_Zc_2_Comm_L, Temp3
    mov Wt_Zc_2_Comm_H, Temp4
    sjmp    calc_new_wait_times_exit

store_times_decrease:
	; New commutation time (~60deg) divided by 4 (~15deg nominal)
    mov Wt_Zc_2_Comm_L, Temp1
    mov Wt_Zc_2_Comm_H, Temp2

    ; Set very short delays for all but advance time during startup, in order to widen zero cross capture range
    jnb Flag_Startup_Phase, calc_new_wait_times_exit
    mov Wt_Zc_2_Comm_L, #-16
    mov Wt_Zc_2_Comm_H, #-1
    mov Wt_Comm_2_Zc_L, #-16
    mov Wt_Comm_2_Zc_H, #-1
    mov Wt_Zc_Scan_Tout_L, #-16
    mov Wt_Zc_Scan_Tout_H, #-1

    sjmp    calc_new_wait_times_exit

;**** **** **** **** ****
; Calculate new wait times fast routine
calc_new_wait_times_fast:
    mov A, Temp1                    ; Copy values
    mov Temp3, A
    setb    C                       ; Negative numbers - set carry
    rrc A                       ; Divide by 2
    mov Temp5, A

    mov Wt_Comm_2_Zc_L, Temp5   ; Use this value for zero cross scan delay (7.5deg)
    mov Wt_Zc_Scan_Tout_L, Temp1   ; Set 15deg time for zero cross scan timeout

    clr C
    mov A, Temp8                    ; (Temp8 has Pgm_Comm_Timing - commutation timing setting)
    subb    A, #3                   ; Is timing normal?
    jz  store_times_decrease_fast   ; Yes - branch

    mov A, Temp8
    jb  ACC.0, adjust_timing_two_steps_fast ; If an odd number - branch

    mov A, Temp1                    ; Add 7.5deg and store in Temp1
    add A, Temp5
    mov Temp1, A

    mov A, Temp5                    ; Store 7.5deg in Temp3
    mov Temp3, A
    sjmp    store_times_up_or_down_fast

adjust_timing_two_steps_fast:
    mov A, Temp1                    ; Add 15deg and store in Temp1
    add A, Temp1
    add A, #1
    mov Temp1, A
    mov Temp3, #-1              ; Store minimum time in Temp3

store_times_up_or_down_fast:
    clr C
    mov A, Temp8
    subb    A, #3                   ; Is timing higher than normal?
    jc  store_times_decrease_fast   ; No - branch

store_times_increase_fast:
    mov Wt_Zc_2_Comm_L, Temp3      ; Now commutation time (~60deg) divided by 4 (~15deg nominal)
    sjmp    calc_new_wait_times_exit

store_times_decrease_fast:
    mov Wt_Zc_2_Comm_L, Temp1      ; Now commutation time (~60deg) divided by 4 (~15deg nominal)

calc_new_wait_times_exit:


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait before zero cross scan
;
; Waits for the zero cross scan wait time to elapse
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_before_zc_scan:
    ; If it has not already, we wait here for the Wt_Comm_2_Zc_ delay to elapse.
    Wait_For_Timer3

    ; At this point Timer3 has (already) wrapped and been reloaded with the Wt_ZC_Tout_Start_ delay.
    ; In case this delay has also elapsed, Timer3 has been reloaded with a short delay any number of times.
    ; - The interrupt flag is set and the pending flag will clear immediately after enabling the interrupt.
    mov Startup_Zc_Timeout_Cntd, #2

setup_zc_scan_timeout:
    jnb Flag_Initial_Run_Phase, wait_before_zc_scan_exit

    mov Temp1, Comm_Period4x_L      ; Set long timeout when starting
    mov Temp2, Comm_Period4x_H
    clr C
    rrca    Temp2
    rrca    Temp1
IF MCU_TYPE == 0
    clr C
    rrca    Temp2
    rrca    Temp1
ENDIF
    jnb Flag_Startup_Phase, setup_zc_scan_timeout_startup_done

    mov A, Temp2
    add A, #40h                 ; Increase timeout somewhat to avoid false wind up
    mov Temp2, A

setup_zc_scan_timeout_startup_done:
	mov TMR3CN0, #0					; Disable timer3 and clear flags
    clr C
    clr A
    subb    A, Temp1                ; Set timeout
    mov TMR3L, A
    clr A
    subb    A, Temp2
    mov TMR3H, A
	mov TMR3CN0, #4				; Enable timer3 and clear flags

wait_before_zc_scan_exit:
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait for comparator to go low/high
;
; Scans for comparator going low/high
; Exit if zero cross timeout has elapsed
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_for_comp_out_low:
    mov B, #00h                 ; Desired comparator output
    jnb Flag_Dir_Change_Brake, comp_init
    mov B, #40h
    sjmp    comp_init

wait_for_comp_out_high:
    mov B, #40h                 ; Desired comparator output
    jnb Flag_Dir_Change_Brake, comp_init
    mov B, #00h

comp_init:
    setb    Flag_Demag_Detected         ; Set demag detected flag as default
    clr 	BoolAux0					; BoolAux0 used here to know if there have been comparator reads

comp_start:
    ; Set number of comparator readings required
    mov Temp3, #(2 SHL IS_MCU_48MHZ)        ; Number of OK readings required
    mov Temp4, #(4 SHL IS_MCU_48MHZ)       	; Max wrong readings threshold
    jb  Flag_High_Rpm, comp_check_timeout	; Branch if high rpm

    jnb Flag_Initial_Run_Phase, ($+5)
    clr Flag_Demag_Detected         		; Clear demag detected flag if start phases

    jnb Flag_Startup_Phase, comp_check_timeout
    mov Temp3, #(27 SHL IS_MCU_48MHZ)   	; Set many samples during startup, approximately one pwm period
    mov Temp4, #(27 SHL IS_MCU_48MHZ)
    sjmp    comp_check_timeout

comp_check_timeout:
	mov A, TMR3CN0
    jnb  ACC.7, comp_check_timeout_not_timed_out   			; Has zero cross scan timeout elapsed?
    jnb BoolAux0,  comp_check_timeout_not_timed_out    		; If not comparator reads yet - ignore zero cross timeout
    jnb Flag_Startup_Phase, comp_check_timeout_timeout_extended

    ; Extend timeout during startup
    djnz    Startup_Zc_Timeout_Cntd, comp_check_timeout_extend_timeout

comp_check_timeout_timeout_extended:
    setb    Flag_Comp_Timed_Out
    sjmp    comp_exit

comp_check_timeout_extend_timeout:
    call    setup_zc_scan_timeout

comp_check_timeout_not_timed_out:
	setb BoolAux0						; There have been comparator reads
    Read_Comparator_Output
    anl A, #40h
    cjne    A, B, comp_read_wrong

    ; Comp read ok
    mov A, Startup_Cnt              	; Force a timeout for the first commutation
    jz  comp_start

    jb  Flag_Demag_Detected, comp_start ; Do not accept correct comparator output if it is demag

    djnz    Temp3, comp_check_timeout   ; Decrement readings counter - repeat comparator reading if not zero

    clr Flag_Comp_Timed_Out
    sjmp    comp_exit

comp_read_wrong:
    jb  Flag_Startup_Phase, comp_read_wrong_startup
    jb  Flag_Demag_Detected, comp_read_wrong_extend_timeout

    inc Temp3                   ; Increment number of OK readings required
    clr C
    mov A, Temp3
    subb    A, Temp4
    jc  comp_check_timeout          ; If below initial requirement - take another reading
    sjmp    comp_start              ; Otherwise - go back and restart

comp_read_wrong_startup:
    inc Temp3                   ; Increment number of OK readings required
    clr C
    mov A, Temp3
    subb    A, Temp4                    ; If above initial requirement - do not increment further
    jc  ($+3)
    dec Temp3

    sjmp    comp_check_timeout          ; Continue to look for good ones

comp_read_wrong_extend_timeout:
    clr Flag_Demag_Detected         ; Clear demag detected flag
    jnb Flag_High_Rpm, comp_read_wrong_low_rpm  ; Branch if not high rpm

comp_read_wrong_timeout_set:
    mov TMR3CN0, #00h               ; Timer3 disabled and interrupt flag cleared
    mov TMR3L, #0                   ; Set timeout to ~1ms
    mov TMR3H, #-(8 SHL IS_MCU_48MHZ)
    mov TMR3CN0, #04h               ; Timer3 enabled and interrupt flag cleared
    ljmp    comp_start              ; If comparator output is not correct - go back and restart

comp_read_wrong_low_rpm:
    mov A, Comm_Period4x_H          ; Set timeout to ~4x comm period 4x value
    mov Temp7, #0FFh                ; Default to long timeout

IF MCU_TYPE >= 1
    clr C
    rlc A
    jc  comp_read_wrong_load_timeout
ENDIF

    clr C
    rlc A
    jc  comp_read_wrong_load_timeout

    clr C
    rlc A
    jc  comp_read_wrong_load_timeout

    mov Temp7, A

comp_read_wrong_load_timeout:
    clr C
    clr A
    subb    A, Temp7

    mov TMR3CN0, #00h               ; Timer3 disabled and interrupt flag cleared
    mov TMR3L, #0
    mov TMR3H, A
    mov TMR3CN0, #04h               ; Timer3 enabled and interrupt flag cleared
    ljmp    comp_start              ; If comparator output is not correct - go back and restart

comp_exit:


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Setup commutation timing
;
; Load timer with zero cross to commutation time
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
setup_comm_wait:
	mov TMR3CN0, #0					; Disable timer3 and clear flags
    mov TMR3L, Wt_Zc_2_Comm_L
    mov TMR3H, Wt_Zc_2_Comm_H
	mov TMR3CN0, #4					; Enable timer3 and clear flags


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Evaluate comparator integrity
;
; Checks comparator signal behavior versus expected behavior
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
evaluate_comparator_integrity:
    jb  Flag_Startup_Phase, eval_comp_startup   ; Do not exit run mode during startup phases

    jnb Flag_Comp_Timed_Out, eval_comp_exit ; Has timeout elapsed?
    jb  Flag_Initial_Run_Phase, eval_comp_exit  ; Do not exit run mode if initial run phase
    jb  Flag_Dir_Change_Brake, eval_comp_exit   ; Do not exit run mode if braking
    jb  Flag_Demag_Detected, eval_comp_exit ; Do not exit run mode if it is a demag situation

    ; Inmediately cut power on timeout to avoid damage
    All_Pwm_Fets_Off
    Set_All_Pwm_Phases_Off

	; Signal stall
	setb	Flag_Stall_Notify

	; Routine exit without "ret" command
	clr IE_EA
    dec SP
    dec SP
    setb IE_EA
    ljmp    exit_run_mode_on_timeout                ; Exit run mode if timeout has elapsed

eval_comp_startup:
    inc Startup_Cnt                     ; Increment startup counter

eval_comp_exit:
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait for commutation
;
; Waits from zero cross to commutation
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_for_comm:
    ; Update demag metric
    mov A, Demag_Detected_Metric        ; Sliding average of 8, 256 when demag and 0 when not. Limited to minimum 120
    mov B, #7
    mul AB                      ; Multiply by 7

    jnb Flag_Demag_Detected, wait_for_comm_demag_event_added
    ; Add new value for current demag status
    inc B
    ; Signal demag
    setb    Flag_Demag_Notify

wait_for_comm_demag_event_added:
    mov C, B.0                  ; Divide by 8
    rrc A
    mov C, B.1
    rrc A
    mov C, B.2
    rrc A
    mov Demag_Detected_Metric, A
    clr C
    subb    A, #120                 ; Limit to minimum 120
    jnc ($+5)
    mov Demag_Detected_Metric, #120

    ; Update demag metric max
    clr C
    mov A, Demag_Detected_Metric
    subb    A, Demag_Detected_Metric_Max
    jc  wait_for_comm_demag_metric_max_updated
    mov Demag_Detected_Metric_Max, Demag_Detected_Metric

wait_for_comm_demag_metric_max_updated:
    ; Check demag metric
    clr C
    mov A, Demag_Detected_Metric
    subb    A, Demag_Pwr_Off_Thresh
    jc  wait_for_comm_wait

    ; Cut power if many consecutive demags. This will help retain sync during hard accelerations
    All_Pwm_Fets_Off
    Set_All_Pwm_Phases_Off

    ; Signal desync
    setb    Flag_Desync_Notify

wait_for_comm_wait:
    ; Wait until commutation has to be done
    Wait_For_Timer3
    ret
