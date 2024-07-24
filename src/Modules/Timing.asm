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
; Timing
;
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
    mov  Comm_Period4x_L, #00h
    mov  Comm_Period4x_H, #0F0h
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Calculate next commutation period
;
; Measure the duration of current commutation period,
; and update Comm_Period4x by averaging a fraction of it.
;
; Called immediately after each commutation
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
calc_next_comm_period:
    ; Read commutation time
    clr  IE_EA                          ; Disable all interrupts
    clr  TMR2CN0_TR2                    ; Disable Timer2
    mov  Temp1, TMR2L                   ; Load Timer2 value
    mov  Temp2, TMR2H
    mov  Temp3, Timer2_X
    jnb  TMR2CN0_TF2H,calc_next_comm_period_enable_timer2 ; Check if interrupt is pending
    inc  Temp3                          ; If it is pending,then timer has already wrapped

calc_next_comm_period_enable_timer2:
    setb TMR2CN0_TR2                    ; Timer2 enabled
    setb IE_EA

; Divide time by 2 on 48MHz
IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    clr  C
    rrca Temp3
    rrca Temp2
    rrca Temp1
ENDIF

    jb   Flag_Startup_Phase, calc_next_comm_startup

    ; Calculate this commutation time
    clr  C
    mov  A, Temp1
    subb A, Prev_Comm_L                 ; Calculate the new commutation time
    mov  Prev_Comm_L, Temp1             ; Save timestamp as previous commutation
    mov  Temp1, A                       ; Store commutation period in Temp1 (lo byte)
    mov  A, Temp2
    subb A, Prev_Comm_H
    mov  Prev_Comm_H, Temp2             ; Save timestamp as previous commutation
IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    anl  A, #7Fh
ENDIF
    mov  Temp2, A                       ; Store commutation period in Temp2 (hi byte)

    jnb  Flag_High_Rpm, calc_next_comm_normal ; Branch normal RPM
    ajmp calc_next_comm_period_fast     ; Branch high RPM

calc_next_comm_startup:
    ; Calculate this commutation time
    mov  Temp4, Prev_Comm_L
    mov  Temp5, Prev_Comm_H
    mov  Temp6, Prev_Comm_X
    mov  Prev_Comm_L, Temp1             ; Store timestamp as previous commutation
    mov  Prev_Comm_H, Temp2
    mov  Prev_Comm_X, Temp3             ; Store extended timestamp as previous commutation

    clr  C
    mov  A, Temp1
    subb A, Temp4                       ; Calculate the new commutation time
    mov  A, Temp2
    subb A, Temp5
    mov  A, Temp3
    subb A, Temp6                       ; Calculate the new extended commutation time
IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    anl  A, #7Fh
ENDIF
    jz   calc_next_comm_startup_no_X

    ; Extended byte is not zero, so commutation time is above 0xFFFF
    mov  Comm_Period4x_L, #0FFh
    mov  Comm_Period4x_H, #0FFh
    ajmp calc_next_comm_done

calc_next_comm_startup_no_X:
    ; Extended byte = 0, so commutation time fits within two bytes
    mov  Temp7, Prev_Prev_Comm_L
    mov  Temp8, Prev_Prev_Comm_H
    mov  Prev_Prev_Comm_L, Temp4
    mov  Prev_Prev_Comm_H, Temp5

    ; Calculate the new commutation time based upon the two last commutations (to reduce sensitivity to offset)
    clr  C
    mov  A, Temp1
    subb A, Temp7
    mov  Temp1, A
    mov  A, Temp2
    subb A, Temp8
    mov  Temp2, A

    mov  Temp3, Comm_Period4x_L         ; Comm_Period4x holds the time of 4 commutations
    mov  Temp4, Comm_Period4x_H

    sjmp calc_next_comm_div_4_1

