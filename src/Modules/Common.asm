;**** **** **** **** ****
;
; Bluejay digital ESC firmware for controlling brushless motors in multirotors
;
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
;**** **** **** **** ****
;
; Common definitions for EFM8BB1x/2x based ESCs
;
;**** **** **** **** ****

;*********************
; Device SiLabs EFM8BB1x/2x/51
;*********************
IF MCU_TYPE == 0
	$include (Silabs/SI_EFM8BB1_Defs.inc)
ELSEIF MCU_TYPE == 1
	$include (Silabs/SI_EFM8BB2_Defs.inc)
ELSEIF MCU_TYPE == 2
	$include (Silabs/SI_EFM8BB51_Defs.inc)
ENDIF

;**** **** **** **** ****
; Uses internal calibrated oscillator set to 24/48Mhz
;**** **** **** **** ****

;**** **** **** **** ****
; ESC selection statements
IF MCU_TYPE < 2
	IF ESCNO == A_
	$include (Layouts/A.inc)				; Select pinout A
	ELSEIF ESCNO == B_
	$include (Layouts/B.inc)				; Select pinout B
	ELSEIF ESCNO == C_
	$include (Layouts/C.inc)				; Select pinout C
	ELSEIF ESCNO == D_
	$include (Layouts/D.inc)				; Select pinout D
	ELSEIF ESCNO == E_
	$include (Layouts/E.inc)				; Select pinout E
	ELSEIF ESCNO == F_
	$include (Layouts/F.inc)				; Select pinout F
	ELSEIF ESCNO == G_
	$include (Layouts/G.inc)				; Select pinout G
	ELSEIF ESCNO == H_
	$include (Layouts/H.inc)				; Select pinout H
	ELSEIF ESCNO == I_
	$include (Layouts/I.inc)				; Select pinout I
	ELSEIF ESCNO == J_
	$include (Layouts/J.inc)				; Select pinout J
	ELSEIF ESCNO == K_
	$include (Layouts/K.inc)				; Select pinout K
	ELSEIF ESCNO == L_
	$include (Layouts/L.inc)				; Select pinout L
	ELSEIF ESCNO == M_
	$include (Layouts/M.inc)				; Select pinout M
	ELSEIF ESCNO == N_
	$include (Layouts/N.inc)				; Select pinout N
	ELSEIF ESCNO == O_
	$include (Layouts/O.inc)				; Select pinout O
	ELSEIF ESCNO == P_
	$include (Layouts/P.inc)				; Select pinout P
	ELSEIF ESCNO == Q_
	$include (Layouts/Q.inc)				; Select pinout Q
	ELSEIF ESCNO == R_
	$include (Layouts/R.inc)				; Select pinout R
	ELSEIF ESCNO == S_
	$include (Layouts/S.inc)				; Select pinout S
	ELSEIF ESCNO == T_
	$include (Layouts/T.inc)				; Select pinout T
	ELSEIF ESCNO == U_
	$include (Layouts/U.inc)				; Select pinout U
	ELSEIF ESCNO == V_
	$include (Layouts/V.inc)				; Select pinout V
	ELSEIF ESCNO == W_
	$include (Layouts/W.inc)				; Select pinout W
	;ELSEIF ESCNO == X_
	;$include (Layouts/X.inc)			; Select pinout X
	;ELSEIF ESCNO == Y_
	;$include (Layouts/Y.inc)			; Select pinout Y
	ELSEIF ESCNO == Z_
	$include (Layouts/Z.inc)				; Select pinout Z
	ENDIF
ENDIF

IF MCU_TYPE == 2
	IF ESCNO == A_
	$include (Layouts/BB51/A.inc)			; Select pinout A
	ELSEIF ESCNO == B_
	$include (Layouts/BB51/B.inc)			; Select pinout B
	ELSEIF ESCNO == C_
	$include (Layouts/BB51/C.inc)			; Select pinout C
	ENDIF
ENDIF

SIGNATURE_001			EQU	0E8h		; Device signature
IF MCU_TYPE == 0
	SIGNATURE_002			EQU	0B1h
