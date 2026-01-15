ASM=nasm
CC=gcc

TD=tools###This is for all the associated components
SD=src
BD=build


.PHONY: all floppy_image bootloader kernel clean always tools_fat

### all ( This target is to make sure all program components run )
all: floppy_image tools_fat 


### Floppy image 
floppy_image: $(BD)/floppy.img
$(BD)/floppy.img : bootloader kernel
	dd if=/dev/zero of=$(BD)/floppy.img bs=512 count=2880  
	mkfs.fat -F 12 $(BD)/floppy.img 
	dd if=$(BD)/bootloader.bin of=$(BD)/floppy.img conv=notrunc
	mcopy -i $(BD)/floppy.img $(BD)/kernel.bin "::kernel.bin"
	mcopy -i $(BD)/floppy.img test.txt "::test.txt"


### bootloader
bootloader: $(BD)/bootloader.bin
$(BD)/bootloader.bin: always
	$(ASM) $(SD)/bootloader/boot.asm -f bin -o $(BD)/bootloader.bin

### kernel
kernel: $(BD)/kernel.bin   
$(BD)/kernel.bin: always
	$(ASM) $(SD)/kernel/main.asm -f bin -o $(BD)/kernel.bin

###tools

##tool1-fat
tools_fat: $(BD)/tools/fat
$(BD)/tools/fat: always $(TD)/fat/fat.c
	mkdir -p $(BD)/tools		
	$(CC) -g $(TD)/fat/fat.c -o $(BD)/tools/fat
	
### always 
always: 
	mkdir -p $(BD)

clean:
	rm -rf $(BD)/*