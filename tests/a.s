addi	a7,x0,1024
add	a7,a7,a7
add	a7,a7,a7
add	a7,a7,a7
add	a7,a7,a7 #a7=16384 tag=1
add	a7,a7,a7 #a7=32768 tag=1
sd	ra,0(a7) #index 0
lw      a4,0(x0) #index 0
add	a7,a7,a7 #a7=65536 tag=2
lw      a5,0(a7)
lui     a4,0x0
li      t1,1244
li      a6,1
lw      a5,0(a7)
seqz    a5,a5
#lw      a5,0(a4)
mv      a7,t1
mv      a0,a6
addiw   a3,a5,-1
slli    a2,a5,0x20
slli    a3,a3,0x20
mv      a1,a4
srli    a2,a2,0x20
srli    a3,a3,0x20
ret