ELSEIF MCU_TYPE == 1
	SIGNATURE_002			EQU	0B2h
ELSEIF MCU_TYPE == 2
	SIGNATURE_002			EQU	0B5h
ENDIF

;**** **** **** **** ****
; Constant definitions
;**** **** **** **** ****
ESC_C	EQU	"A" + ESCNO - 1		; ESC target letter

; MCU letter (24Mhz=L, 48Mhz=H, BB51=X)
IF MCU_TYPE == 0
	MCU_C	EQU	"L"
ELSEIF MCU_TYPE == 1
	MCU_C	EQU	"H"
ELSEIF MCU_TYPE == 2
	MCU_C	EQU	"X"
ENDIF
ENDIF

; Dead time number as chars
DT_C2	EQU	"0" + (DEADTIME / 100)
DT_C1	EQU	"0" + ((DEADTIME / 10) MOD 10)
DT_C0	EQU	"0" + (DEADTIME MOD 10)

; ESC layout tag
IF MCU_TYPE < 2
	CSEG AT 1A40h
ELSEIF MCU_TYPE == 2
	CSEG AT 3040h
ENDIF

IF DEADTIME < 100
Eep_ESC_Layout:	DB	"#", ESC_C, "_", MCU_C, "_", DT_C1, DT_C0, "#        "
ELSE
Eep_ESC_Layout:	DB	"#", ESC_C, "_", MCU_C, "_", DT_C2, DT_C1, DT_C0, "#       "
ENDIF

IF MCU_TYPE < 2
	CSEG AT 1A50h
ELSEIF MCU_TYPE == 2
	CSEG AT 3050h
ENDIF

; Project and MCU tag (16 Bytes)
IF MCU_TYPE == 0
	Eep_ESC_MCU:	DB	"#BLHELI$EFM8B10#"
ELSEIF MCU_TYPE == 1
	Eep_ESC_MCU:	DB	"#BLHELI$EFM8B21#"
ELSEIF MCU_TYPE == 2
	Eep_ESC_MCU:	DB	"#BLHELI$EFM8B51#"
ENDIF

Interrupt_Table_Definition MACRO
CSEG AT 0							;; Code segment start
	jmp	reset
CSEG AT 03h						;; Int0 interrupt
	jmp	int0_int
CSEG AT 0Bh						;; Timer0 overflow interrupt
	jmp	t0_int
CSEG AT 13h						;; Int1 interrupt
	jmp	int1_int
CSEG AT 1Bh						;; Timer1 overflow interrupt
	jmp	t1_int
CSEG AT 2Bh						;; Timer2 overflow interrupt
	jmp	t2_int
CSEG AT 5Bh						;; PCA interrupt
	jmp	pca_int
CSEG AT 73h						;; Timer3 overflow/compare interrupt
	jmp	t3_int
ENDM

Initialize_PCA MACRO
	mov	PCA0CN0, #40h				;; PCA enabled
	mov	PCA0MD, #08h				;; PCA clock is system clock

	mov A, #80h
	add A, PwmBitsCount
	mov	PCA0PWM, A					;; Enable PCA auto-reload registers and set pwm cycle length (8-11 bits)

IF PWM_CENTERED == 1
	mov	PCA0CENT, #07h				;; Center aligned pwm
ELSE
	mov	PCA0CENT, #00h				;; Edge aligned pwm
ENDIF
ENDM

Set_MCU_Clk_24MHz MACRO
	mov	CLKSEL, #13h				;; Set clock to 24MHz (Oscillator 1 divided by 2)

	mov	SFRPAGE, #10h
	mov	PFE0CN, #00h				;; Set flash timing for 24MHz and disable prefetch engine
	mov	SFRPAGE, #00h
ENDM

Set_MCU_Clk_48MHz MACRO
	mov	SFRPAGE, #10h
	IF MCU_TYPE == 1
		mov	PFE0CN, #30h			;; Set flash timing for 48MHz and enable prefetch engine
	ELSEIF MCU_TYPE == 2
		mov	PFE0CN, #10h			;; Set flash timing for 48MHz
	ENDIF
	mov	SFRPAGE, #00h

	mov	CLKSEL, #03h				;; Set clock to 48MHz (Oscillator 1)
