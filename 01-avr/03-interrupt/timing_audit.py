"""Analytical check for common-phase periodic whole-string USART transmissions.
This is a feasibility counterexample for that model, not physical TX measurement.
"""
import argparse,json,math
from fractions import Fraction

def analyze(t1,t2,l1=4,l2=4,cpu=8000000,baud=500000,tolerance=4):
    if min(t1,t2,cpu,baud)<=0 or min(l1,l2,tolerance)<0:raise ValueError('Invalid arguments')
    c1=Fraction((l1+2)*10*cpu,baud)
    c2=Fraction((l2+2)*10*cpu,baud)
    first=math.lcm(t1,t2)
    # Even choosing the shorter string first cannot fit both starts into +/-tolerance.
    incompatible=min(c1,c2)>2*tolerance
    return {'model':'common phase, no interleaving of whole strings, physical TX starts',
            'periods':[t1,t2],'first_coincident_deadline_cycles':first,
            'frame_cycles':[float(c1),float(c2)],'allowed_start_window_cycles':2*tolerance,
            'minimum_separation_at_collision_cycles':float(min(c1,c2)),
            'physical_four_cycle_requirement_feasible_in_this_model':not incompatible,
            'average_uart_utilization':float(c1/t1+c2/t2),
            'note':'A feasible collision window alone does not prove schedulability. No hardware tested.'}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--period1',type=int,default=16000);p.add_argument('--period2',type=int,default=24000)
    p.add_argument('--length1',type=int,default=4);p.add_argument('--length2',type=int,default=4);p.add_argument('--output')
    a=p.parse_args();result=analyze(a.period1,a.period2,a.length1,a.length2)
    assert analyze(16000,24000)['first_coincident_deadline_cycles']==48000
    assert analyze(16000,24000)['minimum_separation_at_collision_cycles']==960
    assert not analyze(6144,6144)['physical_four_cycle_requirement_feasible_in_this_model']
    assert not analyze(65535,65534,0,0)['physical_four_cycle_requirement_feasible_in_this_model']
    text=json.dumps(result,ensure_ascii=False,indent=2)
    if a.output:
        from pathlib import Path
        Path(a.output).write_text(text)
    print(text)
