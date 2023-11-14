mini.exe: mini.obj
    link mini.obj kernel32.lib \
        /entry:start \
        /subsystem:console \
        /fixed \
        /ignore:4254 \
        /merge:.rdata=kernel \
        /merge:.text=kernel \
        /section:kernel,RE

kernel.bin: kernel.asm
    nasm kernel.asm -fbin -o kernel.bin

kernel.bin.bw: kernel.bin bitweaver.py
    python .\bitweaver.py pack kernel.bin kernel.bin.bw

bitweaver.py: ac.py

bitstream.inc: kernel.bin.bw inc.py
    python .\inc.py kernel.bin.bw bitstream.inc

mini.obj: mini.asm bitstream.inc
    nasm mini.asm -fwin64

clean:
    del *.obj *.exe *.bw *.inc *.bin
