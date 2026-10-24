#!/usr/bin/env python3
"""Check compile-time invalid settings and the minimum valid default pair."""
from pathlib import Path
import subprocess,json,argparse
p=argparse.ArgumentParser()
for key in ('source','avra','include','sim','output'):p.add_argument('--'+key,required=True,type=Path)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True);source=a.source.read_text();results=[]
for name,p1,p2 in [('invalid_defaults',0,24000),('minimum_defaults',6016,6016)]:
 asm=a.output/(name+'.asm');hexf=asm.with_suffix('.hex')
 asm.write_text(source.replace('.equ TIMER1_INTERVAL=16000',f'.equ TIMER1_INTERVAL={p1}').replace('.equ TIMER2_INTERVAL=24000',f'.equ TIMER2_INTERVAL={p2}'))
 subprocess.run([str(a.avra),'-I',str(a.include),'-o',str(hexf),str(asm)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 raw=subprocess.check_output([str(a.sim),str(hexf),'300000'],text=True)
 (a.output/(name+'.trace.csv')).write_text(raw)
 starts=[l for l in raw.splitlines() if l.startswith('START,')]
 if p1==0:
  assert not starts
  assert bytes(int(l.split(',')[-1]) for l in raw.splitlines() if l.startswith('UART,'))==b'!ERR\r\n'
 else:assert starts and all(0<=int(l.split(',')[-1])<=4 for l in starts)
 results.append({'name':name,'passed':True,'timer_starts':len(starts)})
(a.output/'boot_checks.json').write_text(json.dumps(results,indent=2)+'\n');print(results)
