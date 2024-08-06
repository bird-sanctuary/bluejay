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
; Common definitions for EFM8BB1x/2x/5x based ESCs
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Device SiLabs EFM8BB1x/2x/51
;
; Include defines provided by SiLabs depending on target platform.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
IF MCU_TYPE == MCU_BB2
    $include (Silabs/SI_EFM8BB2_Defs.inc)
ELSEIF MCU_TYPE == MCU_BB51
    $include (Silabs/SI_EFM8BB51_Defs.inc)
ENDIF

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Uses internal calibrated oscillator set to 24/48Mhz
;**** **** **** **** **** **** **** **** **** **** **** **** ****


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; ESC target letter(s)
;
; The initial set of layouts are labeled A-Z and their character can be
; calculated based on that.
;
; The extended set of layouts consisting of two letters will assign the letters
; manually for maximum flexibility.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
IF ESCNO < 27
    ESC_C_COUNT EQU 1
    ESC_C EQU "A" + ESCNO - 1
ELSE
    ESC_C_COUNT EQU 2
ENDIF

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; ESC selection statements
;**** **** **** **** **** **** **** **** **** **** **** **** ****
IF MCU_TYPE = MCU_BB2
IF ESCNO == A_
    $include (Layouts/A.inc)            ; Select pinout A
ELSEIF ESCNO == B_
    $include (Layouts/B.inc)            ; Select pinout B
ELSEIF ESCNO == C_
    $include (Layouts/C.inc)            ; Select pinout C
ELSEIF ESCNO == D_
    $include (Layouts/D.inc)            ; Select pinout D
ELSEIF ESCNO == E_
    $include (Layouts/E.inc)            ; Select pinout E
ELSEIF ESCNO == F_
    $include (Layouts/F.inc)            ; Select pinout F
ELSEIF ESCNO == G_
    $include (Layouts/G.inc)            ; Select pinout G
ELSEIF ESCNO == H_
    $include (Layouts/H.inc)            ; Select pinout H
ELSEIF ESCNO == I_
    $include (Layouts/I.inc)            ; Select pinout I
ELSEIF ESCNO == J_
    $include (Layouts/J.inc)            ; Select pinout J
ELSEIF ESCNO == K_
    $include (Layouts/K.inc)            ; Select pinout K
ELSEIF ESCNO == L_
    $include (Layouts/L.inc)            ; Select pinout L
ELSEIF ESCNO == M_
    $include (Layouts/M.inc)            ; Select pinout M
ELSEIF ESCNO == N_
    $include (Layouts/N.inc)            ; Select pinout N
ELSEIF ESCNO == O_
    $include (Layouts/O.inc)            ; Select pinout O
ELSEIF ESCNO == P_
    $include (Layouts/P.inc)            ; Select pinout P
ELSEIF ESCNO == Q_
    $include (Layouts/Q.inc)            ; Select pinout Q
ELSEIF ESCNO == R_
    $include (Layouts/R.inc)            ; Select pinout R
ELSEIF ESCNO == S_
    $include (Layouts/S.inc)            ; Select pinout S
ELSEIF ESCNO == T_
    $include (Layouts/T.inc)            ; Select pinout T
ELSEIF ESCNO == U_
    $include (Layouts/U.inc)            ; Select pinout U
ELSEIF ESCNO == V_
    $include (Layouts/V.inc)            ; Select pinout V
ELSEIF ESCNO == W_
    $include (Layouts/W.inc)            ; Select pinout W
;ELSEIF ESCNO == X_
    ;$include (Layouts/X.inc)           ; Select pinout X
;ELSEIF ESCNO == Y_
    ;$include (Layouts/Y.inc)           ; Select pinout Y
ELSEIF ESCNO == Z_
    $include (Layouts/Z.inc)            ; Select pinout Z
ELSEIF ESCNO == OA_
    $include (Layouts/OA.inc)           ; Select pinout OA
    ESC_C0 EQU "O"
    ESC_C1 EQU "A"
ENDIF
ENDIF

IF MCU_TYPE == MCU_BB51
IF ESCNO == A_
    $include (Layouts/BB51/A.inc)       ; Select pinout A
ELSEIF ESCNO == B_
    $include (Layouts/BB51/B.inc)       ; Select pinout B
ELSEIF ESCNO == C_
    $include (Layouts/BB51/C.inc)       ; Select pinout C
ELSEIF ESCNO == D_
	$include (Layouts/BB51/D.inc)       ; Select pinout D
ELSEIF ESCNO == E_
	$include (Layouts/BB51/E.inc)		; Select pinout E
ENDIF
ENDIF

