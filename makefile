ASM=nasm

SD=src
BD=build


.PHONY: floppy_image bootloader kernel clean always

### Floppy image 
floppy_image: $(BD)/floppy.img
$(BD)/floppy.img : bootloader kernel
	dd if=/dev/zero of=$(BD)/floppy.img bs=512 count=2880  
	mkfs.fat -F 12 $(BD)/floppy.img 
	dd if=$(BD)/bootloader.bin of=$(BD)/floppy.img conv=notrunc
	mcopy -i $(BD)/floppy.img $(BD)/kernel.bin "::kernel.bin"

### bootloader
bootloader: $(BD)/bootloader.bin
$(BD)/bootloader.bin: always
	$(ASM) $(SD)/bootloader/boot.asm -f bin -o $(BD)/bootloader.bin

### kernel
kernel: $(BD)/kernel.bin   
$(BD)/kernel.bin: always
	$(ASM) $(SD)/kernel/main.asm -f bin -o $(BD)/kernel.bin

### always 
always: 
	mkdir -p $(BD)

clean:
	rm -rf $(BD)/*