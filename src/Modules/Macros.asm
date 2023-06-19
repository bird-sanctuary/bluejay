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
; Macros
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

DSHOT_TLM_CLOCK EQU 24500000            ; 24.5MHz
DSHOT_TLM_START_DELAY EQU -(5 * 25 / 4) ; Start telemetry after 5 us (~30 us after receiving DShot cmd)
IF MCU_TYPE == MCU_BB1
    DSHOT_TLM_PREDELAY EQU 9            ; 9 Timer0 ticks inherent delay
ELSE
    DSHOT_TLM_PREDELAY EQU 7            ; 7 Timer0 ticks inherent delay
ENDIF

IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    DSHOT_TLM_CLOCK_48 EQU 49000000     ; 49MHz
    DSHOT_TLM_START_DELAY_48 EQU -(16 * 49 / 4) ; Start telemetry after 16 us (~30 us after receiving DShot cmd)
    DSHOT_TLM_PREDELAY_48 EQU 11        ; 11 Timer0 ticks inherent delay
ENDIF

Set_DShot_Tlm_Bitrate MACRO rate
    mov  DShot_GCR_Pulse_Time_1, #(DSHOT_TLM_PREDELAY - (1 * DSHOT_TLM_CLOCK / 4 / rate))
    mov  DShot_GCR_Pulse_Time_2, #(DSHOT_TLM_PREDELAY - (2 * DSHOT_TLM_CLOCK / 4 / rate))
    mov  DShot_GCR_Pulse_Time_3, #(DSHOT_TLM_PREDELAY - (3 * DSHOT_TLM_CLOCK / 4 / rate))

    mov  DShot_GCR_Start_Delay, #DSHOT_TLM_START_DELAY

IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    mov  DShot_GCR_Pulse_Time_1_Tmp, #(DSHOT_TLM_PREDELAY_48 - (1 * DSHOT_TLM_CLOCK_48 / 4 / rate))
    mov  DShot_GCR_Pulse_Time_2_Tmp, #(DSHOT_TLM_PREDELAY_48 - (2 * DSHOT_TLM_CLOCK_48 / 4 / rate))
    mov  DShot_GCR_Pulse_Time_3_Tmp, #(DSHOT_TLM_PREDELAY_48 - (3 * DSHOT_TLM_CLOCK_48 / 4 / rate))
ENDIF
ENDM

; DShot GCR encoding, adjust time by adding to previous item
GCR_Add_Time MACRO reg
    mov  B, @reg
    mov  A, DShot_GCR_Pulse_Time_2
    cjne A, B, ($+5)
    mov  A, DShot_GCR_Pulse_Time_3
    mov  @reg, A
ENDM

; Prepare telemetry packet while waiting for Timer3 to wrap
Wait_For_Timer3 MACRO
    LOCAL wait_for_t3 done_waiting
    jb   Flag_Telemetry_Pending, wait_for_t3

    jnb  Flag_Timer3_Pending, done_waiting
    call dshot_tlm_create_packet

wait_for_t3:
    jnb  Flag_Timer3_Pending, done_waiting
    sjmp wait_for_t3

done_waiting:
ENDM

; Used for subdividing the DShot telemetry routine into chunks,
; that will return if Timer3 has wrapped
Early_Return_Packet_Stage MACRO num
    Early_Return_Packet_Stage_ num, %(num + 1)
ENDM

Early_Return_Packet_Stage_ MACRO num next
IF num > 0
    inc  Temp7                          ; Increment current packet stage
    jb   Flag_Timer3_Pending, dshot_packet_stage_&num ; Return early if Timer3 has wrapped
    pop  PSW
    ret
dshot_packet_stage_&num:
ENDIF
IF num < 5
    cjne Temp7, #(num), dshot_packet_stage_&next ; If this is not current stage,skip to next
ENDIF
ENDM

Decode_DShot_2Bit MACRO dest,decode_fail
    movx A, @Temp1
    mov  Temp7, A
    clr  C
    subb A, Temp6                       ; Subtract previous timestamp
    clr  C
    subb A, Temp2
    jc   decode_fail                    ; Check that bit is longer than minimum

    subb A, Temp2                       ; Check if bit is zero or one
    rlca dest                           ; Shift bit into data byte
    inc  Temp1                          ; Next bit

    movx A, @Temp1
    mov  Temp6, A
    clr  C
    subb A, Temp7
    clr  C
    subb A, Temp2
    jc   decode_fail

    subb A, Temp2
    rlca dest
    inc  Temp1
ENDM

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Compound instructions for convenience
;**** **** **** **** **** **** **** **** **** **** **** **** ****
xcha MACRO var1,var2                    ; Exchange via accumulator
    mov  A, var1
    xch  A, var2
    mov  var1, A
ENDM

rrca MACRO var                          ; Rotate right through carry via accumulator
    mov  A, var
    rrc  A
    mov  var, A
ENDM

rlca MACRO var                          ; Rotate left through carry via accumulator
    mov  A, var
    rlc  A
    mov  var, A
ENDM

rla MACRO var                           ; Rotate left via accumulator
    mov  A, var
    rl   A
    mov  var, A
ENDM

ljc MACRO label                         ; Long jump if carry set
    LOCAL skip
    jnc  skip
    jmp  label
skip:
ENDM

ljz MACRO label                         ; Long jump if accumulator is zero
    LOCAL skip
    jnz  skip
    jmp  label
skip:
ENDM

imov MACRO reg,val                      ; Increment pointer register and move
    inc  reg
    mov  @reg, val                      ; Write value to memory address pointed to by register
ENDM

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Division
;
; ih, il: input (hi byte, lo byte)
; oh, ol: output (hi byte, lo byte)
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
Divide_By_16 MACRO ih,il,oh,ol
    mov  A, ih
    swap A
    mov  ol, A
    anl  A, #00Fh
    mov  oh, A
    mov  A, ol
    anl  A, #0F0h
    mov  ol, A
    mov  A, il
    swap A
    anl  A, #00Fh
    orl  A, ol
    mov  ol, A
ENDM

Divide_12Bit_By_16 MACRO ih,il,ol       ; Only if ih < 16
    mov  A, ih
    swap A
    mov  ol, A
    mov  A, il
    swap A
    anl  A, #00Fh
    orl  A, ol
    mov  ol, A
ENDM

Divide_By_8 MACRO ih,il,oh,ol
    mov  A, ih
    swap A
    rl   A
    mov  ol, A
    anl  A, #01Fh
    mov  oh, A
    mov  A, ol
    anl  A, #0E0h
    mov  ol, A
    mov  A, il
    swap A
    rl   A
    anl  A, #01Fh
    orl  A, ol
    mov  ol, A
ENDM

Divide_11Bit_By_8 MACRO ih,il,ol        ; Only if ih < 8
    mov  A, ih
    swap A
    rl   A
    mov  ol, A
    mov  A, il
    swap A
    rl   A
    anl  A, #01Fh
    orl  A, ol
    mov  ol, A
ENDM

Divide_By_4 MACRO ih,il,oh,ol
    clr  C
    mov  A, ih
    rrc  A
    mov  oh, A
    mov  A, il
    rrc  A
    mov  ol, A

    clr  C
    mov  A, oh
    rrc  A
    mov  oh, A
    mov  A, ol
    rrc  A
    mov  ol, A
ENDM

Divide_16Bit_By_2 MACRO hi, lo
    clr  C
    rrca hi
    rrca lo
ENDM
