mini.exe: loader.obj
    link loader.obj kernel32.lib \
        /entry:start \
        /subsystem:console \
        /fixed \
        /out:mini.exe \
        /ignore:4254 \
        /merge:.rdata=kernel \
        /merge:.text=kernel \
        /section:kernel,RE

run: mini.exe
    python .\cat.py core.mini - | mini.exe

mini.bin: mini.asm
    nasm mini.asm -fbin -o mini.bin

mini.bin.bw: mini.bin bitweaver.py
    python .\bitweaver.py pack mini.bin mini.bin.bw

bitweaver.py: ac.py

bitstream.inc: mini.bin.bw inc.py
    python .\inc.py mini.bin.bw bitstream.inc

loader.obj: loader.asm bitstream.inc
    nasm loader.asm -fwin64

clean:
    del *.obj *.exe *.bw *.inc *.bin
