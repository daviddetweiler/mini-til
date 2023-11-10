run: mini-til.exe
    .\mini-til.exe

mini-til.exe: mini-til.obj
    link mini-til.obj kernel32.lib /entry:boot /subsystem:console

mini-til.obj: mini-til.asm
    nasm mini-til.asm -fwin64

mini-til.bin: mini-til.asm
    nasm mini-til.asm -fbin -o mini-til.bin -Dcompressed

mini-til.bin.bw: mini-til.bin bitweaver.py
    python .\bitweaver.py pack mini-til.bin mini-til.bin.bw

bitweaver.py: ac.py

bitstream.inc: mini-til.bin.bw inc.py
    python .\inc.py mini-til.bin.bw bitstream.inc

loader.obj: loader.asm bitstream.inc
    nasm loader.asm -fwin64

loader.exe: loader.obj
    link loader.obj kernel32.lib /entry:start /subsystem:console /fixed

report:
    python .\dead-code.py mini-til.asm
