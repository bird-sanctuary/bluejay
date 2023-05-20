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
    All_Com_Fets_Off                ; Turn off all commutation FETs
    Set_All_Pwm_Phases_Off
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Set pwm limit low rpm
;
; Sets power limit for low rpm
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
set_pwm_limit:
    jb  Flag_High_Rpm, set_pwm_limit_high_rpm   ; If high rpm, limit pwm by rpm instead

;set_pwm_limit_low_rpm:
    ; Set pwm limit
    mov Temp1, #0FFh                ; Default full power
    jb  Flag_Startup_Phase, set_pwm_limit_low_rpm_exit  ; Exit if startup phase set

    mov A, Low_Rpm_Pwr_Slope        ; Check if low RPM power protection is enabled
    jz  set_pwm_limit_low_rpm_exit  ; Exit if disabled (zero)

    mov A, Comm_Period4x_H
    jz  set_pwm_limit_low_rpm_exit  ; Avoid divide by zero

    mov A, #255                 ; Divide 255 by Comm_Period4x_H
    jnb Flag_Initial_Run_Phase, ($+5)   ; More protection for initial run phase
    mov A, #127
    mov B, Comm_Period4x_H
    div AB
    mov B, Low_Rpm_Pwr_Slope        ; Multiply by slope
    mul AB
    mov Temp1, A                    ; Set new limit
    xch A, B
    jz  ($+4)                   ; Limit to max

    mov Temp1, #0FFh

    clr C
    mov A, Temp1                    ; Limit to min
    subb    A, Pwm_Limit_Beg
    jnc set_pwm_limit_low_rpm_exit

    mov Temp1, Pwm_Limit_Beg

set_pwm_limit_low_rpm_exit:
    mov Pwm_Limit_By_Rpm, Temp1
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Set pwm limit high rpm
;
; Sets power limit for high rpm
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
set_pwm_limit_high_rpm:
    clr C
    mov A, Comm_Period4x_L
IF MCU_TYPE >= 1
    subb    A, #0A0h                    ; Limit Comm_Period4x to 160, which is ~510k erpm
ELSE
    subb    A, #0E4h                    ; Limit Comm_Period4x to 228, which is ~358k erpm
ENDIF
    mov A, Comm_Period4x_H
    subb    A, #00h

    mov A, Pwm_Limit_By_Rpm
    jnc set_pwm_limit_high_rpm_inc_limit

    dec A
    sjmp    set_pwm_limit_high_rpm_store

set_pwm_limit_high_rpm_inc_limit:
    inc A

set_pwm_limit_high_rpm_store:
    jz  ($+4)
    mov Pwm_Limit_By_Rpm, A

    ret

