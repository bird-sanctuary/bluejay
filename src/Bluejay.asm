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
; Bluejay is a fork of BLHeli_S <https://github.com/bitdump/BLHeli> by Steffen Skaug.
;
; The input signal can be DShot with rates: DShot150, DShot300 and DShot600.
;
; This file is best viewed with tab width set to 5.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Master clock is internal 24MHz oscillator (or 48MHz, for which the times below are halved)
; Although 24/48 are used in the code, the exact clock frequencies are 24.5MHz or 49.0 MHz
; Timer0 (41.67ns counts) always counts up and is used for
; - RC pulse measurement
; - DShot telemetry pulse timing
; Timer1 (41.67ns counts) always counts up and is used for
; - DShot frame sync detection
; Timer2 (500ns counts) always counts up and is used for
; - RC pulse timeout counts and commutation times
; Timer3 (500ns counts) always counts up and is used for
; - Commutation timeouts
; PCA0 (41.67ns counts) always counts up and is used for
; - Hardware PWM generation
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Motor control:
; - Brushless motor control with 6 states for each electrical 360 degrees
; - An advance timing of 0deg has zero cross 30deg after one commutation and 30deg before the next
; - Timing advance in this implementation is set to 15deg nominally
; - Motor pwm is always damped light (aka complementary pwm, regenerative braking)
; Motor sequence starting from zero crossing:
; - Timer wait: Wt_Comm            15deg    ; Time to wait from zero cross to actual commutation
; - Timer wait: Wt_Advance         15deg    ; Time to wait for timing advance. Nominal commutation point is after this
; - Timer wait: Wt_Zc_Scan         7.5deg   ; Time to wait before looking for zero cross
; - Scan for zero cross            22.5deg  ; Nominal, with some motor variations
;
; Motor startup:
; There is a startup phase and an initial run phase, before normal bemf commutation run begins.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Legend:
; RX            Receive/transmit pin
; Am, Bm, Cm    Comparator inputs for BEMF
; Vn            Common Comparator input
; Ap, Bp, Cp    PWM pins
; Ac, Bc, Cc    Complementary PWM pins
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

$include (Modules\Enums.asm)

; List of enumerated supported ESCs
;                                         PORT 0                   |  PORT 1                   |  PWM    COM    PWM    LED
;                                         P0 P1 P2 P3 P4 P5 P6 P7  |  P0 P1 P2 P3 P4 P5 P6 P7  |  inv    inv    side    n
;                                         -----------------------  |  -----------------------  |  -------------------------
IF MCU_TYPE == MCU_BB2
    A_ EQU 1                            ; Vn Am Bm Cm __ RX __ __  |  Ap Ac Bp Bc Cp Cc __ __  |  no     no     high   _
    B_ EQU 2                            ; Vn Am Bm Cm __ RX __ __  |  Cc Cp Bc Bp Ac Ap __ __  |  no     no     high   _
    C_ EQU 3                            ; RX __ Vn Am Bm Cm Ap Ac  |  Bp Bc Cp Cc __ __ __ __  |  no     no     high   _
    D_ EQU 4                            ; Bm Cm Am Vn __ RX __ __  |  Ap Ac Bp Bc Cp Cc __ __  |  no     yes    high   _
    E_ EQU 5                            ; Vn Am Bm Cm __ RX L0 L1  |  Ap Ac Bp Bc Cp Cc L2 __  |  no     no     high   3 Pinout like A, with LEDs
    F_ EQU 6                            ; Vn Cm Bm Am __ RX __ __  |  Ap Ac Bp Bc Cp Cc __ __  |  no     no     high   _
    G_ EQU 7                            ; Bm Cm Am Vn __ RX __ __  |  Ap Ac Bp Bc Cp Cc __ __  |  no     no     high   _ Pinout like D, but non-inverted com FETs
    H_ EQU 8                            ; Cm Vn Bm Am __ __ __ RX  |  Cc Bc Ac __ Cp Bp Ap __  |  no     no     high   _
    I_ EQU 9                            ; Vn Am Bm Cm __ RX __ __  |  Cp Bp Ap Cc Bc Ac __ __  |  no     no     high   _
    J_ EQU 10                           ; Am Cm Bm Vn RX L0 L1 L2  |  Ap Bp Cp Ac Bc Cc __ __  |  no     no     high   3
    K_ EQU 11                           ; RX Am Vn Bm __ Cm __ __  |  Ac Bc Cc Cp Bp Ap __ __  |  no     yes    high   _
    L_ EQU 12                           ; Cm Bm Am Vn __ RX __ __  |  Cp Bp Ap Cc Bc Ac __ __  |  no     no     high   _
    M_ EQU 13                           ; __ __ L0 RX Bm Vn Cm Am  |  __ Ap Bp Cp Ac Bc Cc __  |  no     no     high   1
    N_ EQU 14                           ; Vn Am Bm Cm __ RX __ __  |  Ac Ap Bc Bp Cc Cp __ __  |  no     no     high   _
    O_ EQU 15                           ; Bm Cm Am Vn __ RX __ __  |  Ap Ac Bp Bc Cp Cc __ __  |  no     yes    low    _ Pinout Like D, but low side pwm
    P_ EQU 16                           ; __ Cm Bm Vn Am RX __ __  |  __ Ap Bp Cp Ac Bc Cc __  |  no     no     high   _
    Q_ EQU 17                           ; __ RX __ L0 L1 Ap Bp Cp  |  Ac Bc Cc Vn Cm Bm Am __  |  no     no     high   2
    R_ EQU 18                           ; Vn Am Bm Cm __ RX __ __  |  Cp Bp Ap Cc Bc Ac __ __  |  no     no     high   _ Same as I
    S_ EQU 19                           ; Bm Cm Am Vn __ RX __ __  |  Ac Ap Bc Bp Cc Cp __ __  |  no     no     high   _
    T_ EQU 20                           ; __ Cm Vn Bm __ Am __ RX  |  Cc Bc Ac Ap Bp Cp __ __  |  no     no     high   _
    U_ EQU 21                           ; L2 L1 L0 RX Bm Vn Cm Am  |  __ Ap Bp Cp Ac Bc Cc __  |  no     no     high   3 Pinout like M, with 3 LEDs
    V_ EQU 22                           ; Am Bm Vn Cm __ RX __ Cc  |  Cp Bc __ __ Bp Ac Ap __  |  no     no     high   _
    W_ EQU 23                           ; __ __ Am Vn __ Bm Cm RX  |  __ __ __ __ Cp Bp Ap __  |  n/a    n/a    high   _ Tristate gate driver
    X_ EQU 24
    Y_ EQU 25
    Z_ EQU 26                           ; Bm Cm Am Vn __ RX __ __  |  Ac Ap Bc Bp Cc Cp __ __  |  yes    no     high   _ Pinout like S, but inverted pwm FETs

    ; Two letter layouts start here. Preferably the first letter is the base
    ; layout and the second letter is the variation in alphabetical order.
    OA_ EQU 27                          ; Bm Cm Am Vn __ RX __ __  |  Ap Ac Bp Bc Cp Cc __ __  |  no     yes    low    _ Pinout Like O, but open drain instead of push-pull COM FETs
