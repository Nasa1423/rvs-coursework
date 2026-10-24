; ATmega8 / AVRA. Two schedules, USART command control, bounded queues.
; CPU must physically run at 8 MHz. USART 500000 baud 8N1.
; Hardware events and physical UART transmission are distinct timing points.
; Protocol: T1 HHHH | T2 HHHH | S1 text | S2 text | R | ? then LF.
; One outstanding command. Replies start !OK / !ERR. Payloads cannot start !.
.include "m8def.inc"
.equ F_CPU = 8000000
.equ TIMER1_INTERVAL = 16000
.equ TIMER2_INTERVAL = 24000
.equ MASK = 63
.dseg
.org 0x60
channel_one_period: .byte 2
channel_two_period: .byte 2
channel_one_length: .byte 1
channel_two_length: .byte 1
rx_head: .byte 1
rx_tail: .byte 1
rx_fault: .byte 1
ev_head: .byte 1
ev_tail: .byte 1
ev_fault: .byte 1
cmd_len: .byte 1
cmd_ready: .byte 1
cmd_bad: .byte 1
rx_discard: .byte 1
tx_busy: .byte 1
tx_pos: .byte 1
.org 0x100
rx_buffer: .byte 64
.org 0x140
event_queue: .byte 64
.org 0x180
channel_one_text: .byte 19
.org 0x194
channel_two_text: .byte 19
.org 0x1c0
tx_buffer: .byte 64
.org 0x200
command_buffer: .byte 32

.cseg
.org 0
 rjmp reset
.org OC1Aaddr
 rjmp on_channel_one
.org OC1Baddr
 rjmp on_channel_two
.org URXCaddr
 rjmp on_receive_byte
.org INT_VECTORS_SIZE

.macro SAVE
 push r16
 in r16,SREG
 push r16
 push r17
 push r18
 push r19
 push r30
 push r31
.endmacro
.macro RESTORE
 pop r31
 pop r30
 pop r19
 pop r18
 pop r17
 pop r16
 out SREG,r16
 pop r16
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
 ldi r16,18