calc_next_comm_normal:
    ; Prepare averaging by dividing Comm_Period4x and current commutation period (Temp2/1) according to speed.
    mov  Temp3, Comm_Period4x_L         ; Comm_Period4x holds the time of 4 commutations
    mov  Temp4, Comm_Period4x_H

    clr  C
    mov  A, Temp4

    subb A, #4                          ; Is Comm_Period4x_H below 4? (above ~80k erpm)
    jc   calc_next_comm_div_16_4        ; Yes - Use averaging for high speeds

    subb A, #4                          ; Is Comm_Period4x_H below 8? (above ~40k erpm)
    jc   calc_next_comm_div_8_2         ; Yes - Use averaging for low speeds

    ; No - Use averaging for even lower speeds

    ; Do not average very fast during initial run
    jb   Flag_Initial_Run_Phase, calc_next_comm_div_8_2_slow

; Update Comm_Period4x from 1 new commutation period
calc_next_comm_div_4_1:
    ; Divide Temp4/3 by 4 and store in Temp6/5
    Divide_By_4 Temp4, Temp3, Temp6, Temp5

    sjmp calc_next_comm_average_and_update

; Update Comm_Period4x from 1/2 new commutation period
calc_next_comm_div_8_2:
    ; Divide Temp4/3 by 8 and store in Temp5
    Divide_11Bit_By_8 Temp4, Temp3, Temp5
    mov  Temp6, #0

    Divide_16Bit_By_2 Temp2, Temp1

    sjmp calc_next_comm_average_and_update

; Update Comm_Period4x from 1/2 new commutation period
calc_next_comm_div_8_2_slow:
    ; Divide Temp4/3 by 8 and store in Temp6/5
    Divide_By_8 Temp4, Temp3, Temp6, Temp5

    Divide_16Bit_By_2 Temp2, Temp1

    sjmp calc_next_comm_average_and_update

; Update Comm_Period4x from 1/4 new commutation period
calc_next_comm_div_16_4:
    ; Divide Temp4/3 by 16 and store in Temp5
    Divide_12Bit_By_16 Temp4, Temp3, Temp5
    mov  Temp6, #0

    ; Divide Temp2/1 by 4 and store in Temp2/1
    Divide_By_4 Temp2, Temp1, Temp2, Temp1

calc_next_comm_average_and_update:
    ; Comm_Period4x = Comm_Period4x - (Comm_Period4x / (16, 8 or 4)) + (Comm_Period / (4, 2 or 1))

    ; Temp6/5: Comm_Period4x divided by (16, 8 or 4)
    clr  C                              ; Subtract a fraction
    mov  A, Temp3                       ; Comm_Period4x_L
    subb A, Temp5
    mov  Temp3, A
    mov  A, Temp4                       ; Comm_Period4x_H
    subb A, Temp6
    mov  Temp4, A

    ; Temp2/1: This commutation period divided by (4, 2 or 1)
    mov  A, Temp3                       ; Add the divided new time
    add  A, Temp1
    mov  Comm_Period4x_L, A
    mov  A, Temp4
    addc A, Temp2
    mov  Comm_Period4x_H, A

    jnc  calc_next_comm_done            ; Is period larger than 0xffff?
    mov  Comm_Period4x_L, #0FFh         ; Yes - Set commutation period registers to very slow timing (0xffff)
    mov  Comm_Period4x_H, #0FFh

calc_next_comm_done:
    clr  C
    mov  A, Comm_Period4x_H
    subb A, #2                          ; Is Comm_Period4x_H below 2? (above ~160k erpm)
    jnc  calc_next_comm_15deg
    setb Flag_High_Rpm                  ; Yes - Set high rpm flag

