  org 0x7C00
  bits 16
%define EOLJ 0x0D,0x0A  ;; 0x0D is used to set cursor at the start of the line and 0x0A is used to jump to the next line 

; FAT 12 header

  jmp short start
  nop

bdb_oem:                        db 'MSWIN4.1'               ;very important understanding here is for dw little endian comes into play and db will write as it is
bdb_bytes_per_sector:           dw 512                      ;db 12h,34h will look like this 12 34 , while dw 1234h will look like thos 34 12
bdb_sectors_per_cluster:        db 1                        ;
bdb_reserved_sectors:           dw 1                        ;sectos reserved at the start for non data use ie we have reserved this for fs internals and boot code,this in our case of fat 12 is 1 sector ie 512 bytes basically our bootloader.bin  
bdb_fat_count:                  db 2                        ;copies of FAT on the disk
bdb_dir_entries_count:          dw 0E0h                     ;total no of possible root entries in fat (in fat 12 and 16 we have a fixed 32 byte size for each entry, dne in fat 32)
bdb_total_sectors:              dw 2880                     ;calc: 2880*512=1.44mb 
bdb_media_descriptor_type:      db 0f0h                     ;F0 means a 3.5" floppy drive 
bdb_sectors_per_fat:            dw 9                        ;9*512 = 4608 bytes per fat and we have 2 fats
bdb_sectors_per_track:          dw 18
bdb_heads:                      dw 2
bdb_hidden_sectors:             dd 0
bdb_large_sector_count:         dd 0

;┌────────────┬───────────────┬───────────────┐
;│ Sector(s)  │ Region        │ Purpose       │
;├────────────┼───────────────┼───────────────┤
;│ 0          │ Reserved      │ Boot + BPB    │--------------------->JUMP+OEM_id,BPB,EBR,Bootloader code ,0x55AA
;│ 1 – 9      │ FAT #1        │ Cluster map   │
;│ 10 – 18    │ FAT #2        │ Backup FAT    │
;│ 19 – 32    │ Root Dir      │ Filenames     │
;│ 33 – 2879  │ Data region   │ File contents │
;└────────────┴───────────────┴───────────────┘

;extended boot record

ebr_drive_number:               db 0                            ;drive number for floppies it is 00h , for hdds its 80h most modern oses ignore this
                                db 0                            ;simply used for padding
ebr_signature:                  db 29h                          ;validity marker , 29 means the 3 following labels are all valid  
ebr_volume_id:                  db 12h,34h,56h,78h              ;any 8 bytes value
ebr_volume_label:               db 'ATKOSB     '                ;any name but must be padded to exactly 11bytes
ebr_system_id:                  db 'FAT12   '                   ;fs type here FAT12 but has to be padded to 8 bytes




start:
  jmp main

lb1:
  push si
  push ax

.l1:
  lodsb   ; this will load in to al from si a single byte ( ie a character in this case)
  or al,al
  jz .fin
  mov ah,0x0e ;interrupt mode within 0x10 which will set write character in TTY mode option 
  int 0x10  ; the interrupt used for 'VIDEO' bios 
  jmp .l1
 
.fin:
  pop ax
  pop si
  ret


main:

;cleared ds (data segment) and es ( extra segment) registers 
;IMP NOTE: we cannot load a immdediate constant directly into DS , ES SI ,CS etc
  mov ax,0
  mov ds,ax
  mov es ,ax
; all addresses are calculated as base * 16 + offset: there fre in stack the calculation is ss*16+sp
;therefore at the start we have 0*16+0x7C00=7C00
;there the stack will go on inc downwards till the base which is 0 from teh top 7C00 
;however it cannot grow all the way to 0 since since 0000-03FF is IVT area and 0400-04FF is BIOS data area  , 0500+ is for BIOS use
  mov ss,ax
  mov sp,0x7C00
  mov si,msg
  call lb1
  mov [ebr_drive_number],dl       ; prereq : DL has drive number
  mov ax,1                        ; AX must hold LBA address to convert into CHS
  mov cl,1                        ; which sector to read from
  mov bx,0x7E00                   ;here we now have ES:BX = 0000:7E00 which we will read out sector 1 from our drive into (the write startes at this address)
  ;;;***This is not a stack it is a data buffer so it is written to upward NOT DOWNWARDS
  call disk_read

  jmp .halt



