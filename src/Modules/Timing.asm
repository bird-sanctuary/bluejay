;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Bluejay digital ESC firmware for controlling brushless motors in multirotors
;
; Copyleft  2022-2023 Daniel Mosquera
;
; The work in this would not be possible with the help and previous work of:
;   stylesuxx, burdalfis, saidinesh5
;   Copyright 2020-2022 Mathias Rasmussen's Bluejay
;   Copyright 2011-2017 Steffen Skaug's Blheli/Blheli_S
;   Bernard Konze's BLMC: http://home.versanet.de/~bkonze/blc_6a/blc_6a.htm
;   Simon Kirby's TGY: https://github.com/sim-/tgy
;
; This file is part of Bluejay.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Timing module
;
;   This module is in charge of:
;       - calculating 4 times commutation period (4x60deg): Comm_Period4x
;       - calculating 7.5deg time quanta: Wt_Zc_Scan_Time_Quanta
;       - calculating 15deg zero cross to commutation time: Wt_Zc_2_Comm
;       - counting 7.5deg while times are calculated
;       - waiting remaining 7.5deg time before zero cross scanning
;       - zero cross scanning for 37.5deg
;       - waiting before commutate for 15deg
;
; Commutation:
;
;                           60deg
;   -------------------------------------------------------
;   |  7.5deg | 37.5deg scan             | 15deg wait com |
;   L-----------------------------------------------------|
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Calculate next commutation period
;
; Adds initial wait of 7.5deg before starting zero cross scan
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
; Comm_Period4x = 0xF000
;
; Simple example using 16 and 4 dividers:
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
    ; Prepare the 7.5deg timer to wait before zero cross scan
    mov TMR3CN0, #0                 ; Disable timer3 and clear flags
    mov TMR3L, Wt_Zc_Scan_Time_Quanta_L
    mov TMR3H, Wt_Zc_Scan_Time_Quanta_H
    mov TMR3CN0, #4                 ; Enable timer3 and clear flags

    ; Read commutation time into A:Temp2:1
    clr TMR2CN0_TR2                 ; Stop Timer2
    mov Temp1, TMR2L                ; Load Timer2 value
    mov Temp2, TMR2H
    mov Temp3, Timer2_X
    setb    TMR2CN0_TR2             ; Continue Timer2

calc_next_comm_normal:
    ; Calculate this commutation time and store in Temp3:2:1
    clr C
    mov A, Temp1
    subb    A, Prev_Comm_B0         ; Calculate the new commutation time
    mov Prev_Comm_B0, Temp1         ; Save timestamp as previous commutation
    mov Temp1, A                    ; Store commutation period in Temp1 (lo byte)
    mov A, Temp2
    subb    A, Prev_Comm_B1
    mov Prev_Comm_B1, Temp2         ; Save timestamp as previous commutation
    mov Temp2, A                    ; Store commutation period in Temp2 (mid byte)
    mov A, Temp3
    subb    A, Prev_Comm_B2
    mov Prev_Comm_B2, Temp3         ; Save timestamp as previous commutation
    mov Temp3, A                    ; Store commutation period in Temp3 (hi byte)

    ; Comm_Period4x holds the time of 4 commutations
    mov Temp4, Comm_Period4x_B0
    mov Temp5, Comm_Period4x_B1
    mov Temp6, Comm_Period4x_B2

    ; Update Comm_Period4x from 1/4 new commutation period
    ; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 16) + (Comm_Period / 4)

    ; Divide Comm_Period4x (Temp6:5:4) by 16
    DivU24_By_16 Temp6, Temp5, Temp4

    ; Divide Comm_Period (Temp3:2:1) by 4
    DivU24_By_4 Temp3, Temp2, Temp1

    ; Subtract a fraction
    ; Comm_Period4x - (Comm_Period4x / 16) -> Temp6:5:4
    clr C
    mov A, Comm_Period4x_B0         ; Comm_Period4x_B0
    subb    A, Temp4
    mov Temp4, A
    mov A, Comm_Period4x_B1         ; Comm_Period4x_B1
    subb    A, Temp5
    mov Temp5, A
    mov A, Comm_Period4x_B2         ; Comm_Period4x_B2
    subb    A, Temp6
    mov Temp6, A

    ; Add the divided new time
    ; Comm_Period4x - (Comm_Period4x / 16) + (Comm_Period / 4) -> Temp6:5:4
    mov A, Temp4
    add A, Temp1
    mov Temp4, A
    mov A, Temp5
    addc    A, Temp2
    mov Temp5, A
    mov A, Temp6
    addc    A, Temp3
    mov Temp6, A

    ; Comm_Period4x holds the time of 4 commutations
    mov Comm_Period4x_B0, Temp4
    mov Comm_Period4x_B1, Temp5
    mov Comm_Period4x_B2, Temp6