ENDIF

; BB51 - Required
IF MCU_TYPE == MCU_BB51
    A_ EQU 1                            ; __ Bm Cm Am Vn RX __ __  |  Ap Ac Bp Bc Cp Cc __ __  |  no     no     low    _
    B_ EQU 2                            ; __ Bm Cm Am Vn RX __ __  |  Ac Ap Bc Bp Cc Cp __ __  |  no     yes    high   _
    C_ EQU 3                            ; __ Bm Cm Am Vn RX __ __  |  Ac Ap Bc Bp Cc Cp __ __  |  yes    yes    high   _
    D_ EQU 4                            ; __ Bm Cm Am Vn RX __ __  |  Ap Ac Bp Bc Cp Cc __ __  |  no	 yes 	high   _
	E_ EQU 5                            ; __ Cm Bm Am Vn RX __ __  |  Cp Bp Ap Cc Bc Ac __ __  |  no	 yes 	high   _
ENDIF

; Select the port mapping to use (or unselect all for use with external batch compile file)
;ESCNO            EQU    A_

; Select the MCU type (or unselect for use with external batch compile file)
;MCU_TYPE        EQU    0    ; BB1
;MCU_TYPE        EQU    1    ; BB2
;MCU_TYPE        EQU    2    ; BB51

; Select the FET dead time (or unselect for use with external batch compile file)
;DEADTIME            EQU    15    ; 20.4ns per step

; Select the pwm frequency (or unselect for use with external batch compile file)
;PWM_FREQ            EQU    0    ; 0=24, 1=48, 2=96 kHz

PWM_CENTERED EQU DEADTIME > 0           ; Use center aligned pwm on ESCs with dead time

IS_MCU_48MHZ EQU 1

IF PWM_FREQ == PWM_24 or PWM_FREQ == PWM_48 or PWM_FREQ == PWM_96
    ; Number of bits in pwm high byte
    PWM_BITS_H EQU (3 - PWM_CENTERED - PWM_FREQ)
ENDIF

$include (Modules\McuOffsets.asm)
$include (Modules\Codespace.asm)
$include (Modules\Common.asm)
$include (Modules\Macros.asm)

; This file is Searched within the INCDIR set in the Makefile.
; This allows overwriting the settings by putting a file with the same name in
; a different directory and setting that in INCDIR.
$include (BluejaySettings.asm)

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Temporary register definitions
;**** **** **** **** **** **** **** **** **** **** **** **** ****
Temp1 EQU R0
Temp2 EQU R1
Temp3 EQU R2
Temp4 EQU R3
Temp5 EQU R4
Temp6 EQU R5
Temp7 EQU R6
Temp8 EQU R7

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; RAM definitions
; Bit-addressable data segment
;**** **** **** **** **** **** **** **** **** **** **** **** ****
DSEG AT 20h
Bit_Access: DS 1                        ; MUST BE AT THIS ADDRESS. Variable at bit accessible address (for non interrupt routines)
Bit_Access_Int: DS 1                    ; Variable at bit accessible address (for interrupts)

Flags0: DS 1                            ; State flags. Reset upon motor_start
    Flag_Startup_Phase BIT Flags0.0     ; Set when in startup phase
    Flag_Initial_Run_Phase BIT Flags0.1 ; Set when in initial run phase (or startup phase),before synchronized run is achieved.
    Flag_Motor_Dir_Rev BIT Flags0.2     ; Set if the current spinning direction is reversed
    Flag_Demag_Notify BIT Flags0.3      ; Set when motor demag has been detected but still not notified
    Flag_Desync_Notify BIT Flags0.4     ; Set when motor desync has been detected but still not notified
    Flag_Stall_Notify BIT Flags0.5      ; Set when motor stall detected but still not notified

Flags1: DS 1                            ; State flags. Reset upon motor_start
    Flag_Timer3_Pending BIT Flags1.0    ; Timer3 pending flag
    Flag_Demag_Detected BIT Flags1.1    ; Set when excessive demag time is detected
    Flag_Comp_Timed_Out BIT Flags1.2    ; Set when comparator reading timed out
    Flag_Motor_Running BIT Flags1.3
    Flag_Motor_Started BIT Flags1.4     ; Set when motor is started
    Flag_Dir_Change_Brake BIT Flags1.5  ; Set when braking before direction change in case of bidirectional operation
    Flag_High_Rpm BIT Flags1.6          ; Set when motor rpm is high (Comm_Period4x_H less than 2)

Flags2: DS 1                            ; State flags. NOT reset upon motor_start
    ; BIT    Flags2.0
    Flag_Pgm_Dir_Rev BIT Flags2.1       ; Set if the programmed direction is reversed
    Flag_Pgm_Bidir BIT Flags2.2         ; Set if the programmed control mode is bidirectional operation
    Flag_16ms_Elapsed BIT Flags2.3      ; Set when timer2 interrupt is triggered
    Flag_Ext_Tele BIT Flags2.4          ; Set if Extended DHOT telemetry is enabled
    Flag_Rcp_Stop BIT Flags2.5          ; Set if the RC pulse value is zero or if timeout occurs
    Flag_Rcp_Dir_Rev BIT Flags2.6       ; RC pulse direction in bidirectional mode
    Flag_Rcp_DShot_Inverted BIT Flags2.7 ; DShot RC pulse input is inverted (and supports telemetry)

Flags3: DS 1                            ; State flags. NOT reset upon motor_start
    Flag_Telemetry_Pending BIT Flags3.0 ; DShot telemetry data packet is ready to be sent
    Flag_Had_Signal BIT Flags3.1        ; Used to detect reset after having had a valid signal
    Flag_User_Reverse_Requested BIT Flags3.2 ; It is set when user request to reverse motors in turtle mode


Tlm_Data_L: DS 1                        ; DShot telemetry data (lo byte)
Tlm_Data_H: DS 1                        ; DShot telemetry data (hi byte)
;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Direct addressing data segment
;**** **** **** **** **** **** **** **** **** **** **** **** ****
DSEG AT 30h
Rcp_Outside_Range_Cnt: DS 1             ; RC pulse outside range counter (incrementing)
Rcp_Timeout_Cntd: DS 1                  ; RC pulse timeout counter (decrementing)
Rcp_Stop_Cnt: DS 1                      ; Counter for RC pulses below stop value