floppy_failure:
  mov si,read_failure
  call .lb1               ;;recall lb1 is method used to print text in bios using the 10h int (from si)
  jmp key_press

key_press:
  mov ah,00h                ;indicates a read and clear of the keyboard input buffer storesteh ascii valuein AL
  int 16h                   ;Keyboard BIOS interrupt
                            ;all in all our 2 lines wait for a key press and continue after any key is pressed
  jmp FFFFh:0

.halt:
  cli
  hlt

halt:
  jmp .halt

;
;DISK READING
;
;PRE-CONDITION: AX holds LBA in LBA TO CHS CONVERSION FUNCTION, CX holds number of sectors to read 
;
;;;say we have out input(LBA value) in ax,we clear dx
;;;at the end of lba_to_chs we will have 
;;;AH -> we set to 02 for "reading disk"
;;;AL -> numbersof sectors we wanna read
;;;CX -> bits(0-5) hold sector number
;;;   -> bits(6-15)hold cylinder number , where lower 8 bits are in CH and bits 8 and 9 (0 indexing)are in uppper 2 bits of CL 
;;;DL -> stores drive number
;;;DH -> stores head
;;;ES:BX -> pointer to data buffer




;LBA TO CHS CONVERSION FUNCTION
lba_to_chs:
  ;C=LBA/(HPC*SPT)
  ;H=(LBA/SPT)%HPC
  ;S=LBA%SPT + 1    ; +1 since sector addressing is from 1
  
  push ax     ; holds LBA address we wanna translate(read PRE-CONDITION)
  push dx     ; to retain the drive number

  xor dx,dx
  div word[bdb_sectors_per_track]    ;now dx will store remainder ie LBA % bdb_sectors_per_track
                                     ;now ax will store remainder ie LBA / bdb_sectors_per_track 
  inc dx
  mov cx,dx                           ;putting sector in cx (SECTOR)
  xor dx,dx
  div word[bdb_heads]                 ;now dx will store remainder (HEAD) ie LBA / bdb_sectors_per_track % bdb_heads
                                      ;now ax will store remainder (CYLINDER) ie LBA / bdb_sectors_per_track / bdb_heads
  mov dh,dl                           ;now dh stores the entire HEAD (which is 8 bits whihc is why we have a hardwarelimit imposed of 0-255)
  mov ch,al                           ;this is to transfer bits 0-7 into of CYLINDER into CH
  shl ah,6
  or  cl,ah                           ;bits 8 and 9 of CYLINDER are "ored" into CL whose bits 0-5 alr contain SECTOR no

  pop ax                              ;now ax holds the value of dx prefunction 
  mov dl,al                            ;since disk number is 8bits long and supposed to be in dl before 13h
  pop ax
  ret

;
;READING FROM A DISK
;
disk_read:
  push cx                      ;CX holds no of sectors to read, AX holds LBS (read PRE-CONDITION)
  call lba_to_chs              ;converted values are stored in results as per LBA TO CHS CONVERSION FUNCTION 
  pop ax
  mov ah,02h                   ; as per requirements now ah has 02 and AL holds number of sectors to read
  mov di,3                     ; this is a counter to attempt reading thrice in case of failure     
  
.retry:
  pusha
  stc
  int 13h
  jnc .done

  ;incase of read failure
  popa
  call disk_reset
  dec di
  test di,di
  jnz .retry                                ;while the counter is not 0 coutinue trying

.fail:
  ;if all "di" number of attempts fail
  jmp floppy_failure


.done:
  popa
  ret
  
disk_reset:
  pusha
  mov ah,0        ; ah=0 in int 13h is used to reset the disk system/ controller
  stc
  int 13h
  jc floppy_failure
  popa
  ret




msg:                  db 'HELLO WORLD !',EOLJ,0
read_failure:         db'FAILURE TO READ FROM DRIVE ! HAVE A GOOD DAY :)',EOLJ,0


times 510-($-$$) db 0
dw 0xAA55