; Build device signature based on target platform: 0xE8, [0xB1 | 0xB2 | 0xB5]
SIGNATURE_001 EQU 0E8h
IF MCU_TYPE == MCU_BB2
    SIGNATURE_002 EQU 0B2h
ELSEIF MCU_TYPE == MCU_BB51
    SIGNATURE_002 EQU 0B5h
ENDIF

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Constant definitions
;**** **** **** **** **** **** **** **** **** **** **** **** ****

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; MCU letter
;
; BB21: H
; BB51: X
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
IF MCU_TYPE == MCU_BB2
    MCU_C EQU "H"
ELSEIF MCU_TYPE == MCU_BB51
    MCU_C EQU "X"
ENDIF

; Dead time number as chars
DT_C2 EQU "0" + (DEADTIME / 100)
DT_C1 EQU "0" + ((DEADTIME / 10) MOD 10)
DT_C0 EQU "0" + (DEADTIME MOD 10)

; Full ESC layout tag including layout letter, mcu letter and deadtime
CSEG AT CSEG_LAYOUT_TAG
IF ESC_C_COUNT == 1
; Eg.: G_H_30, O_L_5,...
IF DEADTIME < 100
    Eep_ESC_Layout: DB "#", ESC_C, "_", MCU_C, "_", DT_C1, DT_C0, "#        "
ELSE
    Eep_ESC_Layout: DB "#", ESC_C, "_", MCU_C, "_", DT_C2, DT_C1, DT_C0, "#       "
ENDIF
ELSEIF ESC_C_COUNT == 2
; Eg.: AA_H_30, AO_L_5,...
IF DEADTIME < 100
    Eep_ESC_Layout: DB "#", ESC_C0, ESC_C1, "_", MCU_C, "_", DT_C1, DT_C0, "#       "
ELSE
    Eep_ESC_Layout: DB "#", ESC_C0, ESC_C1, "_", MCU_C, "_", DT_C2, DT_C1, DT_C0, "#      "
ENDIF
ENDIF

; Project and MCU tag (16 Bytes)
CSEG AT CSEG_MCU_TAG
IF MCU_TYPE == MCU_BB2
    Eep_ESC_MCU: DB "#BLHELI$EFM8B21#"
ELSEIF MCU_TYPE == MCU_BB51
    Eep_ESC_MCU: DB "#BLHELI$EFM8B51#"
ENDIF

Interrupt_Table_Definition MACRO
CSEG AT 0                               ; Code segment start
    jmp  reset
CSEG AT 03h                             ; Int0 interrupt
    jmp  int0_int
CSEG AT 0Bh                             ; Timer0 overflow interrupt
    jmp  t0_int
CSEG AT 13h                             ; Int1 interrupt
    jmp  int1_int
CSEG AT 1Bh                             ; Timer1 overflow interrupt
    jmp  t1_int
CSEG AT 2Bh                             ; Timer2 overflow interrupt
    jmp  t2_int
CSEG AT 5Bh                             ; PCA interrupt
    jmp  pca_int
CSEG AT 73h                             ; Timer3 overflow/compare interrupt
    jmp  t3_int
ENDM

Initialize_PCA MACRO
    mov  PCA0CN0, #40h                  ; PCA enabled
    mov  PCA0MD, #08h                   ; PCA clock is system clock

    mov  PCA0PWM, #(80h + PWM_BITS_H)   ; Enable PCA auto-reload registers and set pwm cycle length (8-11 bits)

IF PWM_CENTERED == 1
    mov  PCA0CENT, #07h                 ; Center aligned pwm
ELSE
    mov  PCA0CENT, #00h                 ; Edge aligned pwm
ENDIF
ENDM

Set_MCU_Clk_24MHz MACRO
    mov  CLKSEL, #13h                   ; Set clock to 24MHz (Oscillator 1 divided by 2)

    mov  SFRPAGE, #10h
    mov  PFE0CN, #00h                   ; Set flash timing for 24MHz and disable prefetch engine
    mov  SFRPAGE, #00h
ENDM

Set_MCU_Clk_48MHz MACRO
    mov  SFRPAGE, #10h
IF MCU_TYPE == MCU_BB2
    mov  PFE0CN, #30h                   ; Set flash timing for 48MHz and enable prefetch engine
ELSEIF MCU_TYPE == MCU_BB51
    mov  PFE0CN, #10h                   ; Set flash timing for 48MHz
ENDIF
    mov  SFRPAGE, #00h

    mov  CLKSEL, #03h                   ; Set clock to 48MHz (Oscillator 1)
ENDM

Unlock_Flash MACRO
    mov  Flash_Key_1, #0A5h
    mov  Flash_Key_2, #0F1h
ENDM

Lock_Flash MACRO
    mov  Flash_Key_1, #0
    mov  Flash_Key_2, #0
ENDM