Beacon_Delay_Cnt: DS 1                  ; Counter to trigger beacon during wait for start
Startup_Cnt: DS 1                       ; Startup phase commutations counter (incrementing)
Startup_Zc_Timeout_Cntd: DS 1           ; Startup zero cross timeout counter (decrementing)
Initial_Run_Rot_Cntd: DS 1              ; Initial run rotations counter (decrementing)
Startup_Stall_Cnt: DS 1                 ; Counts start/run attempts that resulted in stall. Reset upon a proper stop
Demag_Detected_Metric: DS 1             ; Metric used to gauge demag event frequency
Demag_Detected_Metric_Max: DS 1         ; Metric used to gauge demag event frequency
Demag_Pwr_Off_Thresh: DS 1              ; Metric threshold above which power is cut
Low_Rpm_Pwr_Slope: DS 1                 ; Sets the slope of power increase for low rpm
Timer2_X: DS 1                          ; Timer2 extended byte
Prev_Comm_L: DS 1                       ; Previous commutation Timer2 timestamp (lo byte)
Prev_Comm_H: DS 1                       ; Previous commutation Timer2 timestamp (hi byte)
Prev_Comm_X: DS 1                       ; Previous commutation Timer2 timestamp (ext byte)
Prev_Prev_Comm_L: DS 1                  ; Pre-previous commutation Timer2 timestamp (lo byte)
Prev_Prev_Comm_H: DS 1                  ; Pre-previous commutation Timer2 timestamp (hi byte)
Comm_Period4x_L: DS 1                   ; Timer2 ticks between the last 4 commutations (lo byte)
Comm_Period4x_H: DS 1                   ; Timer2 ticks between the last 4 commutations (hi byte)
Comparator_Read_Cnt: DS 1               ; Number of comparator reads done
Wt_Adv_Start_L: DS 1                    ; Timer3 start point for commutation advance timing (lo byte)
Wt_Adv_Start_H: DS 1                    ; Timer3 start point for commutation advance timing (hi byte)
Wt_Zc_Scan_Start_L: DS 1                ; Timer3 start point from commutation to zero cross scan (lo byte)
Wt_Zc_Scan_Start_H: DS 1                ; Timer3 start point from commutation to zero cross scan (hi byte)
Wt_Zc_Tout_Start_L: DS 1                ; Timer3 start point for zero cross scan timeout (lo byte)
Wt_Zc_Tout_Start_H: DS 1                ; Timer3 start point for zero cross scan timeout (hi byte)
Wt_Comm_Start_L: DS 1                   ; Timer3 start point from zero cross to commutation (lo byte)
Wt_Comm_Start_H: DS 1                   ; Timer3 start point from zero cross to commutation (hi byte)
Pwm_Limit: DS 1                         ; Maximum allowed pwm (8-bit)
Pwm_Limit_By_Rpm: DS 1                  ; Maximum allowed pwm for low or high rpm (8-bit)
Pwm_Limit_Beg: DS 1                     ; Initial pwm limit (8-bit)
Pwm_Braking_L: DS 1                     ; Max Braking pwm (lo byte)
Pwm_Braking_H: DS 1                     ; Max Braking pwm (hi byte)
Temp_Prot_Limit: DS 1                   ; Temperature protection limit
Temp_Pwm_Level_Setpoint: DS 1           ; PWM level setpoint
Beep_Strength: DS 1                     ; Strength of beeps
Flash_Key_1: DS 1                       ; Flash key one
Flash_Key_2: DS 1                       ; Flash key two
DShot_Pwm_Thr: DS 1                     ; DShot pulse width threshold value (Timer0 ticks)
DShot_Timer_Preset: DS 1                ; DShot timer preset for frame sync detection (Timer1 lo byte)
DShot_Frame_Start_L: DS 1               ; DShot frame start timestamp (Timer2 lo byte)
DShot_Frame_Start_H: DS 1               ; DShot frame start timestamp (Timer2 hi byte)
DShot_Frame_Length_Thr: DS 1            ; DShot frame length criteria (Timer2 ticks)
DShot_Cmd: DS 1                         ; DShot command
DShot_Cmd_Cnt: DS 1                     ; DShot command count
; Pulse durations for GCR encoding DShot telemetry data
DShot_GCR_Pulse_Time_1: DS 1            ; Encodes binary: 1
DShot_GCR_Pulse_Time_2: DS 1            ; Encodes binary: 01
DShot_GCR_Pulse_Time_3: DS 1            ; Encodes binary: 001

DShot_GCR_Pulse_Time_1_Tmp: DS 1
DShot_GCR_Pulse_Time_2_Tmp: DS 1
DShot_GCR_Pulse_Time_3_Tmp: DS 1
DShot_GCR_Start_Delay: DS 1
Ext_Telemetry_L: DS 1                   ; Extended telemetry data to be sent
Ext_Telemetry_H: DS 1
Scheduler_Counter: DS 1                 ; Scheduler Heartbeat
;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Indirect addressing data segments
;**** **** **** **** **** **** **** **** **** **** **** **** ****
ISEG AT 080h                            ; The variables below must be in this sequence
_Pgm_Gov_P_Gain: DS 1                   ;
Pgm_Startup_Power_Min: DS 1             ; Minimum power during startup phase
Pgm_Startup_Beep: DS 1                  ; Startup beep melody on/off
_Pgm_Dithering: DS 1                    ; Enable PWM dithering
Pgm_Startup_Power_Max: DS 1             ; Maximum power (limit) during startup (and starting initial run phase)
_Pgm_Rampup_Slope: DS 1                 ;
Pgm_Rpm_Power_Slope: DS 1               ; Low RPM power protection slope (factor)
Pgm_Pwm_Freq: DS 1                      ; PWM frequency (temporary method for display)
Pgm_Direction: DS 1                     ; Rotation direction
_Pgm_Input_Pol: DS 1                    ; Input PWM polarity
Initialized_L_Dummy: DS 1               ; Place holder
Initialized_H_Dummy: DS 1               ; Place holder
_Pgm_Enable_TX_Program: DS 1            ; Enable/disable value for TX programming
Pgm_Braking_Strength: DS 1              ; Set maximum braking strength (complementary pwm)
_Pgm_Gov_Setup_Target: DS 1             ; Main governor setup target
_Pgm_Startup_Rpm: DS 1                  ; Startup RPM
_Pgm_Startup_Accel: DS 1                ; Startup acceleration
_Pgm_Volt_Comp: DS 1                    ; Voltage comp
Pgm_Comm_Timing: DS 1                   ; Commutation timing
_Pgm_Damping_Force: DS 1                ; Damping force
_Pgm_Gov_Range: DS 1                    ; Governor range
_Pgm_Startup_Method: DS 1               ; Startup method
_Pgm_Min_Throttle: DS 1                 ; Minimum throttle
_Pgm_Max_Throttle: DS 1                 ; Maximum throttle
Pgm_Beep_Strength: DS 1                 ; Beep strength
Pgm_Beacon_Strength: DS 1               ; Beacon strength
Pgm_Beacon_Delay: DS 1                  ; Beacon delay
_Pgm_Throttle_Rate: DS 1                ; Throttle rate
Pgm_Demag_Comp: DS 1                    ; Demag compensation
_Pgm_BEC_Voltage_High: DS 1             ; BEC voltage
_Pgm_Center_Throttle: DS 1              ; Center throttle (in bidirectional mode)
_Pgm_Main_Spoolup_Time: DS 1            ; Main spoolup time
Pgm_Enable_Temp_Prot: DS 1              ; Temperature protection enable
_Pgm_Enable_Power_Prot: DS 1            ; Low RPM power protection enable
_Pgm_Enable_Pwm_Input: DS 1             ; Enable PWM input signal
_Pgm_Pwm_Dither: DS 1                   ; Output PWM dither
Pgm_Brake_On_Stop: DS 1                 ; Braking when throttle is zero
Pgm_LED_Control: DS 1                   ; LED control
Pgm_Power_Rating: DS 1                  ; Power rating
Pgm_Safety_Arm: DS  1                   ; Various flag settings: bit 0 is require edt enable to arm

