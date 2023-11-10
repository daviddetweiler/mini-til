run: mini-til.exe
    .\mini-til.exe

mini-til.exe: mini-til.obj report
    link mini-til.obj kernel32.lib /entry:boot /subsystem:console

mini-til.obj: mini-til.asm
    nasm mini-til.asm -fwin64

mini-til.bin: mini-til.asm
    nasm mini-til.asm -fbin -o mini-til.bin -Dcompressed

mini-til.bin.bw: mini-til.bin bitweaver.py
    python .\bitweaver.py pack mini-til.bin mini-til.bin.bw

bitweaver.py: ac.py

report:
    python dead-code.py mini-til.asm