calc_next_comm_15deg:
    ; Commutation period: 360 deg / 6 runs = 60 deg
    ; 60 deg / 4 = 15 deg

    ; Load current commutation timing and compute 15 deg timing
    ; Divide Comm_Period4x by 16 (Comm_Period1x divided by 4) and store in Temp4/3
    Divide_By_16 Comm_Period4x_H, Comm_Period4x_L, Temp4, Temp3

    ; Subtract timing reduction
    clr  C
    mov  A, Temp3
    subb A, #2                          ; Set timing reduction
    mov  Temp3, A
    mov  A, Temp4
    subb A, #0
    mov  Temp4, A

    jc   calc_next_comm_15deg_set_min   ; Check that result is still positive
    jnz  calc_next_comm_period_exit     ; Check that result is still above minimum
    mov  A, Temp3
    jnz  calc_next_comm_period_exit

calc_next_comm_15deg_set_min:
    mov  Temp3, #1                      ; Set minimum waiting time (Timers cannot wait for a delay of 0)
    mov  Temp4, #0

    sjmp calc_next_comm_period_exit

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Calculate next commutation period (fast)
; Fast calculation (Comm_Period4x_H less than 2)
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
calc_next_comm_period_fast:
    ; Calculate new commutation time
    mov  Temp3, Comm_Period4x_L         ; Comm_Period4x holds the time of 4 commutations
    mov  Temp4, Comm_Period4x_H

    ; Divide by 16 and store in Temp5
    Divide_12Bit_By_16 Temp4, Temp3, Temp5

    clr  C
    mov  A, Temp3                       ; Subtract a fraction
    subb A, Temp5
    mov  Temp3, A
    mov  A, Temp4
    subb A, #0
    mov  Temp4, A

    ; NOTE: Temp2 is assumed to be zero (approx. Comm_Period4x_H / 4)
    mov  A, Temp1                       ; Divide by 4
    rr   A
    rr   A
    anl  A, #03Fh

    add  A, Temp3                       ; Add the divided new time
    mov  Temp3, A
    mov  A, Temp4
    addc A, #0
    mov  Temp4, A

    mov  Comm_Period4x_L, Temp3         ; Store Comm_Period4x
    mov  Comm_Period4x_H, Temp4

    clr  C
    subb A, #2                          ; Is Comm_Period4x_H 2 or more? (below ~160k erpm)
    jc   calc_next_comm_period_fast_div_comm_perio4x_by_16
    clr  Flag_High_Rpm                  ; Yes - Clear high rpm bit

calc_next_comm_period_fast_div_comm_perio4x_by_16:
    mov  A, Temp4                       ; Divide Comm_Period4x by 16 and store in Temp4/3
    swap A
    mov  Temp7, A
    mov  Temp4, #0                      ; Clear waiting time high byte
    mov  A, Temp3
    swap A
    anl  A, #0Fh
    orl  A, Temp7
    clr  C
    subb A, #2                          ; Timing reduction
    mov  Temp3, A
    jc   calc_next_comm_fast_set_min    ; Check that result is still positive
    jnz  calc_next_comm_period_exit     ; Check that result is still above minimum

calc_next_comm_fast_set_min:
    mov  Temp3, #1                      ; Set minimum waiting time (Timers cannot wait for a delay of 0)

calc_next_comm_period_exit:

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait advance timing
;
; Waits for the advance timing to elapse
;
; NOTE: Be VERY careful if using temp registers. They are passed over this routine
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_advance_timing:
    ; If it has not already, we wait here for the Wt_Adv_Start_ delay to elapse.
    Wait_For_Timer3

    ; At this point Timer3 has (already) wrapped and been reloaded with the Wt_Zc_Scan_Start_ delay.
    ; In case this delay has also elapsed, Timer3 has been reloaded with a short delay any number of times.
    ; - The interrupt flag is set and the pending flag will clear immediately after enabling the interrupt.
    mov  TMR3RLL, Wt_ZC_Tout_Start_L    ; Setup next wait time
    mov  TMR3RLH, Wt_ZC_Tout_Start_H
    setb Flag_Timer3_Pending
    orl  EIE1, #80h                     ; Enable Timer3 interrupts

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Calculate new wait times
;**** **** **** **** **** **** **** **** **** **** **** **** ****
calc_new_wait_times:
    mov  Temp1, #Pgm_Comm_Timing        ; Load commutation timing setting
    mov  A, @Temp1
    mov  Temp8, A                       ; Store in Temp8

    clr  C
    clr  A
    subb A, Temp3                       ; Negate
    mov  Temp1, A
    clr  A
    subb A, Temp4
    mov  Temp2, A
IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    clr  C
    rlca Temp1                          ; Multiply by 2
    rlca Temp2
ENDIF

    ; Temp2/1 = 15deg Timer2 period
    jb   Flag_High_Rpm, calc_new_wait_times_fast ; Branch if high rpm

    ; Load programmed commutation timing
    jnb  Flag_Startup_Phase, adjust_comm_timing

    mov  Temp8, #3                      ; Set dedicated timing during startup
    sjmp load_comm_timing_done

adjust_comm_timing:
    ; Adjust commutation timing according to demag metric
    clr  C
    mov  A, Demag_Detected_Metric       ; Check demag metric
    subb A, #130
    jc   load_comm_timing_done

    inc  Temp8                          ; Increase timing (if metric 130 or above)

    subb A, #30
    jc   adjust_comm_timing_limit_to_max

    inc  Temp8                          ; Increase timing again (if metric 160 or above)

adjust_comm_timing_limit_to_max:
    clr  C
    mov  A, Temp8                       ; Limit timing to max
    subb A, #6
    jc   load_comm_timing_done

    mov  Temp8, #5                      ; Set timing to max (if timing 6 or above)

load_comm_timing_done:
    mov  A, Temp1                       ; Copy values
    mov  Temp3, A
    mov  A, Temp2
    mov  Temp4, A

    setb C                              ; Negative numbers - set carry
    mov  A, Temp2                       ; Store 7.5deg in Temp5/6 (15deg / 2)
    rrc  A
    mov  Temp6, A
    mov  A, Temp1
    rrc  A
    mov  Temp5, A

    mov  Wt_Zc_Scan_Start_L, Temp5      ; Set 7.5deg time for zero cross scan delay
    mov  Wt_Zc_Scan_Start_H, Temp6
    mov  Wt_Zc_Tout_Start_L, Temp1      ; Set 15deg time for zero cross scan timeout
    mov  Wt_Zc_Tout_Start_H, Temp2

    clr  C
    mov  A, Temp8                       ; (Temp8 has Pgm_Comm_Timing)
    subb A, #3                          ; Is timing normal?
    jz   store_times_decrease           ; Yes - branch

    mov  A, Temp8
    jb   ACC.0, adjust_timing_two_steps ; If an odd number - branch

    ; Commutation timing setting is 2 or 4
    mov  A, Temp1                       ; Store 22.5deg in Temp1/2 (15deg + 7.5deg)
    add  A, Temp5
    mov  Temp1, A
    mov  A, Temp2
    addc A, Temp6
    mov  Temp2, A

    mov  A, Temp5                       ; Store 7.5deg in Temp3/4
    mov  Temp3, A
    mov  A, Temp6
    mov  Temp4, A

    sjmp store_times_up_or_down

adjust_timing_two_steps:
    ; Commutation timing setting is 1 or 5
    mov  A, Temp1                       ; Store 30deg in Temp1/2 (15deg + 15deg)
    setb C                              ; Add 1 to final result (Temp1/2 * 2 + 1)
    addc A, Temp1
    mov  Temp1, A
    mov  A, Temp2
    addc A, Temp2
    mov  Temp2, A

    mov  Temp3, #-1                     ; Store minimum time (0deg) in Temp3/4
    mov  Temp4, #-1

store_times_up_or_down:
    clr  C
    mov  A, Temp8
    subb A, #3                          ; Is timing higher than normal?
    jc   store_times_decrease           ; No - branch

