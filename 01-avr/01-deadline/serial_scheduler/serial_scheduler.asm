; ATmega8, AVRA, 8 MHz, USART 500000 baud 8N1.
; Timing contract: first OUT UDR occurs within 4 CPU cycles of its deadline.
; Timer2 starts PHASE cycles after Timer1. RX is polled, including during TX.
; T1 HHHH / T2 HHHH / S1 text / S2 text / R. LF terminates a command.
; Reply !OK CRLF or !ERR CRLF. At most one outstanding command.
.include "m8def.inc"
.equ F_CPU=8000000
.equ TIMER1_INTERVAL=16000
.equ TIMER2_INTERVAL=24000
.equ LEAD=512
.equ GAP=2048
.equ MAX_PERIOD=57344
.dseg
.org 0x60
period1: .byte 2
period2: .byte 2
length1: .byte 1
length2: .byte 1
phase: .byte 2
due1: .byte 2
due2: .byte 2
cmd_len: .byte 1
cmd_ready: .byte 1
cmd_bad: .byte 1
reply_pending: .byte 1
fault: .byte 1
.org 0x90
candidate: .byte 6
candidate_phase: .byte 2
.org 0xa0
text1: .byte 19
text2: .byte 19
.org 0xd0
command: .byte 32
.cseg
.org 0
 rjmp reset
.org OC1Aaddr
 rjmp timer_a
.org OC1Baddr
 rjmp timer_b
.org INT_VECTORS_SIZE
.macro SAVE
 push r0
 in r0,SREG
 push r0
 push r1
 clr r1
 push r16
 push r17
 push r18
 push r19
 push r20
 push r21
 push r22
 push r23
 push r24
 push r25
 push r26
 push r27
 push r28
 push r29
 push r30
 push r31
.endmacro
.macro RESTORE
 pop r31
 pop r30
 pop r29
 pop r28
 pop r27
 pop r26
 pop r25
 pop r24
 pop r23
 pop r22
 pop r21
 pop r20
 pop r19
 pop r18
 pop r17
 pop r16
 pop r1
 pop r0
 out SREG,r0
 pop r0
 reti
.endmacro
reset:
 cli
 ldi r16,high(RAMEND)
 out SPH,r16
 ldi r16,low(RAMEND)
 out SPL,r16
 clr r1
 ldi XL,0x60
 clr XH
 ldi r16,128
