;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; DShot
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Detect DShot RCP level
;
; Determine if RCP signal level is normal or inverted DShot
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
detect_rcp_level:
    mov A, #50                  ; Must detect the same level 50 times (25 us)
    mov C, RTX_BIT

detect_rcp_level_read:
    jc  ($+5)
    jb  RTX_BIT, detect_rcp_level   ; Level changed from low to high - start over
    jnc ($+5)
    jnb RTX_BIT, detect_rcp_level   ; Level changed from high to low - start over
    djnz    ACC, detect_rcp_level_read

    mov Flag_Rcp_DShot_Inverted, C
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Check DShot command
;
; Determine received DShot command and perform action
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
dshot_cmd_check:
    mov A, DShot_Cmd
    jnz dshot_cmd_beeps_check
    ret

dshot_cmd_beeps_check:
    mov Temp1, A
    clr C
    subb    A, #6               ; Beacon beeps for command 1-5
    jnc dshot_cmd_check_count

    clr IE_EA                   ; Disable all interrupts
    call    switch_power_off    ; Switch power off in case braking is set
    call    beacon_beep
    call    wait200ms           ; Wait a bit for next beep
    setb    IE_EA               ; Enable all interrupts

    sjmp    dshot_cmd_exit

dshot_cmd_check_count:
    ; Remaining commands must be received 6 times in a row
    clr C
    mov A, DShot_Cmd_Cnt
    subb    A, #6
    jc  dshot_cmd_exit_no_clear

dshot_cmd_direction_normal:
    ; Set motor spinning direction to normal
    cjne    Temp1, #7, dshot_cmd_direction_reverse

    clr Flag_Pgm_Dir_Rev

    sjmp    dshot_cmd_exit

dshot_cmd_direction_reverse:
    ; Set motor spinning direction to reversed
    cjne    Temp1, #8, dshot_cmd_direction_bidir_off

    setb    Flag_Pgm_Dir_Rev

    sjmp    dshot_cmd_exit

dshot_cmd_direction_bidir_off:
    ; Set motor control mode to normal (not bidirectional)
    cjne    Temp1, #9, dshot_cmd_direction_bidir_on

    clr Flag_Pgm_Bidir

    sjmp    dshot_cmd_exit

dshot_cmd_direction_bidir_on:
    ; Set motor control mode to bidirectional
    cjne    Temp1, #10, dshot_cmd_extended_telemetry_enable

    setb    Flag_Pgm_Bidir

    sjmp    dshot_cmd_exit

dshot_cmd_extended_telemetry_enable:
    ; Enable extended telemetry
    cjne    Temp1, #13, dshot_cmd_extended_telemetry_disable

    mov Ext_Telemetry_L, #00h
    mov Ext_Telemetry_H, #0Eh   ; Send state/event 0 frame to signal telemetry enable

    setb    Flag_Ext_Tele

    sjmp    dshot_cmd_exit

dshot_cmd_extended_telemetry_disable:
    ; Disable extended telemetry
    cjne    Temp1, #14, dshot_cmd_direction_user_normal

    mov Ext_Telemetry_L, #0FFh
    mov Ext_Telemetry_H, #0Eh   ; Send state/event 0xff frame to signal telemetry disable

    clr     Flag_Ext_Tele

    sjmp    dshot_cmd_exit

dshot_cmd_direction_user_normal:
    ; Set motor spinning direction to user programmed direction
    cjne    Temp1, #20, dshot_cmd_direction_user_reverse

    mov Temp2, #Pgm_Direction       ; Read programmed direction
    mov A, @Temp2
    dec A
    mov C, ACC.0                    ; Set direction
    mov Flag_Pgm_Dir_Rev, C

    ; Indicate that forced reverse operation is off
    clr Flag_Forced_Rev_Operation

    sjmp    dshot_cmd_exit

dshot_cmd_direction_user_reverse:       ; Temporary reverse
    ; Set motor spinning direction to reverse of user programmed direction
    cjne    Temp1, #21, dshot_cmd_save_settings

    mov Temp2, #Pgm_Direction       ; Read programmed direction
    mov A, @Temp2
    dec A
    mov C, ACC.0
    cpl C                       ; Set reverse direction
    mov Flag_Pgm_Dir_Rev, C

    ; Indicate that forced reverse operation is on
    setb Flag_Forced_Rev_Operation

    sjmp    dshot_cmd_exit

dshot_cmd_save_settings:
    cjne    Temp1, #12, dshot_cmd_exit

    clr A                       ; Set programmed direction from flags
    mov C, Flag_Pgm_Dir_Rev
    mov ACC.0, C
    mov C, Flag_Pgm_Bidir
    mov ACC.1, C
    inc A
    mov Temp2, #Pgm_Direction       ; Store programmed direction
    mov @Temp2, A

    mov Flash_Key_1, #0A5h          ; Initialize flash keys to valid values
    mov Flash_Key_2, #0F1h

    call    erase_and_store_all_in_eeprom

    mov Flash_Key_1, #0         ; Reset flash keys to invalid values
    mov Flash_Key_2, #0

    setb    IE_EA