store_times_increase:
    mov  Wt_Comm_Start_L, Temp3         ; Now commutation time (~60deg) divided by 4 (~15deg nominal)
    mov  Wt_Comm_Start_H, Temp4
    mov  Wt_Adv_Start_L, Temp1          ; New commutation advance time (~15deg nominal)
    mov  Wt_Adv_Start_H, Temp2
    sjmp calc_new_wait_times_exit

store_times_decrease:
    mov  Wt_Comm_Start_L, Temp1         ; Now commutation time (~60deg) divided by 4 (~15deg nominal)
    mov  Wt_Comm_Start_H, Temp2
    mov  Wt_Adv_Start_L, Temp3          ; New commutation advance time (~15deg nominal)
    mov  Wt_Adv_Start_H, Temp4

    ; Set very short delays for all but advance time during startup, in order to widen zero cross capture range
    jnb  Flag_Startup_Phase, calc_new_wait_times_exit
    mov  Wt_Comm_Start_L, #-16
    mov  Wt_Comm_Start_H, #-1
    mov  Wt_Zc_Scan_Start_L, #-16
    mov  Wt_Zc_Scan_Start_H, #-1
    mov  Wt_Zc_Tout_Start_L, #-16
    mov  Wt_Zc_Tout_Start_H, #-1

    sjmp calc_new_wait_times_exit

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Calculate new wait times fast routine
;**** **** **** **** **** **** **** **** **** **** **** **** ****
calc_new_wait_times_fast:
    mov  A, Temp1                       ; Copy values
    mov  Temp3, A
    setb C                              ; Negative numbers - set carry
    rrc  A                              ; Divide by 2
    mov  Temp5, A

    mov  Wt_Zc_Scan_Start_L, Temp5      ; Use this value for zero cross scan delay (7.5deg)
    mov  Wt_Zc_Tout_Start_L, Temp1      ; Set 15deg time for zero cross scan timeout

    clr  C
    mov  A, Temp8                       ; (Temp8 has Pgm_Comm_Timing)
    subb A, #3                          ; Is timing normal?
    jz   store_times_decrease_fast      ; Yes - branch

    mov  A, Temp8
    jb   ACC.0, adjust_timing_two_steps_fast ; If an odd number - branch

    mov  A, Temp1                       ; Add 7.5deg and store in Temp1
    add  A, Temp5
    mov  Temp1, A
    mov  A, Temp5                       ; Store 7.5deg in Temp3
    mov  Temp3, A
    sjmp store_times_up_or_down_fast

adjust_timing_two_steps_fast:
    mov  A, Temp1                       ; Add 15deg and store in Temp1
    add  A, Temp1
    add  A, #1
    mov  Temp1, A
    mov  Temp3, #-1                     ; Store minimum time in Temp3

store_times_up_or_down_fast:
    clr  C
    mov  A, Temp8
    subb A, #3                          ; Is timing higher than normal?
    jc   store_times_decrease_fast      ; No - branch

store_times_increase_fast:
    mov  Wt_Comm_Start_L, Temp3         ; Now commutation time (~60deg) divided by 4 (~15deg nominal)
    mov  Wt_Adv_Start_L, Temp1          ; New commutation advance time (~15deg nominal)
    sjmp calc_new_wait_times_exit

store_times_decrease_fast:
    mov  Wt_Comm_Start_L, Temp1         ; Now commutation time (~60deg) divided by 4 (~15deg nominal)
    mov  Wt_Adv_Start_L, Temp3          ; New commutation advance time (~15deg nominal)

calc_new_wait_times_exit:

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait before zero cross scan
;
; Waits for the zero cross scan wait time to elapse
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_before_zc_scan:
    ; If it has not already, we wait here for the Wt_Zc_Scan_Start_ delay to elapse.
    Wait_For_Timer3

    ; At this point Timer3 has (already) wrapped and been reloaded with the Wt_ZC_Tout_Start_ delay.
    ; In case this delay has also elapsed, Timer3 has been reloaded with a short delay any number of times.
    ; - The interrupt flag is set and the pending flag will clear immediately after enabling the interrupt.
    mov  Startup_Zc_Timeout_Cntd, #2

