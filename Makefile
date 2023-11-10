run: mini.exe
    .\mini.exe

debug.exe: mini.obj
    link mini.obj kernel32.lib /entry:boot /subsystem:console /out:debug.exe

mini.obj: mini.asm
    nasm mini.asm -fwin64

mini.bin: mini.asm
    nasm mini.asm -fbin -o mini.bin -Dcompressed

mini.bin.bw: mini.bin bitweaver.py
    python .\bitweaver.py pack mini.bin mini.bin.bw

bitweaver.py: ac.py

bitstream.inc: mini.bin.bw inc.py
    python .\inc.py mini.bin.bw bitstream.inc

loader.obj: loader.asm bitstream.inc
    nasm loader.asm -fwin64

mini.exe: loader.obj
    link loader.obj kernel32.lib /entry:start /subsystem:console /fixed /out:mini.exe

report:
    python .\dead-code.py mini.asm
