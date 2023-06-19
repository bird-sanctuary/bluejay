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
; ESC programming (EEPROM emulation)
;
; The BB EFM8 technically does not have a dedicated EEPROM but in Bluejay a
; part of the flash space is dedicated to emulate an EEPROM. This is the space
; that holds all the settings and is what the configurator reads/writes ( via
; the bootloader).
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

ESC_LAYOUT_SIZE         EQU 48
MELODY_SIZE             EQU 140


;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Read all "EEPROM" parameters
;**** **** **** **** **** **** **** **** **** **** **** **** ****
read_all_eeprom_parameters:
    ; Check initialized signature
    mov  DPTR, #Eep_Initialized_L
    mov  Temp1, #Bit_Access
    call read_eeprom_byte
    mov  A, Bit_Access
    cjne A, #055h, read_eeprom_store_defaults
    inc  DPTR                           ; Now Eep_Initialized_H
    call read_eeprom_byte
    mov  A, Bit_Access
    cjne A, #0AAh, read_eeprom_store_defaults
    sjmp read_eeprom_read

read_eeprom_store_defaults:
    Unlock_Flash
    call set_default_parameters
    call erase_and_store_all_in_eeprom
    Lock_Flash
    sjmp read_eeprom_exit

read_eeprom_read:
    ; Read "EEPROM"
    mov  DPTR, #_Eep_Pgm_Gov_P_Gain
    mov  Temp1, #_Pgm_Gov_P_Gain
    mov  Temp4, #10                     ; 10 parameters

read_eeprom_block1:
    call read_eeprom_byte
    inc  DPTR
    inc  Temp1
    djnz Temp4, read_eeprom_block1

    ; Read "EEPROM" after Eep_Initialized_x flags
    ; Temp4 = EEPROM_B2_PARAMETERS_COUNT parameters: [_Eep_Enable_TX_Program - Eep_Pgm_Power_Rating]
    mov  DPTR, #_Eep_Enable_TX_Program
    mov  Temp1, #_Pgm_Enable_TX_Program
    mov  Temp4, #EEPROM_B2_PARAMETERS_COUNT

read_eeprom_block2:
    call read_eeprom_byte
    inc  DPTR
    inc  Temp1
    djnz Temp4, read_eeprom_block2

    ; Set pointer to uncritical area
    mov  DPTR, #Eep_Dummy

read_eeprom_exit:
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Erase flash and store all parameter values in "EEPROM"
;**** **** **** **** **** **** **** **** **** **** **** **** ****
erase_and_store_all_in_eeprom:
    clr  IE_EA                          ; Disable interrupts
    call read_esc_layout
    call read_melody
    call erase_flash

    ; Store firmware main revision
    mov  DPTR, #Eep_FW_Main_Revision
    mov  A, #EEPROM_FW_MAIN_REVISION
    call write_eeprom_byte_from_acc

    ; Store firmware sub revision
    inc  DPTR
    mov  A, #EEPROM_FW_SUB_REVISION
    call write_eeprom_byte_from_acc

    ; Store layout revision
    inc  DPTR
    mov  A, #EEPROM_LAYOUT_REVISION
    call write_eeprom_byte_from_acc

    ; Write eeprom before Eep_Initialized_x flags
    ; Temp4 = 10 parameters [_Eep_Pgm_Gov_P_Gain - Eep_Initialized_x]
    mov  DPTR, #_Eep_Pgm_Gov_P_Gain
    mov  Temp1, #_Pgm_Gov_P_Gain
    mov  Temp4, #10

write_eeprom_block1:
    call write_eeprom_byte
    inc  DPTR
    inc  Temp1
    djnz Temp4, write_eeprom_block1

    ; Write eeprom after Eep_Initialized_x flags
    ; Temp4 = EEPROM_B2_PARAMETERS_COUNT parameters: [_Eep_Enable_TX_Program - Eep_Pgm_Power_Rating]
    mov  DPTR, #_Eep_Enable_TX_Program
    mov  Temp1, #_Pgm_Enable_TX_Program
    mov  Temp4, #EEPROM_B2_PARAMETERS_COUNT

write_eeprom_block2:
    call write_eeprom_byte
    inc  DPTR
    inc  Temp1
    djnz Temp4, write_eeprom_block2

    ; Now write tags, melogy and signature
    call write_esc_layout
    call write_melody
    call write_eeprom_signature

    ; Set pointer to uncritical area
    mov  DPTR, #Eep_Dummy

    ; Allow the flash controller to settle data down
    call wait200ms
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Read eeprom byte
;
; ASSERT:
; - Target address in DPTR
; - Destination address in Temp1
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
read_eeprom_byte:
    clr  A
    movc A, @A+DPTR                     ; Read from flash
    mov  @Temp1, A
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Write eeprom byte
;
; ASSERT:
; - Data in address given by Temp1
; - Destination address in DPTR
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
write_eeprom_byte:
    mov  A, @Temp1