ISEG AT 0B0h
Stack: DS 16                            ; Reserved stack space

ISEG AT 0D0h
Temp_Storage: DS 48                     ; Temporary storage (internal memory)

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; EEPROM code segments
; A segment of the flash is used as "EEPROM", which is not available in SiLabs MCUs
;**** **** **** **** **** **** **** **** **** **** **** **** ****
CSEG AT CSEG_EEPROM
EEPROM_FW_MAIN_REVISION EQU 0           ; Main revision of the firmware
EEPROM_FW_SUB_REVISION EQU 21           ; Sub revision of the firmware
EEPROM_LAYOUT_REVISION EQU 208          ; Revision of the EEPROM layout
EEPROM_B2_PARAMETERS_COUNT EQU 28       ; Number of parameters

Eep_FW_Main_Revision: DB EEPROM_FW_MAIN_REVISION ; EEPROM firmware main revision number
Eep_FW_Sub_Revision: DB EEPROM_FW_SUB_REVISION ; EEPROM firmware sub revision number
Eep_Layout_Revision: DB EEPROM_LAYOUT_REVISION ; EEPROM layout revision number
_Eep_Pgm_Gov_P_Gain: DB 0FFh
Eep_Pgm_Startup_Power_Min: DB DEFAULT_PGM_STARTUP_POWER_MIN
Eep_Pgm_Startup_Beep: DB DEFAULT_PGM_STARTUP_BEEP
_Eep_Pgm_Dithering: DB 0FFh
Eep_Pgm_Startup_Power_Max: DB DEFAULT_PGM_STARTUP_POWER_MAX
_Eep_Pgm_Rampup_Slope: DB 0FFh
Eep_Pgm_Rpm_Power_Slope: DB DEFAULT_PGM_RPM_POWER_SLOPE ; EEPROM copy of programmed rpm power slope (formerly startup power)
Eep_Pgm_Pwm_Freq: DB (24 SHL PWM_FREQ)  ; Temporary method for display
Eep_Pgm_Direction: DB DEFAULT_PGM_DIRECTION ; EEPROM copy of programmed rotation direction
_Eep__Pgm_Input_Pol: DB 0FFh
Eep_Initialized_L: DB 055h              ; EEPROM initialized signature (lo byte)
Eep_Initialized_H: DB 0AAh              ; EEPROM initialized signature (hi byte)
; EEPROM parameters block 2 (B2)
_Eep_Enable_TX_Program: DB 0FFh         ; EEPROM TX programming enable
Eep_Pgm_Braking_Strength: DB DEFAULT_PGM_BRAKING_STRENGTH
_Eep_Pgm_Gov_Setup_Target: DB 0FFh
_Eep_Pgm_Startup_Rpm: DB 0FFh
_Eep_Pgm_Startup_Accel: DB 0FFh
_Eep_Pgm_Volt_Comp: DB 0FFh
Eep_Pgm_Comm_Timing: DB DEFAULT_PGM_COMM_TIMING ; EEPROM copy of programmed commutation timing
_Eep_Pgm_Damping_Force: DB 0FFh
_Eep_Pgm_Gov_Range: DB 0FFh
_Eep_Pgm_Startup_Method: DB 0FFh
_Eep_Pgm_Min_Throttle: DB 0FFh          ; EEPROM copy of programmed minimum throttle
_Eep_Pgm_Max_Throttle: DB 0FFh          ; EEPROM copy of programmed minimum throttle
Eep_Pgm_Beep_Strength: DB DEFAULT_PGM_BEEP_STRENGTH ; EEPROM copy of programmed beep strength
Eep_Pgm_Beacon_Strength: DB DEFAULT_PGM_BEACON_STRENGTH ; EEPROM copy of programmed beacon strength
Eep_Pgm_Beacon_Delay: DB DEFAULT_PGM_BEACON_DELAY ; EEPROM copy of programmed beacon delay
_Eep_Pgm_Throttle_Rate: DB 0FFh
Eep_Pgm_Demag_Comp: DB DEFAULT_PGM_DEMAG_COMP ; EEPROM copy of programmed demag compensation
_Eep_Pgm_BEC_Voltage_High: DB 0FFh
_Eep_Pgm_Center_Throttle: DB 0FFh       ; EEPROM copy of programmed center throttle
_Eep_Pgm_Main_Spoolup_Time: DB 0FFh
Eep_Pgm_Temp_Prot_Enable: DB DEFAULT_PGM_ENABLE_TEMP_PROT ; EEPROM copy of programmed temperature protection enable
_Eep_Pgm_Enable_Power_Prot: DB 0FFh     ; EEPROM copy of programmed low rpm power protection enable
_Eep_Pgm_Enable_Pwm_Input: DB 0FFh
_Eep_Pgm_Pwm_Dither: DB 0FFh
Eep_Pgm_Brake_On_Stop: DB DEFAULT_PGM_BRAKE_ON_STOP ; EEPROM copy of programmed braking when throttle is zero
Eep_Pgm_LED_Control: DB DEFAULT_PGM_LED_CONTROL ; EEPROM copy of programmed LED control
Eep_Pgm_Power_Rating: DB DEFAULT_PGM_POWER_RATING ; EEPROM copy of programmed power rating
Eep_Pgm_Safety_Arm: DB DEFAULT_PGM_SAFETY_ARM ; Various flag settings: bit 0 is require edt enable to arm

Eep_Dummy: DB 0FFh                      ; EEPROM address for safety reason
CSEG AT CSEG_NAME
Eep_Name: DB "Bluejay (.1 DEV)"         ; Name tag (16 Bytes)

CSEG AT CSEG_MELODY
Eep_Pgm_Beep_Melody: DB 2,58,4,32,52,66,13,0,69,45,13,0,52,66,13,0,78,39,211,0,69,45,208,25,52,25,0

    Interrupt_Table_Definition          ; SiLabs interrupts
CSEG AT CSEG_APP                        ; Code segment after interrupt vectors