ENDM


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Additional dshot macros
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****

DSHOT_TLM_CLOCK     EQU 24500000                ; 24.5MHz
DSHOT_TLM_START_DELAY   EQU -(5 * 25 / 4)           ; Start telemetry after 5 us (~30 us after receiving DShot cmd)
IF MCU_TYPE == 0
DSHOT_TLM_PREDELAY      EQU 9                   ; 9 Timer0 ticks inherent delay
ELSE
DSHOT_TLM_PREDELAY      EQU 7                   ; 7 Timer0 ticks inherent delay
ENDIF

IF MCU_TYPE >= 1
    DSHOT_TLM_CLOCK_48      EQU 49000000            ; 49MHz
    DSHOT_TLM_START_DELAY_48    EQU -(16 * 49 / 4)      ; Start telemetry after 16 us (~30 us after receiving DShot cmd)
    DSHOT_TLM_PREDELAY_48   EQU 11              ; 11 Timer0 ticks inherent delay
ENDIF


Set_DShot_Tlm_Bitrate MACRO rate
    mov DShot_GCR_Pulse_Time_1, #(DSHOT_TLM_PREDELAY - (1 * DSHOT_TLM_CLOCK / 4 / rate))
    mov DShot_GCR_Pulse_Time_2, #(DSHOT_TLM_PREDELAY - (2 * DSHOT_TLM_CLOCK / 4 / rate))
    mov DShot_GCR_Pulse_Time_3, #(DSHOT_TLM_PREDELAY - (3 * DSHOT_TLM_CLOCK / 4 / rate))

    mov DShot_GCR_Start_Delay, #DSHOT_TLM_START_DELAY

IF MCU_TYPE >= 1
    mov DShot_GCR_Pulse_Time_1_Tmp, #(DSHOT_TLM_PREDELAY_48 - (1 * DSHOT_TLM_CLOCK_48 / 4 / rate))
    mov DShot_GCR_Pulse_Time_2_Tmp, #(DSHOT_TLM_PREDELAY_48 - (2 * DSHOT_TLM_CLOCK_48 / 4 / rate))
    mov DShot_GCR_Pulse_Time_3_Tmp, #(DSHOT_TLM_PREDELAY_48 - (3 * DSHOT_TLM_CLOCK_48 / 4 / rate))
ENDIF
ENDM


; DShot GCR encoding, adjust time by adding to previous item
GCR_Add_Time MACRO reg
    mov B, @reg
    mov A, DShot_GCR_Pulse_Time_2
    cjne    A, B, ($+5)
    mov A, DShot_GCR_Pulse_Time_3
    mov @reg, A
ENDM

; Prepare telemetry packet while waiting for Timer3 to wrap
; Uses temp1:2:3:4:5
Wait_For_Timer3 MACRO
LOCAL wait_begin wait_run_rcpulse_stm_first wait_run_telemetry_stm_first wait_for_t3 wait_end
wait_begin:
	cpl Flag_Stm_Select
	jnb Flag_Stm_Select, wait_run_telemetry_stm_first

wait_run_rcpulse_stm_first:
    ; Run at least 1 state of rcpulse stm, so firmware cannot get
    ; stuck at max PWM
    call    dshot_rcpulse_stm

    ; If no Flag_Timer3_Pending end
    jnb Flag_Timer3_Pending, wait_end

    ; Run telemetry packet state machine only if telemetry is
    ; pending and timer3 is pending
    call    dshot_tlmpacket_stm
    sjmp wait_for_t3

wait_run_telemetry_stm_first:
    ; Run telemetry packet state machine only if telemetry is
    ; pending and timer3 is pending
    call    dshot_tlmpacket_stm

    ; If no Flag_Timer3_Pending end
    jnb Flag_Timer3_Pending, wait_end

    ; Run at least 1 state of rcpulse stm, so firmware cannot get
    ; stuck at max PWM
    call    dshot_rcpulse_stm

