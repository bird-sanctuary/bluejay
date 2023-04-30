;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Power control
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Switch power off
;
; Switches all FETs off
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
switch_power_off:
    All_Pwm_Fets_Off                ; Turn off all pwm FETs
    All_Com_Fets_Off                ; Turn off all complementary fets FETs
    Set_All_Pwm_Phases_Off
    ret