; Submodule includes
$include (Modules\Isrs.asm)
$include (Modules\Fx.asm)
$include (Modules\Power.asm)
$include (Modules\Scheduler.asm)
$include (Modules\Timing.asm)
$include (Modules\Commutation.asm)
$include (Modules\DShot.asm)
$include (Modules\Eeprom.asm)
$include (Modules\Settings.asm)

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Main program
;
; Main program entry point
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
pgm_start:
    Lock_Flash
    mov  WDTCN, #0DEh                   ; Disable watchdog (WDT)
    mov  WDTCN, #0ADh
    mov  SP, #Stack                     ; Initialize stack (16 bytes of indirect RAM)
IF MCU_TYPE == MCU_BB2
    orl  VDM0CN, #080h                  ; Enable the VDD monitor
ENDIF
    mov  RSTSRC, #06h                   ; Set missing clock and VDD monitor as a reset source if not 1S capable
    mov  CLKSEL, #00h                   ; Set clock divider to 1 (Oscillator 0 at 24MHz)
    call switch_power_off
    ; Ports initialization
    mov  P0, #P0_INIT
    mov  P0MDIN, #P0_DIGITAL
    mov  P0MDOUT, #P0_PUSHPULL
    mov  P0, #P0_INIT
    mov  P0SKIP, #P0_SKIP
    mov  P1, #P1_INIT
    mov  P1MDIN, #P1_DIGITAL
    mov  P1MDOUT, #P1_PUSHPULL
    mov  P1, #P1_INIT
    mov  P1SKIP, #P1_SKIP
    mov  P2MDOUT, #P2_PUSHPULL
IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    ; Not available on BB1
    mov  SFRPAGE, #20h
    mov  P2MDIN, #P2_DIGITAL
IF MCU_TYPE == MCU_BB2
    ; Not available on BB51
    mov  P2SKIP, #P2_SKIP
ENDIF
    mov  SFRPAGE, #00h
ENDIF
    Initialize_Crossbar                 ; Initialize the crossbar and related functionality
    call switch_power_off               ; Switch power off again,after initializing ports

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Internal RAM
;
; EFM8 consists of 256 bytes of internal RAM of which the lower 128 bytes can be
; directly adressed and the upper portion (starting at 0x80) can only be
; indirectly accessed.
;
; NOTE: Upper portion of RAM and SFR use the same address space. RAM is accessed
;       indirectly. If you are directly accessing the upper space, you are - in
;       fact - addressing the SFR.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Clear internal RAM
;
; First the accumlator is cleared, then address is overflowed to 255 and content
; of addresses 255 - 0 is set to 0.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
    clr  A                              ; Clear accumulator
    mov  Temp1, A                       ; Clear Temp1
clear_ram:
    mov  @Temp1, A                      ; Clear RAM address
    djnz Temp1, clear_ram               ; Decrement address and repeat

    call set_default_parameters         ; Set default programmed parameters
    call read_all_eeprom_parameters     ; Read all programmed parameters
    call decode_settings                ; Decode programmed settings

    ; Initializing beeps
    clr  IE_EA                          ; Disable interrupts explicitly
    call wait100ms                      ; Wait a bit to avoid audible resets if not properly powered
    call play_beep_melody               ; Play startup beep melody
    call led_control                    ; Set LEDs to programmed values

    call wait100ms                      ; Wait for flight controller to get ready

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; No signal entry point
;**** **** **** **** **** **** **** **** **** **** **** **** ****
init_no_signal:
    clr  IE_EA                          ; Disable interrupts explicitly
    Lock_Flash
    call switch_power_off

IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    ; While not armed, all MCUs run at 24MHz clock frequency. After arming those
    ; MCUs that support it (BB2 & BB51) are switched to 48MHz clock frequency.
    Set_MCU_Clk_24MHz
ENDIF

    ; If input signal is high for about ~150ms, enter bootloader mode
    mov  Temp1, #9
    mov  Temp2, #0
    mov  Temp3, #0
input_high_check:
    jnb  RTX_BIT, bootloader_done       ; If low is detected, skip bootloader check
    djnz Temp3, input_high_check
    djnz Temp2, input_high_check
    djnz Temp1, input_high_check

    call beep_enter_bootloader

    ljmp CSEG_BOOT_START                ; Jump to bootloader

bootloader_done:
    ; If we had a signal before, reset the flag, beep, wait a bit and contiune
    ; with DSHOT setup. If we did not have a signal yet, continue with DSHOT
    ; setup straight away.
    jnb  Flag_Had_Signal, setup_dshot
    call beep_signal_lost

    ; Wait for flight controller to get ready
    call wait250ms
    call wait250ms
    call wait250ms
    clr  Flag_Had_Signal

setup_dshot:
    ; Setup timers for DShot
    mov  TCON, #51h                     ; Timer0/1 run and Int0 edge triggered
    mov  CKCON0, #01h                   ; Timer0/1 clock is system clock divided by 4 (for DShot150)
    mov  TMOD, #0AAh                    ; Timer0/1 set to 8-bits auto reload and gated by Int0/1
    mov  TH0, #0                        ; Auto reload value zero
    mov  TH1, #0

    mov  TMR2CN0, #04h                  ; Timer2 enabled (system clock divided by 12)
    mov  TMR3CN0, #04h                  ; Timer3 enabled (system clock divided by 12)

    Initialize_PCA                      ; Initialize PCA
    Set_Pwm_Polarity                    ; Set pwm polarity
    Enable_Power_Pwm_Module             ; Enable power pwm module
    Enable_Damp_Pwm_Module              ; Enable damping pwm module
    Initialize_Comparator               ; Initialize comparator
    Initialize_Adc                      ; Initialize ADC operation
    call wait1ms

    call detect_rcp_level               ; Detect RCP level (normal or inverted DShot)

    ; Route RCP according to detected DShot signal (normal or inverted)
    mov  IT01CF, #(80h + (RTX_PIN SHL 4) + RTX_PIN) ; Route RCP input to Int0/1,with Int1 inverted
    jnb  Flag_Rcp_DShot_Inverted, setup_dshot_clear_flags
    mov  IT01CF, #(08h + (RTX_PIN SHL 4) + RTX_PIN) ; Route RCP input to Int0/1,with Int0 inverted

