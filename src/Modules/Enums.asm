;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Bluejay digital ESC firmware for controlling brushless motors in multirotors
;
; Copyleft 2023 Chris Landa
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
; Enums
;
; Enumerations to make code more readable
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; MCU Types
;**** **** **** **** **** **** **** **** **** **** **** **** ****
    MCU_BB51 EQU 2
    MCU_BB2 EQU 1

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; PWM frequency and resolution
;**** **** **** **** **** **** **** **** **** **** **** **** ****

    ; Frequency
    PWM_96 EQU 2
    PWM_48 EQU 1
    PWM_24 EQU 0

    ; Resolution
    PWM_11_BIT EQU 3
    PWM_10_BIT EQU 2
    PWM_9_BIT EQU 1
    PWM_8_BIT EQU 0

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; DSHOT Commands
;**** **** **** **** **** **** **** **** **** **** **** **** ****
    CMD_DIRECTION_USER_REVERSE EQU 21
    CMD_DIRECTION_USER_NORMAL EQU 20
    CMD_EXTENDED_TELEMETRY_DISABLE EQU 14
    CMD_EXTENDED_TELEMETRY_ENABLE EQU 13
    CMD_SAVE_SETTINGS EQU 12
    CMD_BIDIR_ON EQU 10
    CMD_BIDIR_OFF EQU 9
    CMD_DIRECTION_REVERSE EQU 8
    CMD_DIRECTION_NORMAL EQU 7
    CMD_ESC_INFO EQU 6
    CMD_BEEP_5 EQU 5
    CMD_BEEP_4 EQU 4
    CMD_BEEP_3 EQU 3
    CMD_BEEP_2 EQU 2
    CMD_BEEP_1 EQU 1