dshot_cmd_exit:
    mov DShot_Cmd, #0               ; Clear DShot command and exit
    mov DShot_Cmd_Cnt, #0

dshot_cmd_exit_no_clear:
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; DShot telemetry create packet
;
; Create DShot telemetry packet and prepare it for being sent
; The routine is divided into 6 sections that can return early
; in order to reduce commutation interference
;
; Requirements:
; - Must NOT be called while Flag_Telemetry_Pending is set
; - Must NOT write to Temp7, Temp8
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

DSHOT_TLM_CREATE_PACKET_STAGE_0  EQU 0
DSHOT_TLM_CREATE_PACKET_STAGE_1  EQU 2
DSHOT_TLM_CREATE_PACKET_STAGE_2  EQU 4
DSHOT_TLM_CREATE_PACKET_STAGE_3  EQU 6
DSHOT_TLM_CREATE_PACKET_STAGE_4  EQU 8
DSHOT_TLM_CREATE_PACKET_STAGE_5  EQU 10

dshot_tlmpacket_stm:
    jnb  Flag_Telemetry_Pending, dshot_tlmpacket_begin
    ret

dshot_tlmpacket_begin:
    ; Select register bank 2
    push    PSW
    mov PSW, #10h

    ; Jump to the current stage
    mov A, Temp7
    mov DPTR, #dshot_tlmpacket_stm_table
    jmp @A+DPTR

dshot_tlmpacket_stm_table:
    ajmp    dshot_tlmpacket_stm_stage0
    ajmp    dshot_tlmpacket_stm_stage1
    ajmp    dshot_tlmpacket_stm_stage2
    ajmp    dshot_tlmpacket_stm_stage3
    ajmp    dshot_tlmpacket_stm_stage4
    ajmp    dshot_tlmpacket_stm_stage5


dshot_tlmpacket_stm_stage0:
    ; If extended telemetry ready jump to telemetry ready
    mov A, Ext_Telemetry_H
    jnz dshot_tlmpacket_stm_ready

    clr IE_EA
    mov A, Comm_Period4x_L          ; Read commutation period
    mov Tlm_Data_H, Comm_Period4x_H
    setb    IE_EA

    ; Calculate e-period (6 commutations) in microseconds
    ; Comm_Period * 6 * 0.5 = Comm_Period4x * 3/4 (1/2 + 1/4)
    mov C, Tlm_Data_H.0
    rrc A
    mov Temp2, A
    mov C, Tlm_Data_H.1
    rrc A
    add A, Temp2
    mov Temp3, A                    ; Comm_Period3x_L

    mov A, Tlm_Data_H
    rr  A
    clr ACC.7
    mov Temp2, A
    rr  A
    clr ACC.7
    addc    A, Temp2
    mov Temp4, A                    ; Comm_Period3x_H

    ; Timer2 ticks are ~489ns (not 500ns), so use approximation for better accuracy:
    ; E-period = Comm_Period3x - 4 * Comm_Period4x_H

    ; Note: For better performance assume Comm_Period4x_H < 64 (6-bit, above ~5k erpm)
    ; At lower speed result will be less precise
    mov A, Tlm_Data_H               ; Comm_Period4x_H
    rl  A                       ; Multiply by 4
    rl  A
    anl A, #0FCh
    mov Temp5, A

    clr C
    mov A, Temp3                    ; Comm_Period3x_L
    subb    A, Temp5
    mov Tlm_Data_L, A
    mov A, Temp4                    ; Comm_Period3x_H
    subb    A, #0
    mov Tlm_Data_H, A

dshot_tlmpacket_stm_ready:
    ; If timer3 has not been triggered we can continue
    jb  Flag_Timer3_Pending, dshot_tlmpacket_stm_stage1

    ; Store state and return
    mov Temp7, #DSHOT_TLM_CREATE_PACKET_STAGE_1
    pop PSW
    ret


dshot_tlmpacket_stm_stage1:
    ; If extended telemetry ready jump to extended telemetry coded
    mov A, Ext_Telemetry_H
    jnz dshot_tlmpacket_stm_ext_coded

    ; 12-bit encode exponent
    mov A, Tlm_Data_H
    jnz dshot_expo_encode
    mov A, Tlm_Data_L               ; Already 12-bit
    jnz dshot_tlmpacket_stm_expo_encoded

    ; If period is zero then reset to FFFFh (FFFh for 12-bit)
    mov Tlm_Data_H, #0Fh
    mov Tlm_Data_L, #0FFh
    sjmp dshot_tlmpacket_stm_expo_encoded

dshot_tlmpacket_stm_ext_coded:
    ; Move extended telemetry data to telemetry data to send
    mov Tlm_Data_L, Ext_Telemetry_L
    mov Tlm_Data_H, Ext_Telemetry_H
    ; Clear extended telemetry data
    mov Ext_Telemetry_H, #0

dshot_tlmpacket_stm_expo_encoded:
    ; If timer3 has not been triggered we can continue
    jb  Flag_Timer3_Pending, dshot_tlmpacket_stm_stage2

    ; Store state and return
    mov Temp7, #DSHOT_TLM_CREATE_PACKET_STAGE_2
    pop PSW
    ret