calc_next_comm_15deg:
    ; Commutation period: 360 deg / 6 runs = 60 deg
    ; 60 deg / 4 = 15 deg

    ; Load current commutation timing and compute 15 deg timing
    ; Divide Comm_Period4x by 16 (Comm_Period1x divided by 4) and store in Temp6:5:4
    DivU24_By_16 Temp6, Temp5, Temp4

    ; Here Temp6 should be 0 (but just in case)
    mov A, Temp6
    jz calc_next_comm_period_exit

    ; If not 0 load highest value (Temp6 is not used)
    mov Temp5, #0FFh
    mov Temp4, #0FFh

calc_next_comm_period_exit:


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Calculate new wait times
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
calc_new_wait_times:
    ; Negate deg timming 15 deg in Temp5:4 and set it to Temp2:1
    clr C
    clr A
    subb    A, Temp4                ; Negate
    mov Temp1, A
    clr A
    subb    A, Temp5
    mov Temp2, A

    ; Zero cross to commutation is 15deg
    ; Temp2:1 = 15deg Timer2 period
    mov Wt_Zc_2_Comm_L, Temp1
    mov Wt_Zc_2_Comm_H, Temp2

    ; Zero cross scan time quanta is 7.5deg
    ; Temp4:3 = (15deg) / 2 = 7.5deg
    setb    C                       ; Adding negative numbers. Set carry
    mov A, Temp2                    ; Store 7.5deg in Temp4:3 (15deg / 2)
    rrc A
    mov Wt_Zc_Scan_Time_Quanta_H, A
    mov A, Temp1
    rrc A
    mov Wt_Zc_Scan_Time_Quanta_L, A

calc_new_wait_times_exit:
    ; Wait for 7.5deg before zc scan
    Wait_For_Timer3


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Load timer3 commutation wait timer before zero cross scan
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
load_wait_timer_before_zc_scan:
    ; Load timer for zero cross timeout
    ; Time precalculated for the following cases:
    ; - Flag_Initial_Run_Phase
    ; - Flag_Startup_Phase
    mov TMR3CN0, #0                 ; Disable timer3 and clear flags
    mov TMR3L, Wt_Zc_Scan_Time_Quanta_L    ; Setup next wait time
    mov TMR3H, Wt_Zc_Scan_Time_Quanta_H
    mov TMR3CN0, #4                 ; Enable timer3 and clear flags

    ; Allow up to zero cross 14 timeouts when motor is started:
    ;  105deg (60deg + 45deg), each zero cross timeout is 7.5deg
    mov Zc_Timeout_Cntd, #14

load_wait_timer_before_zc_scan_exit:
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
    mov B, #000h                 ; Desired comparator output
    jnb Flag_Dir_Change_Brake, comp_check_start
    mov B, #0C0h
    sjmp    comp_check_start

wait_for_comp_out_high:
    mov B, #0C0h                 ; Desired comparator output
    jnb Flag_Dir_Change_Brake, comp_check_start
    mov B, #000h

