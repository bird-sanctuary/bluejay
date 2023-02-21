;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Commutation routines
;
; Performs commutation switching
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Comm phase 1 to comm phase 2
comm1_comm2:                        ; C->A
    jb  Flag_Motor_Dir_Rev, comm1_comm2_rev

    clr IE_EA
    B_Com_Fet_Off
    A_Com_Fet_On
    Set_Pwm_Phase_C             ; Reapply power after a demag cut
    setb    IE_EA
    Set_Comparator_Phase_B
    ret

comm1_comm2_rev:                    ; A->C
    clr IE_EA
    B_Com_Fet_Off
    C_Com_Fet_On
    Set_Pwm_Phase_A             ; Reapply power after a demag cut
    setb    IE_EA
    Set_Comparator_Phase_B
    ret

; Comm phase 2 to comm phase 3
comm2_comm3:                        ; B->A
    jb  Flag_Motor_Dir_Rev, comm2_comm3_rev

    clr IE_EA
    C_Pwm_Fet_Off                   ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_B
    A_Com_Fet_On                    ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb    IE_EA
    Set_Comparator_Phase_C
    ret

comm2_comm3_rev:                    ; B->C
    clr IE_EA
    A_Pwm_Fet_Off                   ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_B
    C_Com_Fet_On                    ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb    IE_EA
    Set_Comparator_Phase_A
    ret

; Comm phase 3 to comm phase 4
comm3_comm4:                        ; B->C
    jb  Flag_Motor_Dir_Rev, comm3_comm4_rev

    clr IE_EA
    A_Com_Fet_Off
    C_Com_Fet_On
    Set_Pwm_Phase_B             ; Reapply power after a demag cut
    setb    IE_EA
    Set_Comparator_Phase_A
    ret

comm3_comm4_rev:                    ; B->A
    clr IE_EA
    C_Com_Fet_Off
    A_Com_Fet_On
    Set_Pwm_Phase_B             ; Reapply power after a demag cut
    setb    IE_EA
    Set_Comparator_Phase_C
    ret

; Comm phase 4 to comm phase 5
comm4_comm5:                        ; A->C
    jb  Flag_Motor_Dir_Rev, comm4_comm5_rev

    clr IE_EA
    B_Pwm_Fet_Off                   ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_A
    C_Com_Fet_On                    ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb    IE_EA
    Set_Comparator_Phase_B
    ret

comm4_comm5_rev:                    ; C->A
    clr IE_EA
    B_Pwm_Fet_Off                   ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_C
    A_Com_Fet_On                    ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb    IE_EA
    Set_Comparator_Phase_B
    ret

; Comm phase 5 to comm phase 6
comm5_comm6:                        ; A->B
    jb  Flag_Motor_Dir_Rev, comm5_comm6_rev

    clr IE_EA
    C_Com_Fet_Off
    B_Com_Fet_On
    Set_Pwm_Phase_A             ; Reapply power after a demag cut
    setb    IE_EA
    Set_Comparator_Phase_C
    ret

comm5_comm6_rev:                    ; C->B
    clr IE_EA
    A_Com_Fet_Off
    B_Com_Fet_On
    Set_Pwm_Phase_C             ; Reapply power after a demag cut
    setb    IE_EA
    Set_Comparator_Phase_A
    ret

; Comm phase 6 to comm phase 1
comm6_comm1:                        ; C->B
    jb  Flag_Motor_Dir_Rev, comm6_comm1_rev

    clr IE_EA
    A_Pwm_Fet_Off                   ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_C
    B_Com_Fet_On                    ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb    IE_EA
    Set_Comparator_Phase_A
    ret

comm6_comm1_rev:                    ; A->B
    clr IE_EA
    C_Pwm_Fet_Off                   ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_A
    B_Com_Fet_On                    ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb    IE_EA
    Set_Comparator_Phase_C
    ret