dshot_tlmpacket_stm_stage2:
    mov A, Tlm_Data_L

    ; Compute inverted xor checksum (4-bit)
    swap    A
    xrl A, Tlm_Data_L
    xrl A, Tlm_Data_H
    cpl A

    ; GCR encode the telemetry data (16-bit)
    mov Temp1, #Temp_Storage        ; Store pulse timings in Temp_Storage
    mov @Temp1, DShot_GCR_Pulse_Time_1; Final transition time

    call    dshot_gcr_encode            ; GCR encode lowest 4-bit of A (store through Temp1)

    ; If timer3 has not been triggered we can continue
    jb  Flag_Timer3_Pending, dshot_tlmpacket_stm_stage3

    ; Store state and return
    mov Temp7, #DSHOT_TLM_CREATE_PACKET_STAGE_3
    pop PSW
    ret


dshot_tlmpacket_stm_stage3:
    mov A, Tlm_Data_L
    call    dshot_gcr_encode

    ; If timer3 has not been triggered we can continue
    jb  Flag_Timer3_Pending, dshot_tlmpacket_stm_stage4

    ; Store state and return
    mov Temp7, #DSHOT_TLM_CREATE_PACKET_STAGE_4
    pop PSW
    ret


dshot_tlmpacket_stm_stage4:
    mov A, Tlm_Data_L
    swap    A
    call    dshot_gcr_encode

    ; If timer3 has not been triggered we can continue
    jb  Flag_Timer3_Pending, dshot_tlmpacket_stm_stage5

    ; Store state and return
    mov Temp7, #DSHOT_TLM_CREATE_PACKET_STAGE_5
    pop PSW
    ret


dshot_tlmpacket_stm_stage5:
    mov A, Tlm_Data_H
    call    dshot_gcr_encode

    inc Temp1
    mov Temp7, #DSHOT_TLM_CREATE_PACKET_STAGE_0  ; Reset current packet stage

    pop PSW
    setb    Flag_Telemetry_Pending      ; Mark that packet is ready to be sent
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; DShot 12-bit encode
;
; Encodes 16-bit e-period as a 12-bit value of the form:
; <e e e m m m m m m m m m> where M SHL E ~ e-period [us]
;
; Note: Not callable to improve performance
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
dshot_expo_encode:
    ; Encode 16-bit e-period as a 12-bit value
    jb  ACC.7, dshot_12bit_7        ; ACC = Tlm_Data_H
    jb  ACC.6, dshot_12bit_6
    jb  ACC.5, dshot_12bit_5
    jb  ACC.4, dshot_12bit_4
    jb  ACC.3, dshot_12bit_3
    jb  ACC.2, dshot_12bit_2
    jb  ACC.1, dshot_12bit_1
    mov A, Tlm_Data_L               ; Already 12-bit (E=0)
    ajmp    dshot_tlmpacket_stm_expo_encoded

dshot_12bit_7:
    ;mov    A, Tlm_Data_H
    mov C, Tlm_Data_L.7
    rlc A
    mov Tlm_Data_L, A
    mov Tlm_Data_H, #0fh
    ajmp    dshot_tlmpacket_stm_expo_encoded

dshot_12bit_6:
    ;mov    A, Tlm_Data_H
    mov C, Tlm_Data_L.7
    rlc A
    mov C, Tlm_Data_L.6
    rlc A
    mov Tlm_Data_L, A
    mov Tlm_Data_H, #0dh
    ajmp    dshot_tlmpacket_stm_expo_encoded

dshot_12bit_5:
    ;mov    A, Tlm_Data_H
    mov C, Tlm_Data_L.7
    rlc A
    mov C, Tlm_Data_L.6
    rlc A
    mov C, Tlm_Data_L.5
    rlc A
    mov Tlm_Data_L, A
    mov Tlm_Data_H, #0bh
    ajmp    dshot_tlmpacket_stm_expo_encoded

dshot_12bit_4:
    mov A, Tlm_Data_L
    anl A, #0f0h
    clr Tlm_Data_H.4
    orl A, Tlm_Data_H
    swap    A
    mov Tlm_Data_L, A
    mov Tlm_Data_H, #09h
    ajmp    dshot_tlmpacket_stm_expo_encoded

dshot_12bit_3:
    mov A, Tlm_Data_L
    mov C, Tlm_Data_H.0
    rrc A
    mov C, Tlm_Data_H.1
    rrc A
    mov C, Tlm_Data_H.2
    rrc A
    mov Tlm_Data_L, A
    mov Tlm_Data_H, #07h
    ajmp    dshot_tlmpacket_stm_expo_encoded

dshot_12bit_2:
    mov A, Tlm_Data_L
    mov C, Tlm_Data_H.0
    rrc A
    mov C, Tlm_Data_H.1
    rrc A
    mov Tlm_Data_L, A
    mov Tlm_Data_H, #05h
    ajmp    dshot_tlmpacket_stm_expo_encoded