setup_dshot_clear_flags:
    clr  Flag_Demag_Notify              ; Clear motor events
    clr  Flag_Desync_Notify
    clr  Flag_Stall_Notify
    clr  Flag_Telemetry_Pending         ; Clear DShot telemetry flag
    clr  Flag_Ext_Tele                  ; Clear extended telemetry enabled flag

    ; Setup interrupts
    mov  IE, #2Dh                       ; Enable Timer1/2 interrupts and Int0/1 interrupts
    mov  EIE1, #80h                     ; Enable Timer3 interrupts
    mov  IP, #03h                       ; High priority to Timer0 and Int0 interrupts

    setb IE_EA                          ; Enable all interrupts

    mov  CKCON0, #0Ch                   ; Timer0/1 clock is system clock (for DShot300/600)

    ; Setup variables for DShot300
    mov  DShot_Timer_Preset, #-128      ; Load DShot sync timer preset (for DShot300)
    mov  DShot_Pwm_Thr, #16             ; Load DShot pwm threshold (for DShot300)
    mov  DShot_Frame_Length_Thr, #80    ; Load DShot frame length criteria

    Set_DShot_Tlm_Bitrate 375000        ; = 5/4 * 300000

    ; Test whether signal is DShot300, if so begin arming
    mov  Rcp_Outside_Range_Cnt, #10     ; Set out of range counter
    call wait100ms                      ; Wait for new RC pulse
    mov  A, Rcp_Outside_Range_Cnt       ; Check if pulses were accepted
    jz   arming_begin

    ; Setup variables for DShot600
    mov  DShot_Timer_Preset, #-64       ; Load DShot sync timer preset (for DShot600)
    mov  DShot_Pwm_Thr, #8              ; Load DShot pwm threshold (for DShot600)
    mov  DShot_Frame_Length_Thr, #40    ; Load DShot frame length criteria

    Set_DShot_Tlm_Bitrate 750000        ; = 5/4 * 600000

    ; Test whether signal is DShot600, if so begin arming
    mov  Rcp_Outside_Range_Cnt, #10     ; Set out of range counter
    call wait100ms                      ; Wait for new RC pulse
    mov  A, Rcp_Outside_Range_Cnt       ; Check if pulses were accepted
    jz   arming_begin

    ; No valid signal detected, try again
    ljmp init_no_signal

arming_begin:
    push PSW
    mov  PSW, #10h                      ; Temp8 in register bank 2 holds value
    mov  Temp8, CKCON0                  ; Save DShot clock settings for telemetry
    pop  PSW

    setb Flag_Had_Signal                ; Mark that a signal has been detected
    mov  Startup_Stall_Cnt, #0          ; Reset stall count

    clr  IE_EA
    call beep_f1_short                  ; Confirm RC pulse detection by beeping
    setb IE_EA

; Make sure RC pulse has been zero for ~300ms
arming_wait:
    clr  C
    mov  A, Rcp_Stop_Cnt
    subb A, #10
    jc   arming_wait

    clr  IE_EA
    call beep_f2_short                  ; Confirm arm state by beeping
    setb IE_EA

; Armed and waiting for power on (RC pulse > 0)
wait_for_start:
    clr  A
    mov  Comm_Period4x_L, A             ; Reset commutation period for telemetry
    mov  Comm_Period4x_H, A
    mov  DShot_Cmd, A                   ; Reset DShot command (only considered in this loop)
    mov  DShot_Cmd_Cnt, A
    mov  Beacon_Delay_Cnt, A            ; Clear beacon wait counter
    mov  Timer2_X, A                    ; Clear Timer2 extended byte

wait_for_start_loop:
    clr  C
    mov  A, Timer2_X
    subb A, #94
    jc   wait_for_start_no_beep         ; Counter wrapping (about 3 sec)

    mov  Timer2_X, #0
    inc  Beacon_Delay_Cnt               ; Increment beacon wait counter

    mov  Temp1, #Pgm_Beacon_Delay
    mov  A, @Temp1
    mov  Temp1, #20                     ; 1 min
    dec  A
    jz   beep_delay_set

    mov  Temp1, #40                     ; 2 min
    dec  A
    jz   beep_delay_set

    mov  Temp1, #100                    ; 5 min
    dec  A
    jz   beep_delay_set

    mov  Temp1, #200                    ; 10 min
    dec  A
    jz   beep_delay_set

    mov  Beacon_Delay_Cnt, #0           ; Reset beacon counter for infinite delay

beep_delay_set:
    clr  C
    mov  A, Beacon_Delay_Cnt
    subb A, Temp1                       ; Check against chosen delay
    jc   wait_for_start_no_beep         ; Has delay elapsed?

    dec  Beacon_Delay_Cnt               ; Decrement counter for continued beeping

    mov  Temp1, #4                      ; Beep tone 4
    clr  IE_EA                          ; Disable all interrupts
    call switch_power_off               ; Switch power off in case braking is set
    call beacon_beep
    setb IE_EA                          ; Enable all interrupts

wait_for_start_no_beep:
    jb   Flag_Telemetry_Pending, wait_for_start_check_rcp
    call dshot_tlm_create_packet        ; Create telemetry packet (0 rpm)
    call scheduler_run

wait_for_start_check_rcp:
    ; If RC pulse is higher than stop (>0) then proceed to start the motor
    jnb  Flag_Rcp_Stop, wait_for_start_nonzero

    mov  A, Rcp_Timeout_Cntd            ; Load RC pulse timeout counter value
    ljz  init_no_signal                 ; If pulses are missing - go back to detect input signal

    call dshot_cmd_check                ; Check and process DShot command

    sjmp wait_for_start_loop            ; Go back to beginning of wait loop

wait_for_start_nonzero:
    call wait100ms                      ; Wait to see if start pulse was glitch

    ; If RC pulse returned to stop (0) - start over
    jb   Flag_Rcp_Stop, wait_for_start_loop

    ; If no safety arm jump to motor start
    mov  Temp1, #Pgm_Safety_Arm
    cjne @Temp1, #001h, motor_start

    ; If EDT flag is set start motor
    jb  Flag_Ext_Tele, motor_start

    ; Safety is enabled. Check Flag_Ext_Tele is set
    ; If not set beep and wait again
    call beep_safety_no_arm
    jmp  wait_for_start_loop



;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Motor start entry point
;**** **** **** **** **** **** **** **** **** **** **** **** ****
motor_start:
    clr  IE_EA                          ; Disable interrupts

    call switch_power_off

    clr  A
    mov  Flags0, #0                     ; Clear run time flags
    mov  Flags1, #0
    mov  Demag_Detected_Metric, #0      ; Clear demag metric
    mov  Demag_Detected_Metric_Max, #0  ; Clear demag metric max
    mov  Ext_Telemetry_H, #0            ; Clear extended telemetry data

    ; Set up start operating conditions
    mov  Temp2, #Pgm_Startup_Power_Max
    mov  Pwm_Limit_Beg, @Temp2          ; Set initial pwm limit
    mov  Pwm_Limit_By_Rpm, Pwm_Limit_Beg

    ; Set temperature PWM limit and setpoint to the maximum value
    mov  Pwm_Limit, Pwm_Limit_Beg
    mov  Temp_Pwm_Level_Setpoint, Pwm_Limit_Beg

; Begin startup sequence
IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    Set_MCU_Clk_48MHz                   ; Enable 48MHz clock frequency

    ; Scale DShot criteria for 48MHz
    clr  C
    rlca DShot_Timer_Preset             ; Scale sync timer preset

    clr  C
    rlca DShot_Frame_Length_Thr         ; Scale frame length criteria

    clr  C
    rlca DShot_Pwm_Thr                  ; Scale pulse width criteria

    ; Scale DShot telemetry for 48MHz
    xcha DShot_GCR_Pulse_Time_1, DShot_GCR_Pulse_Time_1_Tmp
    xcha DShot_GCR_Pulse_Time_2, DShot_GCR_Pulse_Time_2_Tmp
    xcha DShot_GCR_Pulse_Time_3, DShot_GCR_Pulse_Time_3_Tmp

    mov  DShot_GCR_Start_Delay, #DSHOT_TLM_START_DELAY_48
