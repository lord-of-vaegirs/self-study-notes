## 手里有libc库，求解其中函数偏移

以__free_hook为例

先找到汇编代码里面free的起始地址`readelf -s /home/lixingjian/pwn/note/libc.so.6 | grep " free@@"`

再找到free_hook具体位置`objdump -d -M intel --start-address=0x9a6d0 /home/lixingjian/pwn/note/libc.so.6 | head -n 10`，一般是`mov rax QWORD PTR[rip+0x....]`