dshot_12bit_1:
    mov A, Tlm_Data_L
    mov C, Tlm_Data_H.0
    rrc A
    mov Tlm_Data_L, A
    mov Tlm_Data_H, #03h
    ajmp    dshot_tlmpacket_stm_expo_encoded


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; DShot GCR encode
;
; GCR encode e-period data for DShot telemetry
;
; Input
; - Temp1: Data pointer for storing pulse timings
; - A: 4-bit value to GCR encode
; - B: Time that must be added to transition
; Output
; - B: Time remaining to be added to next transition
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
dshot_gcr_encode:
    anl A, #0Fh
    rl  A   ; Multiply by 2 to match jump offsets
    mov DPTR, #dshot_gcr_encode_jump_table
    jmp @A+DPTR

dshot_gcr_encode_jump_table:
    ajmp    dshot_gcr_encode_0_11001
    ajmp    dshot_gcr_encode_1_11011
    ajmp    dshot_gcr_encode_2_10010
    ajmp    dshot_gcr_encode_3_10011
    ajmp    dshot_gcr_encode_4_11101
    ajmp    dshot_gcr_encode_5_10101
    ajmp    dshot_gcr_encode_6_10110
    ajmp    dshot_gcr_encode_7_10111
    ajmp    dshot_gcr_encode_8_11010
    ajmp    dshot_gcr_encode_9_01001
    ajmp    dshot_gcr_encode_A_01010
    ajmp    dshot_gcr_encode_B_01011
    ajmp    dshot_gcr_encode_C_11110
    ajmp    dshot_gcr_encode_D_01101
    ajmp    dshot_gcr_encode_E_01110
    ajmp    dshot_gcr_encode_F_01111

; GCR encoding is ordered by least significant bit first,
; and represented as pulse durations.
dshot_gcr_encode_0_11001:
    imov    Temp1, DShot_GCR_Pulse_Time_3
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_1_11011:
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_2_10010:
    GCR_Add_Time    Temp1
    imov    Temp1, DShot_GCR_Pulse_Time_3
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_3_10011:
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_3
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_4_11101:
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_5_10101:
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_6_10110:
    GCR_Add_Time    Temp1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_7_10111:
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_8_11010:
    GCR_Add_Time    Temp1
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_9_01001:
    imov    Temp1, DShot_GCR_Pulse_Time_3
    imov    Temp1, DShot_GCR_Pulse_Time_2
    ret

dshot_gcr_encode_A_01010:
    GCR_Add_Time    Temp1
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_2
    ret

dshot_gcr_encode_B_01011:
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_2
    ret

dshot_gcr_encode_C_11110:
    GCR_Add_Time    Temp1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    ret

dshot_gcr_encode_D_01101:
    imov    Temp1, DShot_GCR_Pulse_Time_2
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_2
    ret

dshot_gcr_encode_E_01110:
    GCR_Add_Time    Temp1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_2
    ret

dshot_gcr_encode_F_01111:
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_1
    imov    Temp1, DShot_GCR_Pulse_Time_2
    ret



;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; DShot rcpulse state machine
;
; Processes rc pulse in multiple stages
;
; Uses Temp1:2:3:4:5
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

DSHOT_RCPULSE_STATE_DONE            EQU 0       ; done state
DSHOT_RCPULSE_STATE_START           EQU 2       ; start state
DSHOT_RCPULSE_STATE_BIDIRCK         EQU 4       ; bidirectional (3D) check state
DSHOT_RCPULSE_STATE_BOOST           EQU 6       ; stall boost state
DSHOT_RCPULSE_STATE_PWM_LIMIT       EQU 8       ; apply pwm limit state
DSHOT_RCPULSE_STATE_DYNAMIC_PWM     EQU 10      ; choose dynamic pwm frequency state
DSHOT_RCPULSE_STATE_LSD             EQU 12      ; limit pwm, scale & calculate dithering pattern
DSHOT_RCPULSE_STATE_SET_DAMP        EQU 14      ; set damp state
DSHOT_RCPULSE_STATE_SET_PWM         EQU 16      ; set pwm state

dshot_rcpulse_stm:
    ; Load context
	push B

    ; Jump to stm's current state
    mov A, DShot_rcpulse_stm_state
    mov DPTR, #dshot_rcpulse_stm_jump_table
    jmp @A+DPTR

dshot_rcpulse_stm_jump_table:
    ajmp dshot_rcpulse_stm_end
    ajmp dshot_rcpulse_stm_start_state
    ajmp dshot_rcpulse_stm_bidirck_state
    ajmp dshot_rcpulse_stm_boost_state
    ajmp dshot_rcpulse_stm_pwm_limit_state
    ajmp dshot_rcpulse_stm_dynamic_pwm_state
    ajmp dshot_rcpulse_stm_pwm_limit_scale_dithering_state
    ajmp dshot_rcpulse_stm_set_damp_state
    ajmp dshot_rcpulse_stm_set_pwm_state



    ; ********************************** START STATE *******************************
