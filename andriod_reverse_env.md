这是一份为你精心整理的 **M1 Pro 芯片安卓逆向环境搭建全手册**。它涵盖了从基础环境到静态分析，再到动态调试的全过程，并针对你今天遇到的实际问题进行了深度复盘。

---

# 📱 M1 Pro 安卓逆向工程环境搭建手册 (2024版)

## 0. 核心架构背景
*   **宿主机:** MacBook Pro (M1 Pro, ARM64 架构)
*   **虚拟机:** Windows 11 ARM (VMware)
*   **目标环境:** Android Emulator (ARM64 架构)
*   **优势:** M1 的 ARM 架构与安卓原生指令集一致，动态调试性能极佳，无需指令集转译。

---

## 1. 基础运行环境 (macOS Host)

### 1.1 Homebrew & Java
安卓逆向工具高度依赖 Java 环境。
*   **安装命令:**
    ```bash
    brew install openjdk@17
    ```
*   **环境变量配置 (坑点复盘):**
    安装后需手动将 Java 加入 PATH，否则终端无法识别 `java` 命令。

### 1.2 Android Studio & SDK
*   **安装:** 下载时务必选择 **"Mac with Apple chip"** 版本。
*   **ADB 配置:**
    ```bash
    echo 'export PATH=$HOME/Library/Android/sdk/platform-tools:$PATH' >> ~/.zshrc
    source ~/.zshrc
    ```

---

## 2. 静态分析工具: JADX-GUI
用于将 APK 的 DEX 文件反编译为 Java 源码。
*   **安装方式:**
    ```bash
    brew install jadx
    ```
*   **使用:** 终端输入 `jadx-gui` 直接运行。

---

## 3. 动态插桩工具: Frida (重点)

### 3.1 客户端安装 (macOS)
*   **错误回顾:** 现代 macOS 遵循 PEP 668，不允许全局 `pip install`。
*   **解决方案:** 使用 `pipx` 隔离安装。
    ```bash
    brew install pipx
    pipx ensurepath
    pipx install frida-tools
    ```

### 3.2 服务端安装 (Emulator)
*   **架构选择:** 必须下载 `frida-server-xx.x.x-android-arm64.xz`。
*   **部署命令:**
    ```bash
    adb push frida-server /data/local/tmp/
    adb shell "chmod 755 /data/local/tmp/frida-server"
    ```
*   **错误回顾:** 使用 `su -c` 启动报错 `invalid uid/gid`。
*   **解决方案:** 
    1. 执行 `adb root` 让守护进程直接获得 root。
    2. 直接运行：`adb shell "/data/local/tmp/frida-server &"`。

---

## 4. 动态调试工具: IDA Pro 9.2 (跨机联动)

这是最复杂的步骤，涉及 **虚拟机 - 宿主机 - 模拟器** 三方网络打通。

### 4.1 Server 端部署
*   **文件选择:** 选用 IDA 目录下的 `android_server` (默认为 ARM64)。
*   **部署:** 
    ```bash
    adb push android_server /data/local/tmp/as
    adb shell "chmod 755 /data/local/tmp/as"
    adb shell "su -c /data/local/tmp/as"
    ```

### 4.2 网络链路打通 (关键坑点)
*   **错误回顾 1:** 虚拟机尝试连接 `192.168.89.2` 报错“积极拒绝”。
    *   **原因:** `.2` 通常是虚拟网关，Mac 宿主机在虚拟网段的地址通常是 **`.1`**。
*   **错误回顾 2:** `adb forward` 默认只绑定 `127.0.0.1`，虚拟机无法访问。
    *   **解决方案:** 使用 `socat` 进行端口广播转发。
    ```bash
    brew install socat
    # 将 Mac 所有网卡的 23946 请求转发给本地 adb
    socat TCP-LISTEN:23946,fork,reuseaddr TCP:127.0.0.1:23946
    ```

### 4.3 附加进程 (Attach) 权限排除
*   **错误回顾:** IDA 提示 `could not attach... necessary privileges`。
*   **最终排查 Checklist:**
    1.  **SELinux:** 必须设为宽容模式：`adb shell "setenforce 0"`。
    2.  **Ptrace 冲突:** 检查是否有 Frida 脚本正在运行，如有需关闭，因为一个进程只能被一个调试器占用。
    3.  **ADB Root:** 必须执行过 `adb root`。

---

## 5. 总结：每日实战常用指令表

| 功能 | 命令 |
| :--- | :--- |
| **环境自检** | `adb devices` / `frida-ps -U` |
| **开启 Root 权限** | `adb root` |
| **关闭 SELinux** | `adb shell setenforce 0` |
| **IDA 端口转发** | `adb forward tcp:23946 tcp:23946` |
| **Mac 端口重定向** | `socat TCP-LISTEN:23946,fork,reuseaddr TCP:127.0.0.1:23946` |
| **Frida 注入启动** | `frida -U -f [包名] -l [脚本.js]` |

---

## 6. 导师寄语
你现在已经拥有了一套**价值数万元（硬件+商业软件）**且配置完美的逆向工作站。16G 内存环境下，建议：
1.  **做 Java 静态分析时:** 仅开启 JADX 和 Chrome 查文档。
2.  **做 Native 动态调试时:** 开启虚拟机 (IDA) 和模拟器，关闭 Android Studio 以节省内存。

**下一步建议:** 寻找一个简单的 `Crackme.apk`，练习如何通过 IDA 修改寄存器来绕过逻辑。祝你在逆向之路上越走越远！