setup_zc_scan_timeout:
    setb Flag_Timer3_Pending
    orl  EIE1, #80h                     ; Enable Timer3 interrupts

    jnb  Flag_Initial_Run_Phase, wait_before_zc_scan_exit

    mov  Temp1, Comm_Period4x_L         ; Set long timeout when starting
    mov  Temp2, Comm_Period4x_H
    Divide_16Bit_By_2 Temp2, Temp1
    jnb  Flag_Startup_Phase, setup_zc_scan_timeout_startup_done

    mov  A, Temp2
    add  A, #40h                        ; Increase timeout somewhat to avoid false wind up
    mov  Temp2, A

setup_zc_scan_timeout_startup_done:
    clr  IE_EA
    anl  EIE1, #7Fh                     ; Disable Timer3 interrupts
    mov  TMR3CN0, #00h                  ; Timer3 disabled and interrupt flag cleared
    clr  C
    clr  A
    subb A, Temp1                       ; Set timeout
    mov  TMR3L, A
    clr  A
    subb A, Temp2
    mov  TMR3H, A
    mov  TMR3CN0, #04h                  ; Timer3 enabled and interrupt flag cleared
    setb Flag_Timer3_Pending
    orl  EIE1, #80h                     ; Enable Timer3 interrupts
    setb IE_EA

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
    mov  B, #00h                        ; Desired comparator output
    jnb  Flag_Dir_Change_Brake, comp_init
    mov  B, #40h
    sjmp comp_init

wait_for_comp_out_high:
    mov  B, #40h                        ; Desired comparator output
    jnb  Flag_Dir_Change_Brake, comp_init
    mov  B, #00h

comp_init:
    setb Flag_Demag_Detected            ; Set demag detected flag as default
    mov  Comparator_Read_Cnt, #0        ; Reset number of comparator reads

comp_start:
    ; Set number of comparator readings required
    mov  Temp3, #(1 SHL IS_MCU_48MHZ)   ; Number of OK readings required
    mov  Temp4, #(1 SHL IS_MCU_48MHZ)   ; Max number of readings required
    jb   Flag_High_Rpm, comp_check_timeout ; Branch if high rpm

    jnb  Flag_Initial_Run_Phase, comp_start_check_startup_phase
    clr  Flag_Demag_Detected            ; Clear demag detected flag if start phases

comp_start_check_startup_phase:
    jnb  Flag_Startup_Phase, comp_not_startup
    mov  Temp3, #(27 SHL IS_MCU_48MHZ)  ; Set many samples during startup,approximately one pwm period
    mov  Temp4, #(27 SHL IS_MCU_48MHZ)
    sjmp comp_check_timeout

comp_not_startup:
    ; Too low value (~<15) causes rough running at pwm harmonics.
    ; Too high a value (~>35) causes the RCT4215 630 to run rough on full throttle
    mov  Temp4, #(20 SHL IS_MCU_48MHZ)
    mov  A, Comm_Period4x_H             ; Set number of readings higher for lower speeds
    jnz  comp_not_startup_check_ok_readings
    inc  A                              ; Minimum 1

comp_not_startup_check_ok_readings:
    mov  Temp3, A
    clr  C
    subb A, #(20 SHL IS_MCU_48MHZ)
    jc   comp_check_timeout
    mov  Temp3, #(20 SHL IS_MCU_48MHZ)  ; Maximum 20

comp_check_timeout:
    jb   Flag_Timer3_Pending, comp_check_timeout_not_timed_out ; Has zero cross scan timeout elapsed?

    mov  A, Comparator_Read_Cnt         ; Check that comparator has been read
    jz   comp_check_timeout_not_timed_out ; If not yet read - ignore zero cross timeout

    jnb  Flag_Startup_Phase, comp_check_timeout_timeout_extended

    ; Extend timeout during startup
    djnz Startup_Zc_Timeout_Cntd, comp_check_timeout_extend_timeout