dshot_rcpulse_stm_start_state:
    ; Invert DShot data and substract 96 (still 12 bits)
    clr C
    mov A, Temp4
    cpl A
    mov Temp3, A                    ; Store in case it is a DShot command
    subb    A, #96
    mov Temp4, A
    mov A, Temp5
    cpl A
    anl A, #0Fh
    subb    A, #0
    mov Temp5, A
    jnc dshot_rcpulse_stm_normal_range

    ; Set pulse length to zero and stop
    setb    Flag_Rcp_Stop
    mov Temp4, #0
    mov Temp5, #0

    ; Check for 0 or DShot command
    mov A, Temp3
    jz  dshot_rcpulse_stm_set_cmd        ; Clear DShot command when RCP is zero

    clr C                           ; We are in the special DShot range
    rrc A                           ; Shift tlm bit into carry
    jnc dshot_rcpulse_stm_clear_cmd      ; Check for tlm bit set (if not telemetry, invalid command)

    cjne    A, DShot_Cmd, dshot_rcpulse_stm_set_cmd

    inc DShot_Cmd_Cnt
    sjmp    dshot_rcpulse_stm_normal_range

dshot_rcpulse_stm_clear_cmd:
    clr A

dshot_rcpulse_stm_set_cmd:
    mov DShot_Cmd, A
    mov DShot_Cmd_Cnt, #0

dshot_rcpulse_stm_normal_range:
    ; Store next state
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_BIDIRCK
    jmp dshot_rcpulse_stm_end



    ; ********************************** BIDIRECTIONAL (3D) CHECK STATE *******************************
dshot_rcpulse_stm_bidirck_state:
    ; Check for bidirectional operation (0=stop, 96-2095->fwd, 2096-4095->rev)
    jnb Flag_Pgm_Bidir, dshot_rcpulse_stm_not_bidir    ; If not bidirectional operation - branch

    ; Subtract 2000 (still 12 bits)
    clr C
    mov A, Temp4
    subb    A, #0D0h
    mov B, A
    mov A, Temp5
    subb    A, #07h
    jc  dshot_rcpulse_stm_bidir_set     ; Is result is positive?
    mov Temp4, B                        ; Yes - Use the subtracted value
    mov Temp5, A

dshot_rcpulse_stm_bidir_set:
    jnb Flag_Pgm_Dir_Rev, ($+4)         ; Check programmed direction
    cpl C                               ; Reverse direction
    mov Flag_Rcp_Dir_Rev, C             ; Set rcp direction

    clr C                               ; Multiply throttle value by 2
    rlca    Temp4
    rlca    Temp5

dshot_rcpulse_stm_not_bidir:
    ; From here Temp5/Temp4 should be at most 3999 (4095-96)
    mov A, Temp4                        ; Divide by 16 (12 to 8-bit)
    anl A, #0F0h
    orl A, Temp5                        ; Note: Assumes Temp5 to be 4-bit
    swap    A
    mov B, #5                           ; Divide by 5 (max 49)
    div AB
    mov Temp3, A

    ; Align to 11 bits
    ;clr    C                           ; Note: Cleared by div
    rrca    Temp5
    mov A, Temp4
    rrc A

    ; Scale from 2000 to 2048
    add A, Temp3
    mov Temp4, A
    mov A, Temp5
    addc    A, #0
    mov Temp5, A
    jnb ACC.3, ($+7)                    ; Limit to 11-bit maximum
    mov Temp4, #0FFh
    mov Temp5, #07h

dshot_rcpulse_stm_bidir_done:
    ; Store next state
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_BOOST
    jmp dshot_rcpulse_stm_end



    ; ********************************** BOOST STATE *******************************
dshot_rcpulse_stm_boost_state:
    ; Do not boost when changing direction in bidirectional mode
    jb  Flag_Motor_Started, dshot_rcpulse_stm_startup_boosted

    ; Boost pwm during direct start
    jnb Flag_Initial_Run_Phase, dshot_rcpulse_stm_startup_boosted

    ; Do not boost when rcpulse is 0
    mov A, Temp4
    orl A, Temp5
    jz dshot_rcpulse_stm_startup_boosted

    ; Enforce limit by RPM during startup
    mov Pwm_Limit_By_Rpm, Pwm_Limit_Beg

    ; Check more power is requested than the minimum required at startup
    mov A, Temp5
    jnz dshot_rcpulse_stm_stall_boost

    ; Read minimum startup power setting
    mov Temp2, #Pgm_Startup_Power_Min
    mov B, @Temp2

    clr C                       ; Set power to at least be minimum startup power
    mov A, Temp4
    subb    A, B
    jnc dshot_rcpulse_stm_stall_boost
    mov Temp4, B

dshot_rcpulse_stm_stall_boost:
    mov A, Stall_Counter        ; Check stall count
    jz  dshot_rcpulse_stm_startup_boosted
    mov B, #40                  ; Note: Stall count should be less than 6
    mul AB

    add A, Temp4                    ; Add more power when failing to start motor (stalling)
    mov Temp4, A
    mov A, Temp5
    addc    A, #0
    mov Temp5, A
    jnb ACC.3, ($+7)                ; Limit to 11-bit maximum
    mov Temp4, #0FFh
    mov Temp5, #07h