ENDIF

    mov  C, Flag_Pgm_Dir_Rev            ; Read spin direction setting
    mov  Flag_Motor_Dir_Rev, C

    jnb  Flag_Pgm_Bidir, motor_start_bidir_done ; Check if bidirectional operation

    mov  C, Flag_Rcp_Dir_Rev            ; Read force direction
    mov  Flag_Motor_Dir_Rev, C          ; Set spinning direction

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Motor start beginning
;**** **** **** **** **** **** **** **** **** **** **** **** ****
motor_start_bidir_done:
    ; Set initial motor state
    setb Flag_Startup_Phase             ; Set startup phase flags
    setb Flag_Initial_Run_Phase
    mov  Startup_Cnt, #0                ; Reset startup phase run counter
    mov  Initial_Run_Rot_Cntd, #12      ; Set initial run rotation countdown

    ; Initialize commutation
    call comm5_comm6                    ; Initialize commutation
    call comm6_comm1
    call initialize_timing              ; Initialize timing
    call calc_next_comm_period          ; Set virtual commutation point
    call initialize_timing              ; Initialize timing
    call calc_next_comm_period
    call initialize_timing              ; Initialize timing

    setb IE_EA                          ; Enable interrupts

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Run entry point
;
; Run 1 = B(p-on) + C(n-pwm) - comparator A evaluated
; Out_cA changes from low to high
;**** **** **** **** **** **** **** **** **** **** **** **** ****
run1:
    call wait_for_comp_out_high         ; Wait for high
    ; setup_comm_wait                    ; Setup wait time from zero cross to commutation
    ; evaluate_comparator_integrity      ; Check whether comparator reading has been normal
    call wait_for_comm                  ; Wait from zero cross to commutation
    call comm1_comm2                    ; Commutate
    call calc_next_comm_period          ; Calculate next timing and wait advance timing wait
    ; wait_advance_timing                ; Wait advance timing and start zero cross wait
    ; calc_new_wait_times
    ; wait_before_zc_scan                ; Wait zero cross wait and start zero cross timeout

; Run 2 = A(p-on) + C(n-pwm) - comparator B evaluated
; Out_cB changes from high to low
run2:
    call wait_for_comp_out_low
    ; setup_comm_wait
    ; evaluate_comparator_integrity
    call set_pwm_limit                  ; Set pwm power limit for low or high rpm
    call wait_for_comm
    call comm2_comm3
    call calc_next_comm_period
    ; wait_advance_timing
    ; calc_new_wait_times
    ; wait_before_zc_scan

; Run 3 = A(p-on) + B(n-pwm) - comparator C evaluated
; Out_cC changes from low to high
run3:
    call wait_for_comp_out_high
    ; setup_comm_wait
    ; evaluate_comparator_integrity
    call wait_for_comm
    call comm3_comm4
    call calc_next_comm_period
    ; wait_advance_timing
    ; calc_new_wait_times
    ; wait_before_zc_scan

; Run 4 = C(p-on) + B(n-pwm) - comparator A evaluated
; Out_cA changes from high to low
run4:
    call wait_for_comp_out_low
    ; setup_comm_wait
    ; evaluate_comparator_integrity
    call wait_for_comm
    call comm4_comm5
    call calc_next_comm_period
    ; wait_advance_timing
    ; calc_new_wait_times
    ; wait_before_zc_scan

; Run 5 = C(p-on) + A(n-pwm) - comparator B evaluated
; Out_cB changes from low to high
run5:
    call wait_for_comp_out_high
    ; setup_comm_wait
    ; evaluate_comparator_integrity
    call wait_for_comm
    call comm5_comm6
    call calc_next_comm_period
    ; wait_advance_timing
    ; calc_new_wait_times
    ; wait_before_zc_scan

; Run 6 = B(p-on) + A(n-pwm) - comparator C evaluated
; Out_cC changes from high to low
run6:
    call wait_for_comp_out_low
    ; setup_comm_wait
    ; evaluate_comparator_integrity
    call wait_for_comm
    call comm6_comm1
    call calc_next_comm_period
    call scheduler_run
    ; wait_advance_timing
    ; calc_new_wait_times
    ; wait_before_zc_scan

    ; Check if it is startup phases
    jnb  Flag_Initial_Run_Phase, normal_run_checks
    jnb  Flag_Startup_Phase, initial_run_phase

    ; Startup phase
    mov  Pwm_Limit, Pwm_Limit_Beg       ; Set initial max power
    mov  Pwm_Limit_By_Rpm, Pwm_Limit_Beg; Set initial max power
    clr  C
    mov  A, Startup_Cnt                 ; Load startup counter
    subb A, #24                         ; Is counter above requirement?
    jnc  startup_phase_done

    jnb  Flag_Rcp_Stop, run1            ; If pulse is above stop value - Continue to run
    sjmp exit_run_mode

startup_phase_done:
    ; Clear startup phase flag & remove pwm limits
    clr  Flag_Startup_Phase

initial_run_phase:
    ; If it is a direction change - branch
    jb   Flag_Dir_Change_Brake, normal_run_checks

    ; Decrement startup rotation count
    mov  A, Initial_Run_Rot_Cntd
    dec  A
    ; Check number of initial rotations
    jz   initial_run_phase_done         ; Branch if counter is zero

    mov  Initial_Run_Rot_Cntd, A        ; Not zero - store counter

    jnb  Flag_Rcp_Stop, run1            ; Check if pulse is below stop value
    jb   Flag_Pgm_Bidir, run1           ; Check if bidirectional operation

    sjmp exit_run_mode

initial_run_phase_done:
    clr  Flag_Initial_Run_Phase         ; Clear initial run phase flag

    ; Lift startup power restrictions
    ; Temperature protection acts until this point
    ; as a max startup power limiter.
    ; This plus the power limits applied in set_pwm_limit function
    ; act as a startup power limiter to protect the esc and the motor
    ; during startup, jams produced after crashes and desyncs recovery
    mov  Pwm_Limit, #255                ; Reset temperature level pwm limit
    mov  Temp_Pwm_Level_Setpoint, #255  ; Reset temperature level setpoint

    setb Flag_Motor_Started             ; Set motor started
    jmp  run1                           ; Continue with normal run

normal_run_checks:
    ; Reset stall count
    mov  Startup_Stall_Cnt, #0
    setb Flag_Motor_Running

    jnb  Flag_Rcp_Stop, run6_check_bidir ; Check if stop
    jb   Flag_Pgm_Bidir, run6_check_timeout ; Check if bidirectional operation

    mov  Temp2, #Pgm_Brake_On_Stop      ; Check if using brake on stop
    mov  A, @Temp2
    jz   run6_check_timeout

    ; Exit run mode after 100ms when using brake on stop
    clr  C
    mov  A, Rcp_Stop_Cnt                ; Load stop RC pulse counter value
    subb A, #3                          ; Is number of stop RC pulses above limit?
    jnc  exit_run_mode                  ; Yes - exit run mode

