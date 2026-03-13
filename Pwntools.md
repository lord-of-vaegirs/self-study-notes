# Pwntools 竞赛实战速查手册

## 一、 数据发送 (Send 系列)

[函数/方法]
`send` / `sendline`

[参数+用法]
- `send(data)`：发送字节流数据。
- `sendline(data)`：发送数据并在末尾自动加上回车符 `\n`。
- **注意**：Python3 中必须发送 `bytes` 类型（如 `b"A"`）。

[使用示例]
```python
io.send(b"A" * 0x20) 
io.sendline(b"cat flag")
```

---

[函数/方法]
`sendafter` / `sendlineafter`

[参数+用法]
- `sendafter(delim, data)`：接收到 `delim` 后发送数据。
- `sendlineafter(delim, data)`：接收到 `delim` 后发送数据并换行。

[使用示例]
```python
io.sendlineafter(b"Input your choice:", b"1")
```

---

## 二、 数据接收 (Recv 系列)

[函数/方法]
`recv` / `recvline` / `recvuntil`

[参数+用法]
- `recv(nbytes)`：接收指定长度字节。
- `recvline()`：接收一行。
- `recvuntil(delim, drop=False)`：接收直到出现 `delim`。`drop=True` 表示结果不含 `delim`。

[使用示例]
```python
io.recvuntil(b"Gift: 0x")
leak_addr = io.recv(12)
```

---

## 三、 数据打包与解包 (p/u 系列)

[函数/方法]
`p32` / `p64`

[参数+用法]
- 将整数转换为小端序字节流（32位/64位）。

[使用示例]
```python
payload = b"A" * 0x10 + p64(0x4005d0)
```

---

[函数/方法]
`u32` / `u64`

[参数+用法]
- 将字节流转换回整数。**注意：`u64` 必须传入 8 字节。**

[使用示例]
```python
# 接收地址并解包
addr = u64(io.recv(6).ljust(8, b"\x00"))
```

---

## 四、 字节处理与填充

[函数/方法]
`ljust` / `rjust`

[参数+用法]
- `data.ljust(target_len, pad_char)`：左对齐，右侧填充至目标长度。

[使用示例]
```python
# 泄露的地址通常是6字节，需要补齐到8字节才能用u64
leak = io.recv(6).ljust(8, b"\x00")
```

---

[函数/方法]
`b""` (字节前缀)

[参数+用法]
- 在字符串前加 `b`，将其声明为 `bytes` 对象。

[使用示例]
```python
payload = b"admin" + b"\x00" * 10
```

---

## 五、 ELF 符号与地址获取

[函数/方法]
`plt` / `got` / `symbols` (基于 `ELF` 对象)

[参数+用法]
- `elf.plt['func']`：获取函数 PLT 桩地址（用于调用）。
- `elf.got['func']`：获取函数 GOT 表项地址（用于泄露真实地址）。
- `elf.symbols['func']`：综合查找（通常优先指向 PLT）。

[使用示例]
```python
elf = ELF('./pwn')
puts_plt = elf.plt['puts']
puts_got = elf.got['puts']
```

---

## 六、 Libc 搜索与计算

[函数/方法]
`search` (配合 `next`)

[参数+用法]
- `next(libc.search(b"string"))`：在 libc 文件中寻找字符串的**相对偏移**。

[使用示例]
```python
libc = ELF('./libc.so.6')
bin_sh_offset = next(libc.search(b"/bin/sh"))
system_offset = libc.symbols['system'] # 获取函数在libc中的偏移
```

---

## 七、 调试与日志

[函数/方法]
`log.success` / `info`

[参数+用法]
- 在终端打印带格式的调试信息。

[使用示例]
```python
log.success("Libc Base -> " + hex(libc_base))
```

---

[函数/方法]
`pause` / `proc.pid`

[参数+用法]
- `pause()`：暂停脚本，方便手动 GDB 挂载。
- `io.proc.pid`：显示当前运行进程的 PID。

[使用示例]
```python
print("PID: ", io.proc.pid)
pause()
```

---

## 核心辨析与逻辑梳理

### 1. `elf.symbols` vs `elf.plt` vs `elf.got`
- **`elf.plt['puts']`**：是一个**地址**，指向程序里的“跳板”。Payload 里写它，相当于在代码里写 `call puts`。
- **`elf.got['puts']`**：是一个**地址**，指向存储 `puts` 真实位置的那个“格子”。Payload 里把它当作参数传给 `puts`，相当于“打印出这个格子里存的秘密”。
- **`elf.symbols['puts']`**：在 `ELF` 对象里通常等于 `plt` 地址；在 `libc` 对象里则是该函数相对于库起始位置的**偏移**。

### 2. 什么是“绝对地址”？
- **在 `elf` (主程序) 中**：如果 PIE 关闭，`plt/got/symbols` 拿到的都是内存绝对地址；如果 PIE 开启，拿到的是偏移。
- **在 `libc` (库文件) 中**：`symbols` 和 `search` 拿到的永远是**相对于 Libc 头部的偏移**。你必须加上 `libc_base` 才能得到当前进程的绝对地址。

### 3. 经典的 Libc 泄露公式
1. **泄露**：通过 `puts(elf.got['puts'])` 打印出 `puts` 的内存绝对地址 `real_puts`。
2. **算基址**：`libc_base = real_puts - libc.symbols['puts']`。
3. **找目标**：`real_system = libc_base + libc.symbols['system']`。
4. **找字符串**：`real_bin_sh = libc_base + next(libc.search(b"/bin/sh"))`。