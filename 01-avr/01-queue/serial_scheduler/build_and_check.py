#!/usr/bin/env python3
"""Build tools locally and reproduce the simulation on macOS/Linux.
Requires Python 3, git, make, a native C compiler (cc/clang).
Downloads pinned upstream source into ./build; installs nothing system-wide.
Usage: python3 build_and_check.py
"""
from pathlib import Path
import subprocess, shutil, json
ROOT=Path(__file__).resolve().parent
BUILD=ROOT/'build';BUILD.mkdir(exist_ok=True)
def run(args,**kw):
    return subprocess.run([str(x) for x in args],check=True,**kw)
def checkout(name,url,revision):
    p=BUILD/name
    if not p.exists():
        run(['git','init',p]);run(['git','-C',p,'remote','add','origin',url])
    if subprocess.run(['git','-C',str(p),'rev-parse','--verify',revision],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:
        run(['git','-C',p,'fetch','--depth','1','origin',revision])
    run(['git','-C',p,'checkout','--detach',revision]);return p
avra=checkout('avra','https://github.com/Ro5bert/avra.git','c78607c5fe64d044001683cbe90f20e85a080cc4')
sim=checkout('simavr','https://github.com/buserror/simavr.git','5b08da60497f7564f50941f74a549fe2851db030')
run(['make','-C',avra,'-j2'])
src=sim/'simavr'
(src/'sim_core_config.h').write_text('#define CONFIG_SIMAVR_VERSION "local-atmega8"\n#define CONFIG_MEGA8 1\n')
(src/'sim_core_decl.h').write_text('#include "sim_core_config.h"\nextern avr_kind_t mega8;\navr_kind_t * avr_kind[] = { &mega8, NULL };\n')
cc=shutil.which('clang') or shutil.which('cc')
if not cc: raise SystemExit('Install a native C compiler first')
objdir=BUILD/'objects';objdir.mkdir(exist_ok=True)
objects=[]
for p in sorted((src/'sim').glob('sim_*.c'))+sorted((src/'sim').glob('avr_*.c'))+[src/'cores/sim_mega8.c',src/'cores/sim_megax.c']:
    o=objdir/(p.stem+'.o');objects.append(o)
    run([cc,'-O2','-Wno-deprecated-declarations','-I'+str(src),'-I'+str(src/'sim'),'-I'+str(src/'cores'),'-c',p,'-o',o])
exe=BUILD/'sim_test'
run([cc,'-O2','-I'+str(src/'sim'),ROOT/'checks/simulator.c',*objects,'-lm','-o',exe])
# Assemble a copy so AVRA's auxiliary output stays in build/.
asm=BUILD/'serial_scheduler.asm';shutil.copyfile(ROOT/'serial_scheduler.asm',asm)
hexfile=BUILD/'serial_scheduler.hex'
run([avra/'src/avra','-I',avra/'includes','-o',hexfile,asm])
run([shutil.which('python3'),ROOT/'checks/check_commands.py','--sim',exe,'--hex',hexfile,'--output',BUILD/'command-tests'])
print('Functional simulator tests passed. Physical TX timing requires hardware measurement.')
