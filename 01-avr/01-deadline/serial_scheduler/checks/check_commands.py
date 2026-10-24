#!/usr/bin/env python3
"""Run assembled ATmega8 code; measure first UDR writes against Timer1 deadlines."""
import argparse, subprocess, json, math
from collections import Counter
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--sim',required=True);p.add_argument('--hex',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
results=[];all_errors=[]
def case(name,commands=(),expected=(16000,24000,4,4),replies=None,spacing=160,first=40000,interval=1000000,cycles=None):
 schedule=[]
 for i,c in enumerate(commands):
  schedule += [(first+i*interval+j*spacing,b) for j,b in enumerate((c+'\n').encode())]
 f=a.output/(name+'.rx.csv');f.write_text(''.join(f'{t},{b}\n' for t,b in schedule))
 stop=cycles or max(400000,first+len(commands)*interval+100000)
 out=subprocess.check_output([a.sim,a.hex,str(stop),str(f)],text=True)
 (a.output/(name+'.trace.csv')).write_text(out)
 rows=[x.split(',') for x in out.splitlines()];starts=[r for r in rows if r[0]=='START'];end=next(r for r in rows if r[0]=='END');uart=[r for r in rows if r[0]=='UART']
 assert starts,(name,'no timer output')
 errors=[int(r[-1]) for r in starts];assert min(errors)>=0 and max(errors)<=4,(name,'timing',min(errors),max(errors))
 assert int(end[1])==0,(name,'timer stopped')
 state=tuple(map(int,end[2:6]));assert state==expected,(name,state,expected)
 assert int(end[6])==(expected[2]+2)*160+2048,(name,'phase')
 reply=bytes(int(r[3]) for r in uart if r[2]=='0')
 if replies is not None: assert reply==b''.join(b'!OK\r\n' if x else b'!ERR\r\n' for x in replies),(name,reply,replies)
 # Every completed timer string retains channel attribution and CRLF.
 current=[];chan=None;lines=0
 for r in uart:
  ch=int(r[2]);b=int(r[3])
  if ch==0:
   assert not current,(name,'reply interrupted timer string');continue
  if chan is not None:assert ch==chan,(name,'timer interleaving')
  chan=ch;current.append(b)
  if b==10:
   assert len(current)>=2 and current[-2]==13,(name,'bad CRLF')
   current=[];chan=None;lines+=1
 for ch in (1,2):
  selected=[r for r in starts if int(r[2])==ch]
  if not commands:
   period=expected[ch-1]
   assert all((int(y[3])-int(x[3]))%65536==period for x,y in zip(selected,selected[1:])),(name,'deadline drift')
 # Verify steady-state periods in absolute cycles, including counter wraps:
 # no missing event can hide behind a small 16-bit timing error.
 for ch in (1,2):
  tail=[r for r in starts if int(r[2])==ch][-5:]
  for x,y in zip(tail,tail[1:]):
   actual=(int(y[1])-int(y[-1]))-(int(x[1])-int(x[-1]))
   assert actual==expected[ch-1],(name,'missing/drifting deadline',ch,actual)
 all_errors.extend(errors)
 results.append({'name':name,'timer_starts':len(starts),'error_min':min(errors),'error_max':max(errors),'complete_timer_lines':lines,'reply':reply.decode(),'state':state,'timer_stop_count':0})
case('default',cycles=3000000)
case('minimum',['P 1780 1780'],(6016,6016,4,4),[True],cycles=3000000)
case('below_minimum',['P 177F 177F'],replies=[False])
case('odd_period',['P 1781 1781'],(6017,6017,4,4),[True],cycles=3000000)
case('unequal_minimum_multiple',['P 1780 2F00'],(6016,12032,4,4),[True])
case('period_one',['T1 5DC0'],(24000,24000,4,4),[True])
case('period_two',['T2 3E80'],(16000,16000,4,4),[True])
case('restart',['R'],replies=[True])
case('long_gcd_validation',['P DFFF 0001'],replies=[False],cycles=3000000)
case('max_period',['P E000 E000'],(57344,57344,4,4),[True])
case('over_max_period',['P E001 E001'],replies=[False])
case('long_text_one',['S1 abcdefghijklmnop'],(16000,24000,16,4),[True])
case('long_text_two',['S2 abcdefghijklmnop'],(16000,24000,4,16),[True])
case('both_long',['P 3000 3000','S1 abcdefghijklmnop','S2 ABCDEFGHIJKLMNOP'],(12288,12288,16,16),[True]*3)
case('too_long',['S1 abcdefghijklmnopq'],replies=[False])
case('empty_texts',['S1 ','S2 ','P 1280 1280'],(4736,4736,0,0),[True]*3)
case('below_empty_min',['S1 ','S2 ','P 127F 127F'],(16000,24000,0,0),[True,True,False])
case('reject_after_change',['P 1780 1780','S1 abcdefghijklmnop'],(6016,6016,4,4),[True,False])
case('changed_strings',['S1 HELLO','S2 WORLD'],(16000,24000,5,5),[True,True])
for i,c in enumerate(['','T3 4000','T1 0000','T2 ZZZZ','T1 400','P 0000 0000','P 1780 1781','S3 test','garbage','R extra','P 1780x1780','S1 '+('a'*40),'S1 !OK']):
 case('invalid_'+str(i),[c],replies=[False])
# Receive every 160 cycles, sweeping command starts across Timer1 early wakeup.
for offset in range(0,512,32):
 case('rx_phase_'+str(offset),['S1 fast'],replies=[True],first=15500+offset,cycles=300000)
# Admission at its exact mathematical boundary for all supported length pairs.
# Independent Python proof checks g criterion and constructive phase, not firmware execution.
boundaries=[]
for l1 in range(17):
 for l2 in range(17):
  c1=(l1+2)*160;c2=(l2+2)*160;b=c1+c2+4096;phase=c1+2048
  assert phase-c1==2048 and b-phase-c2==2048
  assert 2*b<=2*57344
  boundaries.append({'lengths':[l1,l2],'period':b,'sum':2*b})
  case('boundary_'+str(l1)+'_'+str(l2), ['P E000 E000','S1 '+('a'*l1),'S2 '+('b'*l2),f'P {b:04X} {b:04X}'],(b,b,l1,l2),[True]*4,interval=200000)

report={'passed':len(results),'timing_point':'first OUT UDR, not physical TX','error_cycles':[min(all_errors),max(all_errors)],'measured_timer_starts':len(all_errors),'error_histogram':dict(Counter(all_errors)),'hardware_tested':False,'simavr_uart_override':'cycles_per_byte=160 only; CPU and Timer1 unmodified','minimum_ping_pong':{'period1':6016,'period2':6016,'sum':12032,'phase':3008,'scope':'exact minimum accepted by the documented reserved-window policy'},'cases':results,'length_boundary_count':len(boundaries)}
(a.output/'result.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='cases'},indent=2))