dshot_rcpulse_stm_startup_boosted:
    ; Store next state
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_PWM_LIMIT
    jmp dshot_rcpulse_stm_end



    ; ********************************** PWM LIMIT STATE *******************************
dshot_rcpulse_stm_pwm_limit_state:
    ; Set 8-bit value in Temp2
    mov A, Temp4
    anl A, #0F8h
    orl A, Temp5                    ; Assumes Temp5 to be 3-bit (11-bit rcp)
    swap    A
    rl  A
    mov Temp2, A

    jnz dshot_rcpulse_stm_rcp_not_zero

    mov A, Temp4                    ; Only set Rcp_Stop if all all 11 bits are zero
    jnz dshot_rcpulse_stm_rcp_not_zero

    setb    Flag_Rcp_Stop
    sjmp    dshot_rcpulse_stm_zero_rcp_checked

dshot_rcpulse_stm_rcp_not_zero:
    mov Rcp_Stop_Cnt, #0            ; Reset rcp stop counter
    clr Flag_Rcp_Stop               ; Pulse ready

dshot_rcpulse_stm_zero_rcp_checked:
    ; Decrement outside range counter
    mov A, Rcp_Outside_Range_Cnt
    jz  ($+4)
    dec Rcp_Outside_Range_Cnt

    ; Get minimum pwm limit between pwm rpm limit and pwm temperature limit (Pwm_Limit)
    clr C
    mov A, Pwm_Limit                ; Limit to the smallest
    mov Temp3, A                    ; Store limit in Temp3
    subb    A, Pwm_Limit_By_Rpm
    jc  ($+4)
    mov Temp3, Pwm_Limit_By_Rpm

dshot_rcpulse_stm_zero_rcp_done:
    ; Store next state
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_DYNAMIC_PWM
    jmp dshot_rcpulse_stm_end



    ; ********************************** DYNAMIC PWM STATE *******************************
dshot_rcpulse_stm_dynamic_pwm_state:
    ; If user requests inverted operation mode during startup with command 21
    ; (associated to turtle mode) go straight to 24khz mode to allow full
    ; torque, independently to the normal configuration. Inverted operation mode
    ; will be disabled as soon as user sends command 20 again (disable turtle mode)
    jb Flag_Forced_Rev_Operation, dshot_rcpulse_stm_dynamic_pwm_gt_hi_rcpulse

    ; Check variable pwm is enabled
    jnb Flag_Variable_Pwm_Bits, dshot_rcpulse_stm_dynamic_pwm_done

    ; If variable pwm, set pwm bits depending on PWM_CENTERED 1 [3-1] or 0 [2-0]
    ; and 8 bit rc pulse Temp2
    clr C
    mov A, Temp2                                        ; Load 8bit rc pulse

dshot_rcpulse_stm_dynamic_pwm_lt_lo_rcpulse:
    ; Compare rc pulse to Pgm_Var_PWM_lo_thres
    mov Temp1, #Pgm_Var_PWM_lo_thres                    ; Load low rc pulse threshold pointer
    subb    A, @Temp1
    jnc dshot_rcpulse_stm_dynamic_pwm_gt_lo_rcpulse

    ; rc pulse <= Pgm_Var_PWM_lo_thres -> choose 96khz
    mov PwmBitsCount, #0
    sjmp dshot_rcpulse_stm_dynamic_pwm_centered

dshot_rcpulse_stm_dynamic_pwm_gt_lo_rcpulse:
    ; rc pulse > Pgm_Var_PWM_lo_thres -> choose 48khz or 24khz
    mov Temp1, #Pgm_Var_PWM_hi_thres                    ; Load high rc pulse threshold pointer
    subb    A, @Temp1
    jnc dshot_rcpulse_stm_dynamic_pwm_gt_hi_rcpulse

    ; rc pulse <= Pgm_Var_PWM_hi_thres -> choose 48khz
    mov PwmBitsCount, #1
    sjmp dshot_rcpulse_stm_dynamic_pwm_centered

dshot_rcpulse_stm_dynamic_pwm_gt_hi_rcpulse:
    ; rc pulse > Pgm_Var_PWM_hi_thres -> choose 24khz
    mov PwmBitsCount, #2

dshot_rcpulse_stm_dynamic_pwm_centered:
IF PWM_CENTERED == 0
    ; Increment PwmBits count
    inc PwmBitsCount
ENDIF

dshot_rcpulse_stm_dynamic_pwm_done:
    ; Store next state
    ; No state
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_LSD
    jmp dshot_rcpulse_stm_end



    ; *********** LIMIT PWM, SCALE & CHOOSE DITHERING PATTERN STATE *******************
dshot_rcpulse_stm_pwm_limit_scale_dithering_state:
    ; Limit PWM and scale pwm resolution and invert (duty cycle is defined inversely)
    ; depending on pwm bits count
    mov A, PwmBitsCount

dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm11bit:
    cjne    A, #3, dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm10bit

    ; Check against pwm limit
    clr C
    mov A, Temp3
    subb    A, Temp2                ; Compare against 8-bit rc pulse
    jnc dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm11bit_limited

    ; Limit pwm to 9, 10, 11 bit pwm limit
    mov A, Temp3                    ; Multiply limit by 8 for 11-bit pwm
    mov B, #8
    mul AB
    mov Temp4, A
    mov Temp5, B

dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm11bit_limited:
    ; 11-bit pwm
    mov A, Temp5
    cpl A
    anl A, #7
    mov Temp3, A
    mov A, Temp4
    cpl A
    mov Temp2, A

    ; 11bit does not need 11bit dithering, only for 10, 9, and 8 bit pwm
    jmp dshot_rcpulse_stm_pwm_limit_scale_dithering_done

dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm10bit:
    cjne    A, #2, dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm9bit

    ; Check against pwm limit
    clr C
    mov A, Temp3
    subb    A, Temp2                ; Compare against 8-bit rc pulse
    jnc dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm10bit_limited

    ; Limit pwm to 9, 10, 11 bit pwm limit
    mov A, Temp3                    ; Multiply limit by 8 for 11-bit pwm
    mov B, #8
    mul AB
    mov Temp4, A
    mov Temp5, B

dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm10bit_limited:
    ; 10-bit pwm scaling
    clr C
    mov A, Temp5
    rrc A
    cpl A
    anl A, #3
    mov Temp3, A
    mov A, Temp4
    rrc A
    cpl A
    mov Temp2, A

    ; 11-bit effective dithering of 10-bit pwm
    jb Flag_Dithering, dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm10bit_scaled
    jmp dshot_rcpulse_stm_pwm_limit_scale_dithering_done              ; Long jmp needed here

dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm10bit_scaled:
    mov A, Temp4                    ; 11-bit low byte
    cpl A
    anl A, #((1 SHL (3 - 2)) - 1)   ; Get index [0,1] into dithering pattern table

    ; Multiplying by 4, select pattern [0, 4] on unified dithering pattern table
    rl A
    rl A

    add A, #Dithering_Patterns
    mov Temp1, A                    ; Reuse DShot pwm pointer since it is not currently in use.
    mov A, @Temp1                   ; Retrieve pattern
    rl  A                           ; Rotate pattern
    mov @Temp1, A                   ; Store pattern

    jnb ACC.0, dshot_rcpulse_stm_pwm_limit_scale_dithering_done       ; Increment if bit is set

    mov A, Temp2
    add A, #1
    mov Temp2, A
    jnz dshot_rcpulse_stm_pwm_limit_scale_dithering_done

    mov A, Temp3
    addc    A, #0
    mov Temp3, A
    jnb ACC.2, dshot_rcpulse_stm_pwm_limit_scale_dithering_done

    dec Temp3                       ; Reset on overflow
    dec Temp2
    sjmp dshot_rcpulse_stm_pwm_limit_scale_dithering_done

dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm9bit:
    cjne    A, #1, dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm8bit

    ; Check against pwm limit
    clr C
    mov A, Temp3
    subb    A, Temp2                ; Compare against 8-bit rc pulse
    jnc dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm9bit_limited

    ; Limit pwm to 9, 10, 11 bit pwm limit
    mov A, Temp3                    ; Multiply limit by 8 for 11-bit pwm
    mov B, #8
    mul AB
    mov Temp4, A
    mov Temp5, B

dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm9bit_limited:
    ; 9-bit pwm scaling
    mov B, Temp5
    mov A, Temp4
    mov C, B.0
    rrc A
    mov C, B.1
    rrc A
    cpl A
    mov Temp2, A
    mov A, Temp5
    rr  A
    rr  A
    cpl A
    anl A, #1
    mov Temp3, A

    ; 11-bit effective dithering of 9-bit pwm
    jnb Flag_Dithering, dshot_rcpulse_stm_pwm_limit_scale_dithering_done

    mov A, Temp4                    ; 11-bit low byte
    cpl A
    anl A, #((1 SHL (3 - 1)) - 1)   ; Get index [0-3] into dithering pattern table

    ; Multiplying by 2, select pattern [0, 2, 4, 6] on unified dithering pattern table
    rl A

    add A, #Dithering_Patterns
    mov Temp1, A                    ; Reuse DShot pwm pointer since it is not currently in use.
    mov A, @Temp1                   ; Retrieve pattern
    rl  A                           ; Rotate pattern
    mov @Temp1, A                   ; Store pattern

    jnb ACC.0, dshot_rcpulse_stm_pwm_limit_scale_dithering_done       ; Increment if bit is set

    mov A, Temp2
    add A, #1
    mov Temp2, A
    jnz dshot_rcpulse_stm_pwm_limit_scale_dithering_done

    mov A, Temp3
    addc    A, #0
    mov Temp3, A
    jnb ACC.1, dshot_rcpulse_stm_pwm_limit_scale_dithering_done

    dec Temp3                       ; Reset on overflow
    dec Temp2
    sjmp dshot_rcpulse_stm_pwm_limit_scale_dithering_done


dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm8bit:
    ; Check against pwm limit
    clr C
    mov A, Temp3
    subb    A, Temp2                ; Compare against 8-bit rc pulse
    jnc dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm8bit_limited

    ; Limit pwm to 8-bit pwm limit
    mov A, Temp3
    mov Temp2, A

dshot_rcpulse_stm_pwm_limit_scale_dithering_pwm8bit_limited:
    ; 8-bit pwm scaling
    mov A, Temp2                    ; Temp2 already 8-bit
    cpl A
    mov Temp2, A
    mov Temp3, #0

    ; 11-bit effective dithering of 8-bit pwm
    jnb Flag_Dithering, dshot_rcpulse_stm_pwm_limit_scale_dithering_done

    mov A, Temp4                    ; 11-bit low byte
    cpl A
    anl A, #((1 SHL (3 - 0)) - 1)   ; Get index into dithering pattern table

    add A, #Dithering_Patterns
    mov Temp1, A                    ; Reuse DShot pwm pointer since it is not currently in use.
    mov A, @Temp1                   ; Retrieve pattern
    rl  A                           ; Rotate pattern
    mov @Temp1, A                   ; Store pattern

    jnb ACC.0, dshot_rcpulse_stm_pwm_limit_scale_dithering_done       ; Increment if bit is set

    mov A, Temp2
    add A, #1
    mov Temp2, A
    jnz dshot_rcpulse_stm_pwm_limit_scale_dithering_done

	; Reset on overflow
    dec Temp2

dshot_rcpulse_stm_pwm_limit_scale_dithering_done:
    ; Store next state
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_SET_DAMP
    jmp dshot_rcpulse_stm_end



    ; *********** SET DAMP STATE *******************
dshot_rcpulse_stm_set_damp_state:
; Set pwm registers
IF DEADTIME != 0
    ; Substract dead time from normal pwm and store as damping pwm
    ; Damping pwm duty cycle will be higher because numbers are inverted
    clr C
    mov A, Temp2                    ; Skew damping FET timing
IF MCU_TYPE == 0
    subb    A, #((DEADTIME + 1) SHR 1)
ELSE
    subb    A, #(DEADTIME)
ENDIF
    mov Temp4, A
    mov A, Temp3
    subb    A, #0
    mov Temp5, A
    jnc dshot_rcpulse_stm_max_braking_set

    clr A                       ; Set to minimum value
    mov Temp4, A
    mov Temp5, A
    sjmp    dshot_rcpulse_stm_pwm_braking_set      ; Max braking is already zero - branch

dshot_rcpulse_stm_max_braking_set:
    clr C
    mov A, Temp4
    subb    A, Pwm_Braking_L
    mov A, Temp5
    subb    A, Pwm_Braking_H            ; Is braking pwm more than maximum allowed braking?
    jc  dshot_rcpulse_stm_pwm_braking_set      ; Yes - branch
    mov Temp4, Pwm_Braking_L        ; No - set desired braking instead
    mov Temp5, Pwm_Braking_H

ENDIF
dshot_rcpulse_stm_pwm_braking_set:
    ; Store next state
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_SET_PWM
    jmp dshot_rcpulse_stm_end



    ; *********** SET PWM STATE *******************
dshot_rcpulse_stm_set_pwm_state:
    ; Calculate new pwm cycle length
    mov A, #80h
    add A, PwmBitsCount

    ; Check 8 bit PWM cycle length
    cjne A, #80h, dshot_rcpulse_stm_set_pwm_neq_8bits

dshot_rcpulse_stm_set_pwm_eq_8bits:
    ; Update pwm cycle length (8 bits)
    ; Bit7   to 1 = AutoreloadRegisterSelected (apply duty in next pwm cycle)
    ; Bit2:0 to PwmBitsCount
    mov PCA0PWM, A

    ; Set power and damp pwm auto-reload registers
    Set_Power_Pwm_Reg_H Temp2
IF DEADTIME != 0
    Set_Damp_Pwm_Reg_H  Temp4
ENDIF
    sjmp    dshot_rcpulse_stm_set_pwm_end

dshot_rcpulse_stm_set_pwm_neq_8bits:
    ; Update pwm cycle length (9-11 bits)
    mov PCA0PWM, A

    ; Set power and damp pwm auto-reload registers
    Set_Power_Pwm_Reg_L Temp2
    Set_Power_Pwm_Reg_H Temp3
IF DEADTIME != 0
    Set_Damp_Pwm_Reg_L  Temp4
    Set_Damp_Pwm_Reg_H  Temp5
ENDIF

dshot_rcpulse_stm_set_pwm_end:
    ; Store next state
    mov DShot_rcpulse_stm_state, #DSHOT_RCPULSE_STATE_DONE

	; DShot rcpulse has been processed. Timer1 can be deactivated
    clr TCON_TR1                    ; Stop Timer1

	; Capture new frame
    mov Temp1, #0                   ; Set pointer to start
    mov TL0, #0                 	; Reset Timer0
    setb    IE_EX1                  ; Enable Int1 interrupts



    ; *********** END STATE *******************
dshot_rcpulse_stm_end:
    ; Restore preserved registers
    pop B
    pop ACC
    pop PSW
    reti
