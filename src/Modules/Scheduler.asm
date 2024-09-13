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
; Scheduler
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Divider of scheduler counter as a power of 2 number.
;
; This macro exists for convenience to easily change scheduler step time.
; In the table below you can find valid values for this parameter.
;
; Value     Step    Cycle (8 steps)     Zero crossing scan interference
; ---------------------------------------------------------------------
; 0         16ms    128ms               Medium - High
; 1         32ms    256ms               Medium
; 2         64ms    512ms               Low
; 3         128ms   1024ms              Low
; 4         256ms   2048ms              Low
; 5         512ms   4096ms              Low
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
SCHEDULER_COUNTER_DIVIDER_POW2  EQU 3

; Bitmask to get the remainder of dividing a number by 8
MASK_REMAINDER_DIV8             EQU ((001h SHL SCHEDULER_COUNTER_DIVIDER_POW2) - 001h)

; Mask to get the scheduler step
MASK_STEP                       EQU (007h SHL SCHEDULER_COUNTER_DIVIDER_POW2)

; Scheduler steps for steps 1, 3, 5
STEP1_STATUS_FRAME              EQU (001h SHL SCHEDULER_COUNTER_DIVIDER_POW2)
STEP3_DEBUG1_FRAME              EQU (003h SHL SCHEDULER_COUNTER_DIVIDER_POW2)
STEP5_DEBUG2_FRAME              EQU (005h SHL SCHEDULER_COUNTER_DIVIDER_POW2)

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Scheduler
;
; Each step is 128ms, a complete cycle is 1024ms (8 steps)
;
; ReqSch00:   - Steps even [0, 2, 4, 6]
; ReqSch01:       - Update temperature setpoint on every even step
; ReqSch02:       - [TELEMETRY] Send demag metric frame
; ReqSch03:   - Steps odd [1, 3, 5, 7]
; ReqSch04:       - Update temperature PWM limit on every odd step
; ReqSch06:       - Case step 1
; ReqSch07:           - [TELEMETRY] Send status frame
; ReqSch08:       - Case step 3
; ReqSch09:           - [TELEMETRY] Send debug1 frame
; ReqSch10:       - Case step 5
; ReqSch11:           - [TELEMETRY] Send debug2 frame
; ReqSch12:       - Case step 7
; ReqSch13:           - [TELEMETRY] Send temperature frame
; ReqSch14:       - Start new ADC conversion after every odd step
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

scheduler_run:
    ; Exit if not 16ms elapsed, otherwise start schedule
    jbc  Flag_16ms_Elapsed, scheduler_check_time
    ret

scheduler_check_time:
    ; Increment Scheduler Counter
    inc  Scheduler_Counter

    ; Scheduler cycle defined by SCHEDULER_COUNTER_DIVIDER_POW2
    ; Get the remainder of dividing Scheduler_Counter
    mov A, Scheduler_Counter
    anl A, #MASK_REMAINDER_DIV8
    jz scheduler_start

    ; 128ms not fully elapsed so do nothing
    ret

scheduler_start:
    ; Choose between odd or even steps
    mov  A, Scheduler_Counter
    jb   ACC.SCHEDULER_COUNTER_DIVIDER_POW2, scheduler_steps_odd

scheduler_steps_even:
;**** **** **** **** **** **** **** **** **** **** **** **** ****
; UPDATE TEMPERATURE SETPOINT
;**** **** **** **** **** **** **** **** **** **** **** **** ****

    ; Check temp protection: skip when protection is disabled
    mov  A, Temp_Prot_Limit
    jz   scheduler_steps_even_demag_metric_frame

    ; Set setpoint maximum value
    mov  Temp_Pwm_Level_Setpoint, #255

    ; Check TEMP_LIMIT in Base.inc and make calculations to understand temperature readings
    ; Is temperature reading below 256?
    ;
    ; On BB1 & BB21:
    ; - Using external voltage regulator and vdd 3.3V as ADC reference -> ADC 10bit value corresponding to about 25ºC
    ; - Using external voltage regulator and internal 1.65V as ADC reference -> ADC 10bit value corresponding to about 0ºC
    ;
    ; On BB51:
    ; - Using external voltage regulator and internal 1.65V as ADC reference -> ADC 10bit value corresponding to about 0ºC
    mov  A, ADC0H                       ; Load temp hi
    jz   scheduler_steps_even_demag_metric_frame ; Temperature below 25ºC (on 2S+ (BB1,BB2)) and below 0ºC (on 1S (BB1,BB21),BB51) do not update setpoint

    mov  A, ADC0L                       ; Load temp lo

    clr  C
    subb A, Temp_Prot_Limit             ; Is temperature below first limit?
    jc   scheduler_steps_even_demag_metric_frame ; Yes - Jump to next scheduler

    mov  Temp_Pwm_Level_Setpoint, #200  ; No - update pwm limit (about 80%)

    subb A, #(TEMP_LIMIT_STEP / 2)      ; Is temperature below second limit
    jc   scheduler_steps_even_demag_metric_frame ; Yes - Jump to next scheduler

    mov  Temp_Pwm_Level_Setpoint, #150  ; No - update pwm limit (about 60%)

    subb A, #(TEMP_LIMIT_STEP / 2)      ; Is temperature below third limit
    jc   scheduler_steps_even_demag_metric_frame ; Yes - Jump to next scheduler

    mov  Temp_Pwm_Level_Setpoint, #100  ; No - update pwm limit (about 40% allowing landing)

    subb A, #(TEMP_LIMIT_STEP / 2)      ; Is temperature below final limit
    jc   scheduler_steps_even_demag_metric_frame ; Yes - Jump to next scheduler

    mov  Temp_Pwm_Level_Setpoint, #50   ; No - update pwm limit (about 20% forced landing)
    ; Zero pwm cannot be set because of set_pwm_limit algo restrictions
    ; Otherwise hard stuttering is produced