comp_check_timeout_timeout_extended:
    setb Flag_Comp_Timed_Out
    sjmp comp_exit

comp_check_timeout_extend_timeout:
    call setup_zc_scan_timeout

comp_check_timeout_not_timed_out:
    inc  Comparator_Read_Cnt            ; Increment comparator read count
    Read_Comparator_Output
    anl  A, #40h
    cjne A, B, comp_read_wrong

    ; Comp read ok
    mov  A, Startup_Cnt                 ; Force a timeout for the first commutation
    jz   comp_start

    jb   Flag_Demag_Detected, comp_start ; Do not accept correct comparator output if it is demag

    djnz Temp3, comp_check_timeout      ; Decrement readings counter - repeat comparator reading if not zero

    clr  Flag_Comp_Timed_Out
    sjmp comp_exit

comp_read_wrong:
    jb   Flag_Startup_Phase, comp_read_wrong_startup
    jb   Flag_Demag_Detected, comp_read_wrong_extend_timeout

    inc  Temp3                          ; Increment number of OK readings required
    clr  C
    mov  A, Temp3
    subb A, Temp4
    jc   comp_check_timeout             ; If below initial requirement - take another reading
    sjmp comp_start                     ; Otherwise - go back and restart

comp_read_wrong_startup:
    inc  Temp3                          ; Increment number of OK readings required
    clr  C
    mov  A, Temp3
    subb A, Temp4                       ; If above initial requirement - do not increment further
    jc   comp_read_wrong_startup_jump   ; TODO: Skip this jump to optimize
    dec  Temp3

comp_read_wrong_startup_jump:
    sjmp comp_check_timeout             ; Continue to look for good ones

comp_read_wrong_extend_timeout:
    clr  Flag_Demag_Detected            ; Clear demag detected flag
    anl  EIE1, #7Fh                     ; Disable Timer3 interrupts
    mov  TMR3CN0, #00h                  ; Timer3 disabled and interrupt flag cleared
    jnb  Flag_High_Rpm, comp_read_wrong_low_rpm ; Branch if not high rpm

    mov  TMR3L, #0                      ; Set timeout to ~1ms
    mov  TMR3H, #-(8 SHL IS_MCU_48MHZ)

comp_read_wrong_timeout_set:
    mov  TMR3CN0, #04h                  ; Timer3 enabled and interrupt flag cleared
    setb Flag_Timer3_Pending
    orl  EIE1, #80h                     ; Enable Timer3 interrupts
    ljmp comp_start                     ; If comparator output is not correct - go back and restart

comp_read_wrong_low_rpm:
    mov  A, Comm_Period4x_H             ; Set timeout to ~4x comm period 4x value
    mov  Temp7, #0FFh                   ; Default to long timeout

IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    clr  C
    rlc  A
    jc   comp_read_wrong_load_timeout
ENDIF

    clr  C
    rlc  A
    jc   comp_read_wrong_load_timeout

    clr  C
    rlc  A
    jc   comp_read_wrong_load_timeout

    mov  Temp7, A

comp_read_wrong_load_timeout:
    clr  C
    clr  A
    subb A, Temp7
    mov  TMR3L, #0
    mov  TMR3H, A
    sjmp comp_read_wrong_timeout_set

