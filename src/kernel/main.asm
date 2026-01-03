org 0x7C00
bits 16
%define EOLJ 0x0D,0x0A  ;; 0x0D is used to set cursor at the start of the line and 0x0A is used to jump to the ext line 

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
 mov ss,ax
 mov sp,0x7C00
 mov si,msg
 call lb1


hlt 

halt:
  jmp halt


msg: db 'HELLO WORLD !',EOLJ,0


times 510-($-$$) db 0
dw 0xAA55