scheduler_steps_even_demag_metric_frame:
    ; Check if extended telemetry is enabled, otherwise we are done here.
    jb   Flag_Ext_Tele, scheduler_steps_even_demag_metric_frame_prepare

    ; No more work to do
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; [TELEMETRY] SEND DEMAG METRIC FRAME
;**** **** **** **** **** **** **** **** **** **** **** **** ****
scheduler_steps_even_demag_metric_frame_prepare:
    mov  Ext_Telemetry_L, Demag_Detected_Metric ; Set telemetry low value to demag metric data
    mov  Ext_Telemetry_H, #0Ch          ; Set telemetry high value to demag metric frame ID

    ; No more work to do
    ret

scheduler_steps_odd:
;**** **** **** **** **** **** **** **** **** **** **** **** ****
; UPDATE TEMPERATURE PWM LIMIT EVERY 256ms (ON ODD STEP)
;**** **** **** **** **** **** **** **** **** **** **** **** ****

    ; Check if temp protection is enabled, otherwise continue with odd step
    mov  A, Temp_Prot_Limit
    jz   scheduler_steps_odd_choose_step

    ; PWM limit is updated one unit at a time to avoid abrupt PWM changes
    ; resulting in current spikes, that may damage motor/ESC.
    ; Compare pwm limit to setpoint
    clr  C
    mov  A, Pwm_Limit
    subb A, Temp_Pwm_Level_Setpoint
    jz   scheduler_steps_odd_choose_step ; pwm limit == setpoint -> next
    jc   scheduler_steps_odd_temp_pwm_limit_inc ; pwm limit < setpoint -> increase pwm limit

scheduler_steps_odd_temp_pwm_limit_dec:
    ; Decrease pwm limit
    dec  Pwm_Limit

    ; Continue with odd scheduler step selection
    sjmp scheduler_steps_odd_choose_step

scheduler_steps_odd_temp_pwm_limit_inc:
    ; Increase pwm limit
    inc  Pwm_Limit

; Run speciffic odd scheduler step
scheduler_steps_odd_choose_step:
    ; Check if extended telemetry is enabled, otherwise skip frame generation
    jnb  Flag_Ext_Tele, scheduler_steps_odd_restart_ADC

    ; Get scheduler step
    mov  A, Scheduler_Counter
    anl  A, #MASK_STEP

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; [TELEMETRY] SEND STATUS FRAME
;**** **** **** **** **** **** **** **** **** **** **** **** ****
scheduler_steps_odd_status_frame:
    cjne A, #STEP1_STATUS_FRAME, scheduler_steps_odd_debug1_frame

    ; if (Demag_Detected_Metric_Max >= 120)
    ;   stat.demagMetricMax = (Demag_Detected_Metric_Max - 120) / 9
    ; else
    ;   stat.demagMetricMax = 0
    clr  C
    mov  A, Demag_Detected_Metric_Max
    subb A, #120                        ; 120: substract the minimum
    jnc  scheduler_steps_odd_status_frame_max_load
    clr  A
    sjmp scheduler_steps_odd_status_frame_max_loaded

scheduler_steps_odd_status_frame_max_load:
    mov  B, #9
    div  AB                             ; Ranges: [0 - 135] / 9 == [0 - 15]

