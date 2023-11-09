run: mini-til.exe
    .\mini-til.exe

mini-til.exe: mini-til.obj
    link mini-til.obj kernel32.lib /entry:BOOT /subsystem:console

mini-til.obj: mini-til.asm
    nasm mini-til.asm -fwin64