run6_check_timeout:
    ; Exit run mode immediately if timeout
    mov  A, Rcp_Timeout_Cntd            ; Load RC pulse timeout counter value
    jz   exit_run_mode                  ; If it is zero - go back to wait for power on

run6_check_bidir:
    jb   Flag_Pgm_Bidir, run6_bidir     ; Check if bidirectional operation

run6_check_speed:
    clr  C
    mov  A, Comm_Period4x_H             ; Is Comm_Period4x below minimum speed?
    subb A, #0F0h                       ; Default minimum speed (~1330 erpm)
    jnc  exit_run_mode                  ; Yes - exit run mode
    jmp  run1                           ; No - go back to run 1

run6_bidir:
    ; Check if direction change braking is in progress
    jb   Flag_Dir_Change_Brake, run6_bidir_braking

    ; Check if actual rotation direction matches force direction
    jb   Flag_Motor_Dir_Rev, run6_bidir_check_reversal
    jb   Flag_Rcp_Dir_Rev, run6_bidir_reversal
    sjmp run6_check_speed

run6_bidir_check_reversal:
    jb   Flag_Rcp_Dir_Rev, run6_check_speed

run6_bidir_reversal:
    ; Initiate direction and start braking
    setb Flag_Dir_Change_Brake          ; Set brake flag
    mov  Pwm_Limit_By_Rpm, Pwm_Limit_Beg; Set max power while braking to initial power limit
    jmp  run4                           ; Go back to run 4,thereby changing force direction

run6_bidir_braking:
    mov  Pwm_Limit_By_Rpm, Pwm_Limit_Beg; Set max power while braking to initial power limit

    clr  C
    mov  A, Comm_Period4x_H             ; Is Comm_Period4x below minimum speed?
    subb A, #40h                        ; Bidirectional braking termination speed (~5000 erpm)
    jc   run6_bidir_continue            ; No - continue braking

    ; Braking done, set new spinning direction
    clr  Flag_Dir_Change_Brake          ; Clear braking flag
    mov  C, Flag_Rcp_Dir_Rev            ; Read force direction
    mov  Flag_Motor_Dir_Rev, C          ; Set spinning direction
    setb Flag_Initial_Run_Phase
    mov  Initial_Run_Rot_Cntd, #18

run6_bidir_continue:
    jmp  run1                           ; Go back to run 1

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Exit run mode and power off
;
; Happens on normal stop (RC pulse == 0) or comparator timeout
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
exit_run_mode_on_timeout:
    jb   Flag_Motor_Running, exit_run_mode
    inc  Startup_Stall_Cnt              ; Increment stall count if motors did not properly start

exit_run_mode:
    ; Disable all interrupts (they will be disabled for a while, be aware)
    clr  IE_EA

    call switch_power_off
    mov  Flags0, #0                     ; Clear run time flags (in case they are used in interrupts)
    mov  Flags1, #0

IF MCU_TYPE == MCU_BB2 or MCU_TYPE == MCU_BB51
    Set_MCU_Clk_24MHz

    ; Scale DShot criteria for 24MHz
    setb C
    rrca DShot_Timer_Preset             ; Scale sync timer preset

    clr  C
    rrca DShot_Frame_Length_Thr         ; Scale frame length criteria

    clr  C
    rrca DShot_Pwm_Thr                  ; Scale pulse width criteria

    ; Scale DShot telemetry for 24MHz
    xcha DShot_GCR_Pulse_Time_1, DShot_GCR_Pulse_Time_1_Tmp
    xcha DShot_GCR_Pulse_Time_2, DShot_GCR_Pulse_Time_2_Tmp
    xcha DShot_GCR_Pulse_Time_3, DShot_GCR_Pulse_Time_3_Tmp

    mov  DShot_GCR_Start_Delay, #DSHOT_TLM_START_DELAY
ENDIF

    ; Check if RCP is zero, then it is a normal stop or signal timeout
    jb   Flag_Rcp_Stop, exit_run_mode_no_stall

    ; It is a stall!
    ; Signal stall
    setb Flag_Stall_Notify

    ; Check max consecutive stalls and exit if stall counter > 3
    clr  C
    mov  A, Startup_Stall_Cnt
    subb A, #3
    jnc  exit_run_mode_is_stall

    ; At this point there was a desync event, and a new try is to be done.
    ; The program will jump to motor_start. Interrupts are disabled at this
    ; point so it is safe to jump to motor start, where a new initial state
    ; will be set

    call wait100ms                      ; Wait for a bit between stall restarts

    ljmp motor_start                    ; Go back and try starting motors again

exit_run_mode_is_stall:
    ; Enable all interrupts (disabled above, in exit_run_mode)
    setb IE_EA

    ; Clear extended DSHOT telemetry flag if turtle mode is not active
    ; This flag is also used for EDT safety arm flag
    ; We don't want to deactivate extended telemetry during turtle mode
    ; Extended telemetry flag is important because it is involved in
    ; EDT safety feature. We don't want to disable EDT arming during
    ; turtle mode.
    jb Flag_User_Reverse_Requested, exit_run_mode_is_stall_beep
    clr Flag_Ext_Tele

exit_run_mode_is_stall_beep:
    ; Stalled too many times
    clr  IE_EA
    call beep_motor_stalled
    setb IE_EA

    ljmp arming_begin                   ; Go back and wait for arming

exit_run_mode_no_stall:
    ; Enable all interrupts (disabled above, in exit_run_mode)
    setb IE_EA

    ; Clear extended DSHOT telemetry flag if turtle mode is not active
    ; This flag is also used for EDT safety arm flag
    ; We don't want to deactivate extended telemetry during turtle mode
    ; Extended telemetry flag is important because it is involved in
    ; EDT safety feature. We don't want to disable EDT arming during
    ; turtle mode.
    jb Flag_User_Reverse_Requested, exit_run_mode_no_stall_no_beep
    clr Flag_Ext_Tele

exit_run_mode_no_stall_no_beep:
    ; Clear stall counter
    mov  Startup_Stall_Cnt, #0

    mov  Temp1, #Pgm_Brake_On_Stop      ; Check if using brake on stop
    mov  A, @Temp1
    jz   exit_run_mode_brake_done

    A_Com_Fet_On                        ; Brake on stop
    B_Com_Fet_On
    C_Com_Fet_On

exit_run_mode_brake_done:
    ljmp wait_for_start                 ; Go back to wait for power on

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Reset
;
; Should execution ever reach this point the ESC will be reset,
; as code flash after offset 1A00 is used for EEPROM storage
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
CSEG AT CSEG_RESET
reset:
    ljmp pgm_start

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Bootloader
;
; Include source code for BLHeli bootloader
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;CSEG AT 1C00h
$include (BLHeliBootLoad.inc)

END