zero:
 st X+,r1
 dec r16
 brne zero
 ldi r16,low(TIMER1_INTERVAL)
 sts period1,r16
 ldi r16,high(TIMER1_INTERVAL)
 sts period1+1,r16
 ldi r16,low(TIMER2_INTERVAL)
 sts period2,r16
 ldi r16,high(TIMER2_INTERVAL)
 sts period2+1,r16
 ldi r16,4
 sts length1,r16
 sts length2,r16
 ldi r16,low(6*160+GAP)
 sts phase,r16
 ldi r16,high(6*160+GAP)
 sts phase+1,r16
 ldi ZL,low(TIMER1_STR*2)
 ldi ZH,high(TIMER1_STR*2)
 ldi XL,low(text1)
 clr XH
 rcall flash_copy
 ldi ZL,low(TIMER2_STR*2)
 ldi ZH,high(TIMER2_STR*2)
 ldi XL,low(text2)
 clr XH
 rcall flash_copy
 out UBRRH,r1
 ldi r16,(1<<U2X)
 out UCSRA,r16
 ldi r16,1
 out UBRRL,r16
 ldi r16,(1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
 out UCSRC,r16
 ldi r16,(1<<RXEN)|(1<<TXEN)
 out UCSRB,r16
 ; Validate compile-time defaults using the same rule as USART commands.
 ldi XL,low(period1)
 clr XH
 ldi ZL,low(candidate)
 clr ZH
 ldi r16,6
boot_stage:
 ld r17,X+
 st Z+,r17
 dec r16
 brne boot_stage
 rcall feasible
 brcc boot_valid
 rjmp boot_error
boot_valid:
 lds r16,candidate_phase
 sts phase,r16
 lds r16,candidate_phase+1
 sts phase+1,r16
 out TCCR1A,r1
 out TCNT1H,r1
 out TCNT1L,r1
 ldi r16,(1<<CS10)
 out TCCR1B,r16
 rcall arm_schedules
 ldi r16,(1<<OCIE1A)|(1<<OCIE1B)
 out TIMSK,r16
 sei
main:
 cli
 rcall receive
 sei
 lds r16,reply_pending
 tst r16
 breq check_line
 rcall try_reply
 rjmp main
check_line:
 lds r16,cmd_ready
 tst r16
 breq main
 rcall execute
 sts cmd_ready,r1
 sts cmd_len,r1
 sts cmd_bad,r1
 rjmp main
flash_copy:
 lpm r16,Z+
 st X+,r16
 tst r16
 brne flash_copy
 ret

; Timer interrupts wake early, then wait on their hardware compare flag.
; The four-cycle loop has four possible exit phases. No other ISR may run.
timer_a:
 SAVE
 lds r24,due1
 lds r25,due1+1
 subi r24,3
 sbci r25,0
 out OCR1AH,r25
 out OCR1AL,r24
 ldi r16,(1<<OCF1A)
 out TIFR,r16
 ldi YL,low(text1)
 clr YH
 ld r20,Y+
coarse_a:
 in r18,TCNT1L
 in r19,TCNT1H
 movw r16,r24
 sub r16,r18
 sbc r17,r19
 tst r17
 brne poll_rx_a
 cpi r16,96
 brlo wait_a
poll_rx_a:
 rcall receive
 rjmp coarse_a
wait_a:
 in r16,TIFR
 sbrs r16,OCF1A
 rjmp wait_a
 out UDR,r20
 lds r24,due1
 lds r25,due1+1
 lds r18,period1
 lds r19,period1+1
 add r24,r18
 adc r25,r19
 sts due1,r24
 sts due1+1,r25
 subi r24,low(LEAD)
 sbci r25,high(LEAD)
 out OCR1AH,r25
 out OCR1AL,r24
 ldi r16,(1<<OCF1A)
 out TIFR,r16
 rcall send_tail
 RESTORE
timer_b:
 SAVE
 lds r24,due2
 lds r25,due2+1
 subi r24,3
 sbci r25,0
 out OCR1BH,r25
 out OCR1BL,r24
 ldi r16,(1<<OCF1B)
 out TIFR,r16
 ldi YL,low(text2)
 clr YH
 ld r20,Y+
coarse_b:
 in r18,TCNT1L
 in r19,TCNT1H
 movw r16,r24
 sub r16,r18
 sbc r17,r19
 tst r17
 brne poll_rx_b
 cpi r16,96
 brlo wait_b
poll_rx_b:
 rcall receive
 rjmp coarse_b
wait_b:
 in r16,TIFR
 sbrs r16,OCF1B
 rjmp wait_b
 out UDR,r20
 lds r24,due2
 lds r25,due2+1
 lds r18,period2
 lds r19,period2+1
 add r24,r18
 adc r25,r19
 sts due2,r24
 sts due2+1,r25
 subi r24,low(LEAD)
 sbci r25,high(LEAD)
 out OCR1BH,r25
 out OCR1BL,r24
 ldi r16,(1<<OCF1B)
 out TIFR,r16
 rcall send_tail
 RESTORE
send_tail:
 ld r20,Y+
 tst r20
 breq drain
byte_wait:
 rcall receive
 sbis UCSRA,UDRE
 rjmp byte_wait
 out UDR,r20
 rjmp send_tail
drain:
 rcall receive
 sbis UCSRA,TXC
 rjmp drain
 ldi r16,(1<<U2X)|(1<<TXC)
 out UCSRA,r16
 ret

; Polling RX writes only the command accumulator; preserves r20 and Y.
; Host waits for a reply before its next command; RX is polled in early waits.
receive:
 sbis UCSRA,RXC
 ret
 in r16,UCSRA
 in r17,UDR
 andi r16,(1<<FE)|(1<<DOR)|(1<<PE)
 breq rx_ok
 ldi r16,1
 sts cmd_bad,r16
rx_ok:
 lds r16,cmd_ready
 tst r16
 brne rx_end
 cpi r17,10
 breq rx_finish
 cpi r17,13
 breq rx_end
 lds r16,cmd_len
 cpi r16,31
 brsh rx_bad
 cpi r17,32
 brlo rx_bad
 cpi r17,127
 brsh rx_bad
 ldi ZL,low(command)
 clr ZH
 add ZL,r16
 adc ZH,r1
 st Z,r17
 inc r16
 sts cmd_len,r16
rx_end:
 ret
rx_bad:
 ldi r16,1
 sts cmd_bad,r16
 ret
rx_finish:
 ldi r16,1
 sts cmd_ready,r16
 ret

; Call with interrupts disabled. Counter is NEVER reset or stopped.
; Separate launch phases: epoch+T1 and epoch+PHASE+T2.
arm_schedules:
 in r18,TCNT1L
 in r19,TCNT1H
 lds r24,period1
 lds r25,period1+1
 add r24,r18
 adc r25,r19
 sts due1,r24
 sts due1+1,r25
 subi r24,low(LEAD)
 sbci r25,high(LEAD)
 out OCR1AH,r25
 out OCR1AL,r24
 lds r24,period2
 lds r25,period2+1
 add r24,r18
 adc r25,r19
 lds r16,phase
 lds r17,phase+1
 add r24,r16
 adc r25,r17
 sts due2,r24
 sts due2+1,r25
 subi r24,low(LEAD)
 sbci r25,high(LEAD)
 out OCR1BH,r25
 out OCR1BL,r24
 ldi r16,(1<<OCF1A)|(1<<OCF1B)
 out TIFR,r16
 ret

execute:
 lds r16,cmd_bad
 tst r16
 breq parse
 rjmp error
parse:
 lds r21,cmd_len
 cpi r21,1
 brne long_cmd
 lds r16,command
 cpi r16,'R'
 breq restart
 rjmp error
restart:
 cli
 rcall arm_schedules
 sei
 rjmp okay
long_cmd:
 cpi r21,3
 brsh parse_long
 rjmp error
parse_long:
 ldi XL,low(period1)
 clr XH
 ldi ZL,low(candidate)
 clr ZH
 ldi r16,6
stage:
 ld r17,X+
 st Z+,r17
 dec r16
 brne stage
 lds r23,command
 cpi r23,'P'
 brne single_parameter
 rjmp pair_command
single_parameter:
 lds r22,command+1
 cpi r22,'1'
 breq valid_channel
 cpi r22,'2'
 breq valid_channel
 rjmp error
valid_channel:
 lds r16,command+2
 cpi r16,' '
 breq valid_space
 rjmp error
valid_space:
 lds r23,command
 cpi r23,'T'
 breq parse_period
 cpi r23,'S'
 brne invalid_kind
 rjmp parse_string
invalid_kind:
 rjmp error
parse_period:
 cpi r21,7
 breq hex_start
 rjmp error
hex_start:
 ldi ZL,low(command+3)
 clr ZH
 clr r24
 clr r25
 ldi r21,4
hex_loop:
 ld r16,Z+
 rcall hex_digit
 brcc digit_ok
 rjmp error
digit_ok:
 lsl r24
 rol r25
 lsl r24
 rol r25
 lsl r24
 rol r25
 lsl r24
 rol r25
 or r24,r16
 dec r21
 brne hex_loop
 ldi XL,low(candidate)
 clr XH
 cpi r22,'1'
 breq store_period
 adiw XL,2
store_period:
 st X+,r24
 st X,r25
 rjmp validate
pair_command:
 cpi r21,11
 breq pair_length_ok
 rjmp error
pair_length_ok:
 lds r16,command+1
 cpi r16,' '
 breq pair_space1
 rjmp error
pair_space1:
 lds r16,command+6
 cpi r16,' '
 breq pair_space2
 rjmp error
pair_space2:
 ldi XL,low(candidate)
 clr XH
 ldi ZL,low(command+2)
 clr ZH
 ldi r22,2
pair_number:
 clr r24
 clr r25
 ldi r21,4
pair_digit:
 ld r16,Z+
 rcall hex_digit
 brcc pair_digit_ok
 rjmp error
pair_digit_ok:
 lsl r24
 rol r25
 lsl r24
 rol r25
 lsl r24
 rol r25
 lsl r24
 rol r25
 or r24,r16
 dec r21
 brne pair_digit
 st X+,r24
 st X+,r25
 adiw ZL,1
 dec r22
 brne pair_number
 rjmp validate
parse_string:
 subi r21,3
 cpi r21,17
 brlo string_ok
 rjmp error
string_ok:
 tst r21
 breq string_prefix_valid
 lds r16,command+3
 cpi r16,'!'
 brne string_prefix_valid
 rjmp error
string_prefix_valid:
 cpi r22,'1'
 brne string_two
 sts candidate+4,r21
 rjmp validate
string_two:
 sts candidate+5,r21
validate:
 rcall feasible
 brcc commit
 rjmp error
commit:
 ; Fewer than 300 cycles including rearming; shorter than LEAD.
 cli
 ldi XL,low(candidate)
 clr XH
 ldi ZL,low(period1)
 clr ZH
 ldi r16,8
commit_values:
 ld r17,X+
 st Z+,r17
 dec r16
 brne commit_values
 cpi r23,'S'
 brne rearm
 ldi XL,low(text1)
 clr XH
 cpi r22,'1'
 breq copy_new_text
 ldi XL,low(text2)
copy_new_text:
 ldi ZL,low(command+3)
 clr ZH
 tst r21
 breq terminate_text
copy_chars:
 ld r16,Z+
 st X+,r16
 dec r21
 brne copy_chars
terminate_text:
 ldi r16,13
 st X+,r16
 ldi r16,10
 st X+,r16
 st X,r1
rearm:
 rcall arm_schedules
 sei
okay:
 ldi r16,1
 sts reply_pending,r16
 ret
error:
 ldi r16,2
 sts reply_pending,r16
 ret

; Exact admission for this implementation's reserved-window policy:
; g=gcd(T1,T2); g >= (L1+L2+4)*160 + 2*GAP.
; PHASE=(L1+2)*160+GAP. Gaps reserve wakeup/ISR/command response time.
; The algorithm runs with timer interrupts enabled.
feasible:
 lds r24,candidate
 lds r25,candidate+1
 lds r18,candidate+2
 lds r19,candidate+3
 mov r16,r24
 or r16,r25
 breq infeasible
 mov r16,r18
 or r16,r19
 breq infeasible
 ldi r16,low(MAX_PERIOD+1)
 ldi r17,high(MAX_PERIOD+1)
 cp r24,r16
 cpc r25,r17
 brsh infeasible
 cp r18,r16
 cpc r19,r17
 brsh infeasible
 ; Euclid subtraction, finite for all accepted 16-bit inputs.
gcd_loop:
 cp r24,r18
 cpc r25,r19
 breq gcd_done
 brlo gcd_smaller
 sub r24,r18
 sbc r25,r19
 rjmp gcd_loop
gcd_smaller:
 sub r18,r24
 sbc r19,r25
 rjmp gcd_loop
gcd_done:
 ; Preserve gcd in r27:r26. cycles_for_length returns r19:r18.
 movw r26,r24
 lds r16,candidate+4
 rcall cycles_for_length
 subi r18,low(-GAP)
 sbci r19,high(-GAP)
 sts candidate_phase,r18
 sts candidate_phase+1,r19
 movw r24,r18
 lds r16,candidate+5
 rcall cycles_for_length
 subi r18,low(-GAP)
 sbci r19,high(-GAP)
 add r18,r24
 adc r19,r25
 cp r26,r18
 cpc r27,r19
 brlo infeasible
 clc
 ret
infeasible:
 sec
 ret
cycles_for_length:
 subi r16,-2
 ldi r17,160
 mul r16,r17
 movw r18,r0
 clr r1
 ret
hex_digit:
 cpi r16,'0'
 brlo not_hex
 cpi r16,'9'+1
 brlo decimal
 andi r16,0xdf
 cpi r16,'A'
 brlo not_hex
 cpi r16,'F'+1
 brsh not_hex
 subi r16,'A'-10
 clc
 ret
decimal:
 subi r16,'0'
 clc
 ret
not_hex:
 sec
 ret

; A six-byte response uses <= 960 serial cycles, plus bounded polling.
; Reserve 1400 cycles BEFORE each early compare interrupt.
try_reply:
 cli
 in r24,TCNT1L
 in r25,TCNT1H
 in r18,OCR1AL
 in r19,OCR1AH
 sub r18,r24
 sbc r19,r25
 ldi r16,low(1400)
 ldi r17,high(1400)
 cp r18,r16
 cpc r19,r17
 brlo no_reply
 in r18,OCR1BL
 in r19,OCR1BH
 sub r18,r24
 sbc r19,r25
 cp r18,r16
 cpc r19,r17
 brlo no_reply
 in r18,TIFR
 andi r18,(1<<OCF1A)|(1<<OCF1B)
 brne no_reply
 ; No timer deadline is reached during this bounded transmission.
 lds r16,reply_pending
 sts reply_pending,r1
 ldi YL,low(ok_text*2)
 ldi YH,high(ok_text*2)
 cpi r16,1
 breq reply_loop
 ldi YL,low(err_text*2)
 ldi YH,high(err_text*2)
reply_loop:
 movw r30,r28
 lpm r20,Z
 adiw YL,1
 tst r20
 breq reply_drain
reply_wait:
 sbis UCSRA,UDRE
 rjmp reply_wait
 out UDR,r20
 rjmp reply_loop
reply_drain:
 sbis UCSRA,TXC
 rjmp reply_drain
 ldi r16,(1<<U2X)|(1<<TXC)
 out UCSRA,r16
 sei
 ret
no_reply:
 sei
 ret
boot_error:
 ldi ZL,low(err_text*2)
 ldi ZH,high(err_text*2)
boot_error_byte:
 lpm r16,Z+
 tst r16
 breq invalid_defaults
boot_error_wait:
 sbis UCSRA,UDRE
 rjmp boot_error_wait
 out UDR,r16
 rjmp boot_error_byte
invalid_defaults:
 nop
 rjmp invalid_defaults
TIMER1_STR: .db "ping",13,10,0,0
TIMER2_STR: .db "pong",13,10,0,0
ok_text: .db "!OK",13,10,0
err_text: .db "!ERR",13,10,0,0