scheduler_steps_odd_status_frame_max_loaded:
    ; Load flags
    mov  C, Flag_Demag_Notify
    mov  ACC.7, C
    mov  C, Flag_Desync_Notify
    mov  ACC.6, C
    mov  C, Flag_Stall_Notify
    mov  ACC.5, C

    ; Data loaded clear flags
    clr  Flag_Demag_Notify
    clr  Flag_Desync_Notify
    clr  Flag_Stall_Notify
    mov  Demag_Detected_Metric_Max, #0  ; Reset the Max metric so the next value would reflect maximum seen during the time in between STATUS telemetry packets

    ; Load status frame
    mov  Ext_Telemetry_L, A             ; Set telemetry low value to status data
    mov  Ext_Telemetry_H, #0Eh          ; Set telemetry high value to status frame ID

    ; Now restart ADC conversion
    Restart_Adc

    ; Nothing else to do
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; [TELEMETRY] SEND DEBUG1 FRAME
;**** **** **** **** **** **** **** **** **** **** **** **** ****
scheduler_steps_odd_debug1_frame:
    cjne A, #STEP3_DEBUG1_FRAME, scheduler_steps_odd_debug2_frame

    ; Stub for debug 1
    mov  Ext_Telemetry_L, #088h         ; Set telemetry low value
    mov  Ext_Telemetry_H, #08h          ; Set telemetry high value to debug1 frame ID

    ; Now restart ADC conversion
    Restart_Adc

    ; Nothing else to do
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; [TELEMETRY] SEND DEBUG2 FRAME
;**** **** **** **** **** **** **** **** **** **** **** **** ****
scheduler_steps_odd_debug2_frame:
    cjne A, #STEP5_DEBUG2_FRAME, scheduler_steps_odd_temperature_frame

    ; Stub for debug 2
    mov  Ext_Telemetry_L, #0AAh         ; Set telemetry low value
    mov  Ext_Telemetry_H, #0Ah          ; Set telemetry high value to debug2 frame ID

    ; Now restart ADC conversion
    Restart_Adc

    ; Nothing else to do
    ret

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; [TELEMETRY] SEND TEMPERATURE FRAME
;**** **** **** **** **** **** **** **** **** **** **** **** ****
scheduler_steps_odd_temperature_frame:
    ; If step is not 1, 3 or 5 it has to be 7, so cjmp is not necessary
    ; cjne A, #STEP7_TEMPERATURE_FRAME, scheduler_steps_odd_restart_ADC

;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Power rating only applies to BB21 because voltage references behave diferently
; depending on an external voltage regulator is used or not.
; For BB51 (MCU_TYPE == 2) 1s power rating code path is mandatory
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
IF MCU_TYPE == MCU_BB2
    mov  Temp1, #Pgm_Power_Rating
    cjne @Temp1, #01h, scheduler_steps_odd_temperature_frame_power_rating_2s
ENDIF

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; ON BB51 and BB1, BB2 at 1S, all using internal 1.65V ADC reference
;**** **** **** **** **** **** **** **** **** **** **** **** ****
scheduler_steps_odd_temperature_frame_power_rating_1s:
    mov  A, ADC0H
    jnz  scheduler_steps_odd_temperature_frame_pr1s_temperature_above_0

scheduler_steps_odd_temperature_frame_pr1s_temperature_below_0:
    ; If Hi Byte is not 0x01 we are definetly below 0, thus
    ; clamp to 0.
    clr  A
    sjmp scheduler_steps_odd_temperature_frame_temp_load

scheduler_steps_odd_temperature_frame_pr1s_temperature_above_0:
    ; Prepare extended telemetry temperature value for next telemetry transmission
    ; On BB51 they hi byte is always 1 if the temperature is above 0ºC.
    ; In fact the value is 0x0114 at 0ºC, thus we ignore the hi byte and normalize
    ; the low byte to
    mov  A, ADC0L
    subb A, #14h
    sjmp scheduler_steps_odd_temperature_frame_temp_load

scheduler_steps_odd_temperature_frame_power_rating_2s:
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; ON BB1, BB2 at more than 1S, using vdd V3.3 ADC reference
;
; Prepare extended telemetry temperature value for next telemetry transmission
; Check value above or below 20ºC - this is an approximation ADCOH having a value
; of 0x01 equals to around 22.5ºC.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
    mov  A, ADC0H
    jnz  scheduler_steps_odd_temperature_frame_pr2s_temperature_above_20

scheduler_steps_odd_temperature_frame_pr2s_temperature_below_20:
    ; Value below 20ºC -> to code between 0-20
    mov  A, ADC0L
    clr  C
    subb A, #(255 - 20)
    jnc  scheduler_steps_odd_temperature_frame_temp_load

    ; Value below 0ºC -> clamp to 0
    clr  A
    sjmp scheduler_steps_odd_temperature_frame_temp_load

scheduler_steps_odd_temperature_frame_pr2s_temperature_above_20:
    ; Value above 20ºC -> to code between 20-255
    mov  A, ADC0L                       ; This is an approximation: 9 ADC steps @10 Bit are 10 degrees
    add  A, #20

scheduler_steps_odd_temperature_frame_temp_load:
    mov  Ext_Telemetry_L, A             ; Set telemetry low value with temperature data
    mov  Ext_Telemetry_H, #02h          ; Set telemetry high value on first repeated dshot coding partition

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; START NEW ADC CONVERSION
;**** **** **** **** **** **** **** **** **** **** **** **** ****
scheduler_steps_odd_restart_ADC:
    ; Restart ADC conversion
    Restart_Adc

    ; Nothing else to do
    ret
