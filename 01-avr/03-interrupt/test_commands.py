"""Functional tests of assembled firmware, not a Python reimplementation.
Usage: python3 test_commands.py --sim path/to/sim_test --hex timers.hex --output dir
"""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--sim',required=True);p.add_argument('--hex',required=True);p.add_argument('--output',required=True);a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
# One command per window, enough time for a complete reply and timer messages.
cases=[
 ('?', '!OK T1=3E80 T2=5DC0 L1=04 L2=04', (16000,24000,4,4)),
 ('T1 4000','!OK',(16384,24000,4,4)),
 ('T2 6000','!OK',(16384,24576,4,4)),
 ('S1 hello','!OK',(16384,24576,5,4)),
 ('S2 world','!OK',(16384,24576,5,5)),
 ('?','!OK T1=4000 T2=6000 L1=05 L2=05',(16384,24576,5,5)),
 ('T1 0001','!ERR LOAD',(16384,24576,5,5)),
 ('S1 1234567890123456','!ERR LOAD',(16384,24576,5,5)),
 ('T1 FFFF','!OK',(65535,24576,5,5)),
 ('S1 1234567890123456','!OK',(65535,24576,16,5)),
 ('T1 47FF','!ERR LOAD',(65535,24576,16,5)),
 ('T1 4800','!OK',(18432,24576,16,5)),
 ('T1 GGGG','!ERR SYNTAX',(18432,24576,16,5)),
 ('S1 !OK','!ERR SYNTAX',(18432,24576,16,5)),
 ('R','!OK',(18432,24576,16,5)),
 ('S2 ','!OK',(18432,24576,16,0)),
 ('T2 0FFF','!ERR LOAD',(18432,24576,16,0)),
 ('T2 1000','!OK',(18432,4096,16,0)),
 ('S2 abc','!ERR LOAD',(18432,4096,16,0)),
 ('T2 FFFF','!OK',(18432,65535,16,0)),
 ('S2 abc','!OK',(18432,65535,16,3)),
 ('?','!OK T1=4800 T2=FFFF L1=10 L2=03',(18432,65535,16,3)),
 ('X','!ERR SYNTAX',(18432,65535,16,3)),
 ('S1 '+'a'*40,'!ERR INPUT',(18432,65535,16,3)),
 ('?','!OK T1=4800 T2=FFFF L1=10 L2=03',(18432,65535,16,3)),
]
cases += [
 ('S1 ping','!OK',(18432,65535,4,3)),
 ('S2 pong','!OK',(18432,65535,4,4)),
 ('T1 1800','!OK',(6144,65535,4,4)),
 ('T2 1800','!OK',(6144,6144,4,4)),
 ('R','!OK',(6144,6144,4,4)),
 ('?','!OK T1=1800 T2=1800 L1=04 L2=04',(6144,6144,4,4)),
]
spacing=240000;start=80000;events=[]
for i,(cmd,_,__) in enumerate(cases):
 events.extend((start+i*spacing+j*800,b) for j,b in enumerate((cmd+'\n').encode()))
schedule=out/'rx.csv';schedule.write_text(''.join(f'{t},{b}\n' for t,b in events))
trace=out/'trace.csv';stop=start+len(cases)*spacing
with trace.open('w') as f:subprocess.run([a.sim,a.hex,str(stop),str(schedule)],stdout=f,check=True)
lines=[];pending=bytearray();line_start=0;states=[];pins={'OC1A':[],'OC1B':[]};pin_last={};ended=False
for row in trace.read_text().splitlines():
 x=row.split(',')
 if x[0]=='UART':
  t,b=map(int,x[1:]);
  if not pending:line_start=t
  pending.append(b)
  if b==10:lines.append((line_start,bytes(pending).decode()));pending.clear()
 elif x[0]=='STATE':states.append(tuple(map(int,x[1:])))
 elif x[0] in pins:
  t,v=map(int,x[1:]);k=x[0]
  if pin_last.get(k)!=v:pins[k].append(t)
  pin_last[k]=v
 elif x[0]=='END':assert int(x[2])==0,'Timer stopped during execution';ended=True
assert ended
vectors=next(tuple(map(int,row.split(',')[1:])) for row in trace.read_text().splitlines() if row.startswith('VECTORS,'))
assert all(v>0 for v in vectors)
result=[]
for i,(cmd,reply,expected) in enumerate(cases):
 lo=start+i*spacing;hi=lo+spacing
 replies=[s.strip() for t,s in lines if lo<=t<hi and s.startswith('!')]
 assert replies==[reply],(i,cmd,replies,reply)
 state=[s for s in states if lo+spacing-20000<=s[0]<hi][-1]
 assert state[1:5]==expected,(cmd,state,expected)
 assert state[5:]==(0,0),(cmd,'queue fault',state)
 for pin,times in pins.items():assert any(lo<t<hi for t in times),(cmd,'timer not running',pin)
 result.append({'command':cmd,'reply':reply,'state':expected})
assert any(s=='hello\r\n' for _,s in lines)
assert any(s=='world\r\n' for _,s in lines)
assert any(s=='1234567890123456\r\n' for _,s in lines)
assert any(s=='abc\r\n' for _,s in lines)
assert any(s=='\r\n' for _,s in lines)
allowed={'ping\r\n','pong\r\n','hello\r\n','world\r\n','1234567890123456\r\n','abc\r\n','\r\n'}
assert all(s.startswith('!') or s in allowed for _,s in lines),'Corrupt or interleaved messages'
stable_periods={}
for k,times in pins.items():
 stable=[t for t in times if t>start+(len(cases)-1)*spacing]
 periods=[b-a for a,b in zip(stable,stable[1:])]
 assert periods and max(abs(t-6144) for t in periods)<=4,(k,periods)
 stable_periods[k]={'target':6144,'min':min(periods),'max':max(periods)}
summary={'stable_minimum_policy_periods':stable_periods,'passed':True,'interrupt_vector_entries':dict(zip(['compare_a','compare_b','udre','rx'],vectors)),'commands_tested':len(cases),'complete_lines':len(lines),'timer_stop_observations':0,'state_and_rejection_checks':True,'hardware_tested':False,'uart_callback':'UDR writes, not physical TX pin','cases':result}
(out/'test_results.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False))
print(json.dumps({k:v for k,v in summary.items() if k!='cases'},indent=2))
