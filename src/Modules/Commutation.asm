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
; Commutation
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Commutation routines
;
; Performs commutation switching
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

; Comm phase 1 to comm phase 2
comm1_comm2:                            ; C->A
    jb   Flag_Motor_Dir_Rev, comm1_comm2_rev

    clr  IE_EA
    B_Com_Fet_Off
    A_Com_Fet_On
    Set_Pwm_Phase_C                     ; Reapply power after a demag cut
    setb IE_EA
    Set_Comparator_Phase_B
    ret

comm1_comm2_rev:                        ; A->C
    clr  IE_EA
    B_Com_Fet_Off
    C_Com_Fet_On
    Set_Pwm_Phase_A                     ; Reapply power after a demag cut
    setb IE_EA
    Set_Comparator_Phase_B
    ret

; Comm phase 2 to comm phase 3
comm2_comm3:                            ; B->A
    jb   Flag_Motor_Dir_Rev, comm2_comm3_rev

    clr  IE_EA
    C_Pwm_Fet_Off                       ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_B
    A_Com_Fet_On                        ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb IE_EA
    Set_Comparator_Phase_C
    ret

comm2_comm3_rev:                        ; B->C
    clr  IE_EA
    A_Pwm_Fet_Off                       ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_B
    C_Com_Fet_On                        ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb IE_EA
    Set_Comparator_Phase_A
    ret

; Comm phase 3 to comm phase 4
comm3_comm4:                            ; B->C
    jb   Flag_Motor_Dir_Rev, comm3_comm4_rev

    clr  IE_EA
    A_Com_Fet_Off
    C_Com_Fet_On
    Set_Pwm_Phase_B                     ; Reapply power after a demag cut
    setb IE_EA
    Set_Comparator_Phase_A
    ret

comm3_comm4_rev:                        ; B->A
    clr  IE_EA
    C_Com_Fet_Off
    A_Com_Fet_On
    Set_Pwm_Phase_B                     ; Reapply power after a demag cut
    setb IE_EA
    Set_Comparator_Phase_C
    ret

; Comm phase 4 to comm phase 5
comm4_comm5:                            ; A->C
    jb   Flag_Motor_Dir_Rev, comm4_comm5_rev

    clr  IE_EA
    B_Pwm_Fet_Off                       ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_A
    C_Com_Fet_On                        ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb IE_EA
    Set_Comparator_Phase_B
    ret

comm4_comm5_rev:                        ; C->A
    clr  IE_EA
    B_Pwm_Fet_Off                       ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_C
    A_Com_Fet_On                        ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb IE_EA
    Set_Comparator_Phase_B
    ret

; Comm phase 5 to comm phase 6
comm5_comm6:                            ; A->B
    jb   Flag_Motor_Dir_Rev, comm5_comm6_rev

    clr  IE_EA
    C_Com_Fet_Off
    B_Com_Fet_On
    Set_Pwm_Phase_A                     ; Reapply power after a demag cut
    setb IE_EA
    Set_Comparator_Phase_C
    ret

comm5_comm6_rev:                        ; C->B
    clr  IE_EA
    A_Com_Fet_Off
    B_Com_Fet_On
    Set_Pwm_Phase_C                     ; Reapply power after a demag cut
    setb IE_EA
    Set_Comparator_Phase_A
    ret

; Comm phase 6 to comm phase 1
comm6_comm1:                            ; C->B
    jb   Flag_Motor_Dir_Rev, comm6_comm1_rev

    clr  IE_EA
    A_Pwm_Fet_Off                       ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_C
    B_Com_Fet_On                        ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb IE_EA
    Set_Comparator_Phase_A
    ret

comm6_comm1_rev:                        ; A->B
    clr  IE_EA
    C_Pwm_Fet_Off                       ; Turn off pwm FET (Necessary for EN/PWM driver)
    Set_Pwm_Phase_A
    B_Com_Fet_On                        ; Reapply power after a demag cut (Necessary for EN/PWM driver)
    setb IE_EA
    Set_Comparator_Phase_C
    ret