wait_for_t3:
    ; Now wait until timer3 overflows
    jb Flag_Timer3_Pending, wait_for_t3

wait_end:
ENDM

Decode_DShot_2Bit MACRO dest, decode_fail
    movx    A, @Temp1
    mov Temp7, A
    clr C
    subb    A, Temp6                    ;; Subtract previous timestamp
    clr C
    subb    A, Temp2
    jc  decode_fail             ;; Check that bit is longer than minimum

    subb    A, Temp2                    ;; Check if bit is zero or one
    rlca    dest                        ;; Shift bit into data byte
    inc Temp1                   ;; Next bit

    movx    A, @Temp1
    mov Temp6, A
    clr C
    subb    A, Temp7
    clr C
    subb    A, Temp2
    jc  decode_fail

    subb    A, Temp2
    rlca    dest
    inc Temp1
ENDM

;**** **** **** **** ****
; Compound instructions for convenience
xcha MACRO var1, var2               ;; Exchange via accumulator
    mov A, var1
    xch A, var2
    mov var1, A
ENDM

rrca MACRO var                      ;; Rotate right through carry via accumulator
    mov A, var
    rrc A
    mov var, A
ENDM

rlca MACRO var                      ;; Rotate left through carry via accumulator
    mov A, var
    rlc A
    mov var, A
ENDM

rla MACRO var                       ;; Rotate left via accumulator
    mov A, var
    rl  A
    mov var, A
ENDM

ljc MACRO label                 ;; Long jump if carry set
LOCAL skip
    jnc skip
    jmp label
skip:
ENDM

ljz MACRO label                 ;; Long jump if accumulator is zero
LOCAL skip
    jnz skip
    jmp label
skip:
ENDM

imov MACRO reg, val                 ;; Increment pointer register and move
    inc reg
    mov @reg, val                   ;; Write value to memory address pointed to by register
ENDM

;**** **** **** **** ****
; Division
;
; ih, il: input (hi byte, lo byte)
; oh, ol: output (hi byte, lo byte)
;
Divide_By_16 MACRO ih, il, oh, ol
    mov A, ih
    swap    A
    mov ol, A
    anl A, #00Fh
    mov oh, A
    mov A, ol
    anl A, #0F0h
    mov ol, A
    mov A, il
    swap    A
    anl A, #00Fh
    orl A, ol
    mov ol, A
ENDM

Divide_12Bit_By_16 MACRO ih, il, ol ;; Only if ih < 16
    mov A, ih
    swap    A
    mov ol, A
    mov A, il
    swap    A
    anl A, #00Fh
    orl A, ol
    mov ol, A
ENDM

Divide_By_8 MACRO ih, il, oh, ol
    mov A, ih
    swap    A
    rl  A
    mov ol, A
    anl A, #01Fh
    mov oh, A
    mov A, ol
    anl A, #0E0h
    mov ol, A
    mov A, il
    swap    A
    rl  A
    anl A, #01Fh
    orl A, ol
    mov ol, A
ENDM

Divide_11Bit_By_8 MACRO ih, il, ol      ;; Only if ih < 8
    mov A, ih
    swap    A
    rl  A
    mov ol, A
    mov A, il
    swap    A
    rl  A
    anl A, #01Fh
    orl A, ol
    mov ol, A
ENDM

Divide_By_4 MACRO ih, il, oh, ol
    clr C
    mov A, ih
    rrc A
    mov oh, A
    mov A, il
    rrc A
    mov ol, A

    clr C
    mov A, oh
    rrc A
    mov oh, A
    mov A, ol
    rrc A
    mov ol, A
ENDM

; Mul u16 x u8
;     18 cycles
; o2:1:0 = a2:1 * b0
MulU16xU8 MACRO a1o2, a0o1, b0o0
    mov B, a0o1
    mov A, b0o0
    mul AB

    xch A, b0o0
    mov a0o1, B
    mov B, a1o2
    mul AB

    add A, a0o1
    mov a0o1, A

    mov A, B
    addc A, #0
    mov a1o2, A
ENDM