clear_state:
 st X+,r1
 dec r16
 brne clear_state
 ldi r16,low(TIMER1_INTERVAL)
 sts channel_one_period,r16
 ldi r16,high(TIMER1_INTERVAL)
 sts channel_one_period+1,r16
 ldi r16,low(TIMER2_INTERVAL)
 sts channel_two_period,r16
 ldi r16,high(TIMER2_INTERVAL)
 sts channel_two_period+1,r16
 ldi r16,4
 sts channel_one_length,r16
 sts channel_two_length,r16
 ldi ZL,low(TIMER1_STR*2)
 ldi ZH,high(TIMER1_STR*2)
 ldi XL,low(channel_one_text)
 ldi XH,high(channel_one_text)
 rcall flash_copy
 ldi ZL,low(TIMER2_STR*2)
 ldi ZH,high(TIMER2_STR*2)
 ldi XL,low(channel_two_text)
 ldi XH,high(channel_two_text)
 rcall flash_copy
 ldi r16,(1<<DDB0)|(1<<DDB1)|(1<<DDB2)
 out DDRB,r16
 out PORTB,r1
 out UBRRH,r1
 ldi r16,1
 out UBRRL,r16
 ldi r16,(1<<U2X)
 out UCSRA,r16
 ldi r16,(1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
 out UCSRC,r16
 ldi r16,(1<<RXEN)|(1<<TXEN)|(1<<RXCIE)
 out UCSRB,r16
 out TCCR1B,r1
 out TCNT1H,r1
 out TCNT1L,r1
 ldi r16,high(TIMER1_INTERVAL)
 out OCR1AH,r16
 ldi r16,low(TIMER1_INTERVAL)
 out OCR1AL,r16
 ldi r16,high(TIMER2_INTERVAL)
 out OCR1BH,r16
 ldi r16,low(TIMER2_INTERVAL)
 out OCR1BL,r16
 ldi r16,(1<<COM1A0)|(1<<COM1B0)
 out TCCR1A,r16
 ldi r16,(1<<OCF1A)|(1<<OCF1B)
 out TIFR,r16
 ldi r16,(1<<OCIE1A)|(1<<OCIE1B)
 out TIMSK,r16
 ldi r16,(1<<CS10)
 out TCCR1B,r16
 sei
dispatch_loop:
 rcall read_command_byte
 rcall write_ready_byte
 lds r16,tx_busy
 tst r16
 brne dispatch_loop
 ; Timer messages have priority over replies. A bounded reply can delay
 ; messages, but the queue is drained before accepting another command.
 lds r16,ev_head
 lds r17,ev_tail
 cp r16,r17
 breq no_event
 ldi ZH,high(event_queue)
 mov ZL,r17
 subi ZL,-low(event_queue)
 ld r20,Z
 inc r17
 andi r17,MASK
 sts ev_tail,r17
 ldi ZL,low(channel_one_text)
 ldi ZH,high(channel_one_text)
 cpi r20,1
 breq event_string
 ldi ZL,low(channel_two_text)
 ldi ZH,high(channel_two_text)
event_string:
 rcall prepare_output
copy_event:
 ld r16,Z+
 st X+,r16
 tst r16
 brne copy_event
 rcall start_output
 rjmp dispatch_loop
no_event:
 lds r16,ev_fault
 tst r16
 breq check_command
 sts ev_fault,r1
 ldi ZL,low(err_queue*2)
 ldi ZH,high(err_queue*2)
 rcall reply_flash
 rjmp dispatch_loop
check_command:
 lds r16,cmd_ready
 tst r16
 breq dispatch_loop
 sts cmd_ready,r1
 rcall apply_command
 sts cmd_len,r1
 sts cmd_bad,r1
 rjmp dispatch_loop

; Nonblocking TX: only one byte per dispatch_loop-loop iteration.
write_ready_byte:
 lds r16,tx_busy
 tst r16
 breq tx_done
 sbis UCSRA,UDRE
 ret
 lds r17,tx_pos
 ldi ZH,high(tx_buffer)
 ldi ZL,low(tx_buffer)
 add ZL,r17
 adc ZH,r1
 ld r16,Z
 tst r16
 breq tx_finished
 out UDR,r16
 inc r17
 sts tx_pos,r17
 ret
tx_finished:
 sts tx_busy,r1
tx_done:
 ret
prepare_output:
 ldi XL,low(tx_buffer)
 ldi XH,high(tx_buffer)
 ret
start_output:
 sts tx_pos,r1
 ldi r16,1
 sts tx_busy,r16
 ret
reply_flash:
 rcall prepare_output
 rcall flash_copy
 rjmp start_output
flash_copy:
 lpm r16,Z+
 st X+,r16
 tst r16
 brne flash_copy
 ret

; RX ISR only buffers bytes. Framing/parity/overrun faults poison the line.
on_receive_byte:
 SAVE
 in r18,UCSRA
 in r16,UDR
 andi r18,(1<<FE)|(1<<DOR)|(1<<PE)
 breq rx_enqueue
 ldi r18,1
 sts rx_fault,r18
 rjmp rx_return
rx_enqueue:
 lds r18,rx_head
 mov r17,r18
 inc r17
 andi r17,MASK
 lds r19,rx_tail
 cp r17,r19
 breq rx_full
 ldi ZH,high(rx_buffer)
 mov ZL,r18
 st Z,r16
 sts rx_head,r17
 rjmp rx_return
rx_full:
 ldi r18,1
 sts rx_fault,r18
rx_return:
 RESTORE

read_command_byte:
 lds r16,cmd_ready
 tst r16
 breq rx_process
 ret
rx_process:
 ; Atomic exchange of fault flag; hardware timer keeps counting.
 in r19,SREG
 cli
 lds r18,rx_fault
 sts rx_fault,r1
 out SREG,r19
 tst r18
 breq rx_read
 ldi r18,1
 sts rx_discard,r18
 sts cmd_bad,r18
 sts cmd_len,r1
rx_read:
 lds r17,rx_tail
 lds r18,rx_head
 cp r17,r18
 breq receive_done
 ldi ZH,high(rx_buffer)
 mov ZL,r17
 ld r16,Z
 inc r17
 andi r17,MASK
 sts rx_tail,r17
 cpi r16,10
 breq line_end
 lds r18,rx_discard
 tst r18
 brne receive_done
 cpi r16,13
 breq receive_done
 cpi r16,32
 brlo bad_line
 cpi r16,127
 brsh bad_line
 lds r17,cmd_len
 cpi r17,31
 brsh bad_line
 ldi ZL,low(command_buffer)
 ldi ZH,high(command_buffer)
 add ZL,r17
 adc ZH,r1
 st Z,r16
 inc r17
 sts cmd_len,r17
 ret
bad_line:
 ldi r18,1
 sts cmd_bad,r18
 sts rx_discard,r18
 ret
line_end:
 sts rx_discard,r1
 ldi r18,1
 sts cmd_ready,r18
receive_done:
 ret

on_channel_one:
 SAVE
 in r18,OCR1AL
 in r19,OCR1AH
 lds r16,channel_one_period
 lds r17,channel_one_period+1
 add r18,r16
 adc r19,r17
 out OCR1AH,r19
 out OCR1AL,r18
 ldi r16,1
 rcall queue_event
 RESTORE
on_channel_two:
 SAVE
 in r18,OCR1BL
 in r19,OCR1BH
 lds r16,channel_two_period
 lds r17,channel_two_period+1
 add r18,r16
 adc r19,r17
 out OCR1BH,r19
 out OCR1BL,r18
 ldi r16,2
 rcall queue_event
 RESTORE
queue_event:
 lds r18,ev_head
 mov r17,r18
 inc r17
 andi r17,MASK
 lds r19,ev_tail
 cp r17,r19
 breq ev_full
 ldi ZH,high(event_queue)
 mov ZL,r18
 subi ZL,-low(event_queue)
 st Z,r16
 sts ev_head,r17
 ret
ev_full:
 ldi r17,1
 sts ev_fault,r17
 sbi PORTB,PB0
 ret

; Parser runs with interrupts enabled. Nothing in validation stops Timer1.
apply_command:
 lds r16,cmd_bad
 tst r16
 breq parse_start
 rjmp fail_input
parse_start:
 lds r21,cmd_len
 tst r21
 brne command_nonempty
 rjmp fail_syntax
command_nonempty:
 lds r20,command_buffer
 cpi r21,1
 brne long_command
 cpi r20,'R'
 breq restart
 cpi r20,'?'
 breq status_jump
 rjmp fail_syntax
status_jump:
 rjmp status
long_command:
 cpi r21,3
 brsh length_ok
 rjmp fail_syntax
length_ok:
 lds r22,command_buffer+1
 cpi r22,'1'
 breq channel_ok
 cpi r22,'2'
 breq channel_ok
 rjmp fail_syntax
channel_ok:
 lds r16,command_buffer+2
 cpi r16,' '
 breq separator_ok
 rjmp fail_syntax
separator_ok:
 cpi r20,'T'
 breq period_jump
 cpi r20,'S'
 breq string_jump
 rjmp fail_syntax
period_jump:
 rjmp set_period
string_jump:
 rjmp set_string

; Explicit restart sets both next deadlines from the SAME running-counter
; snapshot. A short critical section protects the AVR 16-bit TEMP latch.
restart:
 in r23,SREG
 cli
 in r18,TCNT1L
 in r19,TCNT1H
 lds r16,channel_one_period
 lds r17,channel_one_period+1
 add r16,r18
 adc r17,r19
 out OCR1AH,r17
 out OCR1AL,r16
 lds r16,channel_two_period
 lds r17,channel_two_period+1
 add r16,r18
 adc r17,r19
 out OCR1BH,r17
 out OCR1BL,r16
 ldi r16,(1<<OCF1A)|(1<<OCF1B)
 out TIFR,r16
 lds r16,ev_head
 sts ev_tail,r16
 sts ev_fault,r1
 cbi PORTB,PB0
 out SREG,r23
 rjmp success

set_period:
 cpi r21,7
 breq parse_hex
 rjmp fail_syntax
parse_hex:
 ldi ZL,low(command_buffer+3)
 ldi ZH,high(command_buffer+3)
 clr r24
 clr r25
 ldi r21,4
hex_loop:
 ld r16,Z+
 rcall hex_digit
 brcc hex_ok
 rjmp fail_syntax
hex_ok:
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
 lds r20,channel_one_length
 cpi r22,'1'
 breq validate_period
 lds r20,channel_two_length
validate_period:
 ; r25:r24 = proposed period, r20 = current payload length.
 rcall validate_load
 brcc period_admitted
 rjmp fail_load
period_admitted:
 ; Atomic two-byte publication, not a timer stop.
 in r23,SREG
 cli
 cpi r22,'1'
 brne commit_period2
 sts channel_one_period,r24
 sts channel_one_period+1,r25
 rjmp period_committed
commit_period2:
 sts channel_two_period,r24
 sts channel_two_period+1,r25
period_committed:
 out SREG,r23
 rjmp success

set_string:
 mov r20,r21
 subi r20,3
 cpi r20,17
 brlo string_length_ok
 rjmp fail_syntax
string_length_ok:
 tst r20
 breq string_prefix_ok
 lds r16,command_buffer+3
 cpi r16,'!'
 brne string_prefix_ok
 rjmp fail_syntax
string_prefix_ok:
 lds r24,channel_one_period
 lds r25,channel_one_period+1
 cpi r22,'1'
 breq validate_string
 lds r24,channel_two_period
 lds r25,channel_two_period+1
validate_string:
 rcall validate_load
 brcc string_admitted
 rjmp fail_load
string_admitted:
 ; ISR never reads strings; TX is idle and future messages snapshot here.
 ldi XL,low(channel_one_text)
 ldi XH,high(channel_one_text)
 cpi r22,'1'
 brne write_string2
 sts channel_one_length,r20
 rjmp write_string
write_string2:
 ldi XL,low(channel_two_text)
 ldi XH,high(channel_two_text)
 sts channel_two_length,r20
write_string:
 ldi ZL,low(command_buffer+3)
 ldi ZH,high(command_buffer+3)
 mov r21,r20
 tst r21
 breq string_end
string_copy:
 ld r16,Z+
 st X+,r16
 dec r21
 brne string_copy
string_end:
 ldi r16,13
 st X+,r16
 ldi r16,10
 st X+,r16
 st X,r1
 rjmp success

; Conservative admission: T >= max(4096, (payload_length + 2)*1024).
; Each timer consumes <= 15.625% of the ideal 500 kbaud TX bandwidth.
; This is a sufficient operating envelope, NOT an exact feasibility oracle.
validate_load:
 mov r18,r20
 subi r18,-2
 lsl r18
 lsl r18                  ; high byte of (length+2)*1024
 cpi r18,16
 brsh minimum_ready
 ldi r18,16
minimum_ready:
 cp r25,r18              ; lower byte of bound is zero
 brlo inadmissible
 clc
 ret
inadmissible:
 sec
 ret
hex_digit:
 cpi r16,'0'
 brlo hex_invalid
 cpi r16,'9'+1
 brlo hex_decimal
 andi r16,0xDF
 cpi r16,'A'
 brlo hex_invalid
 cpi r16,'F'+1
 brsh hex_invalid
 subi r16,'A'-10
 clc
 ret
hex_decimal:
 subi r16,'0'
 clc
 ret
hex_invalid:
 sec
 ret

status:
 rcall prepare_output
 ldi ZL,low(status1*2)
 ldi ZH,high(status1*2)
 rcall append_flash
 lds r16,channel_one_period+1
 rcall hex_byte
 lds r16,channel_one_period
 rcall hex_byte
 ldi ZL,low(status2*2)
 ldi ZH,high(status2*2)
 rcall append_flash
 lds r16,channel_two_period+1
 rcall hex_byte
 lds r16,channel_two_period
 rcall hex_byte
 ldi ZL,low(status3*2)
 ldi ZH,high(status3*2)
 rcall append_flash
 lds r16,channel_one_length
 rcall hex_byte
 ldi ZL,low(status4*2)
 ldi ZH,high(status4*2)
 rcall append_flash
 lds r16,channel_two_length
 rcall hex_byte
 ldi r16,13
 st X+,r16
 ldi r16,10
 st X+,r16
 st X,r1
 rjmp start_output
append_flash:
 lpm r16,Z+
 tst r16
 breq appended
 st X+,r16
 rjmp append_flash
appended:
 ret
hex_byte:
 mov r17,r16
 swap r16
 andi r16,15
 rcall hex_out
 mov r16,r17
 andi r16,15
hex_out:
 cpi r16,10
 brlo hex_out_decimal
 subi r16,-('A'-10)
 st X+,r16
 ret
hex_out_decimal:
 subi r16,-'0'
 st X+,r16
 ret
success:
 ldi ZL,low(ok*2)
 ldi ZH,high(ok*2)
 rjmp reply_flash
fail_syntax:
 ldi ZL,low(err_syntax*2)
 ldi ZH,high(err_syntax*2)
 rjmp reply_flash
fail_input:
 ldi ZL,low(err_input*2)
 ldi ZH,high(err_input*2)
 rjmp reply_flash
fail_load:
 ldi ZL,low(err_load*2)
 ldi ZH,high(err_load*2)
 rjmp reply_flash
TIMER1_STR: .db 112,105,110,103,13,10,0,0
TIMER2_STR: .db 112,111,110,103,13,10,0,0
ok: .db 33,79,75,13,10,0
err_syntax: .db 33,69,82,82,32,83,89,78,84,65,88,13,10,0
err_input: .db 33,69,82,82,32,73,78,80,85,84,13,10,0,0
err_load: .db 33,69,82,82,32,76,79,65,68,13,10,0
err_queue: .db 33,69,82,82,32,81,85,69,85,69,13,10,0,0
status1: .db 33,79,75,32,84,49,61,0
status2: .db 32,84,50,61,0,0
status3: .db 32,76,49,61,0,0
status4: .db 32,76,50,61,0,0
