"""Send one command and distinguish responses from periodic messages.
Usage: python3 send_command.py --port /dev/cu.usbserial-... '?'
Requires pyserial. Command periods are four HEX digits in CPU cycles.
"""
import argparse,time
import serial
p=argparse.ArgumentParser();p.add_argument('--port',required=True);p.add_argument('command');p.add_argument('--timeout',type=float,default=3);a=p.parse_args()
try:payload=a.command.encode('ascii')
except UnicodeEncodeError:p.error('ASCII commands only')
if b'\r' in payload or b'\n' in payload or len(payload)>31:p.error('One line, at most 31 ASCII bytes')
with serial.Serial(a.port,500000,timeout=.1) as ser:
    ser.reset_input_buffer();ser.write(payload+b'\n');ser.flush()
    end=time.monotonic()+a.timeout;buffer=bytearray()
    while time.monotonic()<end:
        buffer.extend(ser.read(256))
        while b'\n' in buffer:
            line,_,rest=buffer.partition(b'\n');buffer=bytearray(rest)
            text=line.rstrip(b'\r').decode('ascii',errors='replace')
            print(text)
            if text.startswith('!OK'):raise SystemExit(0)
            if text.startswith('!ERR'):raise SystemExit(1)
    raise SystemExit('No response: check CPU clock, wiring and baud rate')