; Shorthand if data is already in accumulator
write_eeprom_byte_from_acc:
    orl  PSCTL, #01h                    ; Set the PSWE bit
    anl  PSCTL, #0FDh                   ; Clear the PSEE bit
    mov  Temp8, A
    clr  C
    mov  A, DPH                         ; Check that address is not in bootloader area
    subb A, #BOOTLOADER_OFFSET
    jc   ($+3)

    ret

    mov  A, Temp8

    ; Attempt to unlock flash
    mov  FLKEY, Flash_Key_1             ; First key code
    mov  FLKEY, Flash_Key_2             ; Second key code

    movx @DPTR, A                       ; Write to flash
    anl  PSCTL, #0FEh                   ; Clear the PSWE bit
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Erase flash (erases the flash segment used for "eeprom" variables)
;**** **** **** **** **** **** **** **** **** **** **** **** ****
erase_flash:
    orl  PSCTL, #02h                    ; Set the PSEE bit
    orl  PSCTL, #01h                    ; Set the PSWE bit

    ; Attempt to unlock flash
    mov  FLKEY, Flash_Key_1             ; First key code
    mov  FLKEY, Flash_Key_2             ; Second key code

    mov  DPTR, #Eep_Initialized_L
    movx @DPTR, A
    anl  PSCTL, #0FCh                   ; Clear the PSEE and PSWE bits
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Write eeprom signature
;**** **** **** **** **** **** **** **** **** **** **** **** ****
write_eeprom_signature:
    mov  DPTR, #Eep_Initialized_L
    mov  A, #055h
    call write_eeprom_byte_from_acc

    mov  DPTR, #Eep_Initialized_H
    mov  A, #0AAh
    call write_eeprom_byte_from_acc
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Read esc layout bytes from flash and store in temporary storage
;**** **** **** **** **** **** **** **** **** **** **** **** ****
read_esc_layout:
    mov  Temp3, #ESC_LAYOUT_SIZE        ; Number of esc layout bytes
    mov  Temp2, #Temp_Storage           ; Set RAM address
    mov  Temp1, #Bit_Access
    mov  DPTR, #Eep_ESC_Layout          ; Set flash address
read_esc_layout_byte:
    call read_eeprom_byte
    mov  A, Bit_Access
    mov  @Temp2, A                      ; Write to RAM
    inc  Temp2
    inc  DPTR
    djnz Temp3, read_esc_layout_byte
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Write all esc layout bytes from temporary storage and
; store them in flash
;**** **** **** **** **** **** **** **** **** **** **** **** ****
write_esc_layout:
    mov  Temp3, #ESC_LAYOUT_SIZE        ; Number of esc layout bytes
    mov  Temp2, #Temp_Storage           ; Set RAM address
    mov  DPTR, #Eep_ESC_Layout          ; Set flash address
write_esc_layout_byte:
    mov  A, @Temp2                      ; Read from RAM
    call write_eeprom_byte_from_acc
    inc  Temp2
    inc  DPTR
    djnz Temp3, write_esc_layout_byte
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Melody
;**** **** **** **** **** **** **** **** **** **** **** **** ****

; Read 140  bytes from "EEPROM" and store in external memory (XRAM)
read_melody:
    mov  Temp3, #MELODY_SIZE            ; Number of bytes
    mov  Temp2, #0                      ; Set XRAM address
    mov  Temp1, #Bit_Access
    mov  DPTR, #Eep_Pgm_Beep_Melody     ; Set flash address
read_melody_byte:
    call read_eeprom_byte
    mov  A, Bit_Access
    movx @Temp2, A                      ; Write to XRAM
    inc  Temp2
    inc  DPTR
    djnz Temp3, read_melody_byte
    ret

; Read 140 bytes from external memory (XRAM) and store them in "EEPROM"
write_melody:
    mov  Temp3, #MELODY_SIZE            ; Number of bytes
    mov  Temp2, #0                      ; Set XRAM address
    mov  DPTR, #Eep_Pgm_Beep_Melody     ; Set flash address
write_melody_byte:
    movx A, @Temp2                      ; Read from XRAM
    call write_eeprom_byte_from_acc
    inc  Temp2
    inc  DPTR
    djnz Temp3, write_melody_byte
    ret