comp_exit:

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Setup commutation timing
;
; Clear the zero cross timeout and sets up wait from zero cross to commutation
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
setup_comm_wait:
    clr  IE_EA
    anl  EIE1, #7Fh                     ; Disable Timer3 interrupts

    ; It is necessary to update the timer reload registers before the timer registers,
    ; to avoid a reload of the previous values in case of a short Wt_Comm_Start delay.

    ; Advance wait time will be loaded by Timer3 immediately after the commutation wait elapses
    mov  TMR3RLL, Wt_Adv_Start_L        ; Setup next wait time
    mov  TMR3RLH, Wt_Adv_Start_H
    mov  TMR3CN0, #00h                  ; Timer3 disabled and interrupt flag cleared
    mov  TMR3L, Wt_Comm_Start_L
    mov  TMR3H, Wt_Comm_Start_H
    mov  TMR3CN0, #04h                  ; Timer3 enabled and interrupt flag cleared

    setb Flag_Timer3_Pending
    orl  EIE1, #80h                     ; Enable Timer3 interrupts
    setb IE_EA                          ; Enable interrupts again

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Evaluate comparator integrity
;
; Checks comparator signal behavior versus expected behavior
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
evaluate_comparator_integrity:
    jb   Flag_Startup_Phase, eval_comp_startup ; Do not exit run mode during startup phases

    jnb  Flag_Comp_Timed_Out, eval_comp_exit ; Has timeout elapsed?
    jb   Flag_Initial_Run_Phase, eval_comp_exit ; Do not exit run mode if initial run phase
    jb   Flag_Dir_Change_Brake, eval_comp_exit ; Do not exit run mode if braking
    jb   Flag_Demag_Detected, eval_comp_exit ; Do not exit run mode if it is a demag situation

    ; Disable all interrupts and cut power ASAP. They will be enabled in exit_run_mode_on_timeout
    clr  IE_EA
    call switch_power_off

    ; Routine exit without "ret" command
    dec  SP
    dec  SP

    ; Go to exit run mode if timeout has elapsed
    ljmp exit_run_mode_on_timeout

eval_comp_startup:
    inc  Startup_Cnt                    ; Increment startup counter

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
    mov  A, Demag_Detected_Metric       ; Sliding average of 8,256 when demag and 0 when not. Limited to minimum 120
    mov  B, #7
    mul  AB                             ; Multiply by 7

    jnb  Flag_Demag_Detected, wait_for_comm_demag_event_added
    ; Add new value for current demag status
    inc  B
    ; Signal demag
    setb Flag_Demag_Notify

wait_for_comm_demag_event_added:
    mov  C, B.0                         ; Divide by 8
    rrc  A
    mov  C, B.1
    rrc  A
    mov  C, B.2
    rrc  A
    mov  Demag_Detected_Metric, A
    clr  C
    subb A, #120                        ; Limit to minimum 120
    jnc  wait_for_comm_update_demag_metric_max
    mov  Demag_Detected_Metric, #120

wait_for_comm_update_demag_metric_max:
    ; Update demag metric max
    clr  C
    mov  A, Demag_Detected_Metric
    subb A, Demag_Detected_Metric_Max
    jc   wait_for_comm_demag_metric_max_updated
    mov  Demag_Detected_Metric_Max, Demag_Detected_Metric

wait_for_comm_demag_metric_max_updated:
    ; Check demag metric
    clr  C
    mov  A, Demag_Detected_Metric
    subb A, Demag_Pwr_Off_Thresh
    jc   wait_for_comm_wait

    ; Signal desync
    setb Flag_Desync_Notify

    ; Cut power if many consecutive demags are detected.
    ; This will help retain sync during hard accelerations.
    All_Pwm_Fets_Off
    Set_All_Pwm_Phases_Off

wait_for_comm_wait:
    ; If it has not already, we wait for the Wt_Comm_Start_ delay to elapse.
    Wait_For_Timer3

    ; At this point Timer3 has (already) wrapped and been reloaded with
    ; the Wt_Adv_Start_ delay.
    ;
    ; In case this delay has also elapsed, Timer3 has been reloaded with a short
    ; delay any number of times.
    ; - The interrupt flag is set and the pending flag will clear immediately
    ;   after enabling the interrupt.
    mov  TMR3RLL, Wt_Zc_Scan_Start_L    ; Setup next wait time
    mov  TMR3RLH, Wt_Zc_Scan_Start_H
    setb Flag_Timer3_Pending
    orl  EIE1, #80h                     ; Enable Timer3 interrupts
    ret