comp_check_start:
    ; Set number of comparator readings required
    mov Temp3, #(3 SHL IS_MCU_48MHZ)        ; Number of OK readings required
    mov Temp4, #(3 SHL IS_MCU_48MHZ)       	; Max wrong readings threshold

    jb Flag_Motor_Started, comp_check_timeout
    ; Set many samples if motor not started
    mov Temp3, #(27 SHL IS_MCU_48MHZ)
    mov Temp4, #(27 SHL IS_MCU_48MHZ)

comp_check_timeout:
    ; Check zero cross scan timeout has elapsed
	mov A, TMR3CN0
    jnb ACC.7, comp_check_timeout_not_timed_out

    ; If elapsed extend timeout if timeout counter > 0
    djnz    Zc_Timeout_Cntd, comp_check_timeout_extend_timeout

    ; Timeout elapsed with no reads during all zero cross timeout
    sjmp    comp_exit

comp_check_timeout_extend_timeout:
    ; Reload timer for zero cross timeout
    mov TMR3CN0, #0                 ; Disable timer3 and clear flags
    mov TMR3L, Wt_Zc_Scan_Time_Quanta_L    ; Setup next wait time
    mov TMR3H, Wt_Zc_Scan_Time_Quanta_H
    mov TMR3CN0, #4                 ; Enable timer3 and clear flags

comp_check_timeout_not_timed_out:
    ; Use 3x sampling to increase noise rejection
    ; Initialize sample accumulator
    mov Temp1, #0

    ; Read sample 1 and add it to Temp1
    Read_Comparator_Output
    anl A, #40h
    add A, Temp1
    mov Temp1, A
    nop
    nop
    nop

    ; Read sample 2 and add it to Temp1
    Read_Comparator_Output
    anl A, #40h
    add A, Temp1
    mov Temp1, A
    nop
    nop
    nop

    ; Read sample 3 and add it to Temp1
    Read_Comparator_Output
    anl A, #40h
    add A, Temp1

    ; Check comparator
    cjne    A, B, comp_read_wrong

    ; Decrement reads counter until 0
    djnz    Temp3, comp_check_timeout

    ; Zero cross detected
    sjmp    comp_exit

comp_read_wrong:
    ; if (good reads to do < max good) then C = 1;
    clr C
    mov A, Temp3
    subb    A, Temp4

    ; If good reads to do < max good reads then increment good reads
    mov A, Temp3
    addc    A, #0   ; A = A + 0 + C
    mov Temp3, A

    sjmp    comp_check_timeout              ; Otherwise - go back and restart

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
    jnb Flag_Motor_Started, eval_comp_startup
    jb  Flag_Dir_Change_Brake, eval_comp_good   ; Do not exit run mode if braking

    ; Do not exit run mode if comparator timeout is not zero
    mov A, Zc_Timeout_Cntd
    jnz eval_comp_good

    ; Inmediately cut power on timeout to avoid damage
    All_Pwm_Fets_Off
    Set_All_Pwm_Phases_Off

	; Signal stall
	setb	Flag_Desync_Notify

	; Routine exit without "ret" command
;	clr IE_EA
;    dec SP
;    dec SP
;    setb IE_EA
;    ljmp    exit_run_mode_on_timeout            ; Exit run mode if timeout has elapsed

    ; Commutation is no good
    jmp eval_comp_exit

eval_comp_startup:
    ; Increment startup counter
    inc Startup_Cnt

    ; Do not exit run mode if comparator timeout is not zero
    mov A, Zc_Timeout_Cntd
    jnz eval_comp_good

    ; Set counter to 0 again if timeout expires
    mov Startup_Cnt, #0

    ; Restart timing at startup to 328rpm
    mov Comm_Period4x_B0, #000h
    mov Comm_Period4x_B1, #080h

    ; Inmediately cut power on timeout to avoid damage
    All_Pwm_Fets_Off
    Set_All_Pwm_Phases_Off

    ; Commutation is no good
    jmp eval_comp_exit

eval_comp_good:


eval_comp_exit:


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait for commutation
;
; Waits from zero cross to commutation
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_for_comm:
    Wait_For_Timer3
    ret
