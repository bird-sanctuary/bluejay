;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Bluejay digital ESC firmware for controlling brushless motors in multirotors
;
; Copyleft  2023 Chris Landa
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
; Codespace segment definitions for different MCU types
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

    ; General
    CSEG_APP EQU 80h

IF MCU_TYPE == MCU_BB51
    ; BB51
    CSEG_RESET EQU 2FFDh
    CSEG_EEPROM EQU 3000h
    CSEG_LAYOUT_TAG EQU 3040h
    CSEG_MCU_TAG EQU 3050h
    CSEG_NAME EQU 3060h
    CSEG_MELODY EQU 3070h
    CSEG_BOOT_START EQU 0F000h
ELSE
    ; BB1 & BB21
    CSEG_RESET EQU 19FDh
    CSEG_EEPROM EQU 1A00h
    CSEG_LAYOUT_TAG EQU 1A40h
    CSEG_MCU_TAG EQU 1A50h
    CSEG_NAME EQU 1A60h
    CSEG_MELODY EQU 1A70h
    CSEG_BOOT_START EQU 1C00h
ENDIF
