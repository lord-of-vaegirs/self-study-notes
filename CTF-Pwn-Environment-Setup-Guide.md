# CTF-Pwn 环境混合配置指南（服务器Docker + Mac SSH）

## 📋 概述

本指南详细说明如何在x86 Linux服务器上配置CTF-Pwn Docker环境，并通过MacBook Pro（ARM架构）通过SSH连接使用。

### 硬件架构
- **服务器**: x86 Linux（最佳兼容性）
- **客户端**: MacBook Pro ARM（通过SSH连接）

### 优势
- ✅ 最佳x86架构兼容性
- ✅ 服务器性能优势
- ✅ Mac本地开发体验
- ✅ 环境隔离与安全

---

## 🚀 阶段一：服务器端配置（x86 Linux服务器）

### 步骤1：服务器环境准备

#### 1.1 登录服务器
```bash
ssh username@your-server-ip
```

#### 1.2 安装Docker
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# 验证安装
sudo docker --version
```

#### 1.3 配置Docker镜像加速（国内用户）
```bash
# 创建Docker配置目录
sudo mkdir -p /etc/docker

# 配置镜像加速器（使用阿里云）
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://your-mirror.mirror.aliyuncs.com"]
}
EOF

# 重启Docker服务
sudo systemctl daemon-reload
sudo systemctl restart docker
```

#### 1.4 安装Docker Compose
```bash
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version
```

### 步骤2：创建CTF-Pwn Docker环境

#### 2.1 创建项目目录
```bash
mkdir -p ~/ctf-pwn-environment
cd ~/ctf-pwn-environment
```

#### 2.2 创建Dockerfile
```dockerfile
# ~/ctf-pwn-environment/Dockerfile
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 使用国内镜像源
RUN sed -i "s|http://archive.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g" /etc/apt/sources.list && \
    sed -i "s|http://security.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g" /etc/apt/sources.list

# 添加i386架构支持
RUN dpkg --add-architecture i386

# 更新并安装基础软件
RUN apt-get -y update && apt-get upgrade -y && \
    apt-get install -y \
    # 基础工具
    vim nano netcat-openbsd openssh-server git unzip curl tmux wget sudo \
    # 开发工具
    build-essential gcc-multilib g++-multilib \
    gcc gdb gdbserver gdb-multiarch clang lldb make cmake \
    # Python环境
    python3 python3-pip python3-venv python3-dev python3-setuptools \
    # 32位库支持
    lib32z1 libc6-dbg libc6-dbg:i386 libgcc-s1:i386 \
    # QEMU模拟器
    qemu-system-x86 qemu-user qemu-user-binfmt \
    # 其他依赖
    libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev \
    bison flex

# 配置SSH服务
RUN mkdir /var/run/sshd && \
    echo 'root:ctf123456' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config && \
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config

# 创建非root用户
RUN useradd -m -s /bin/bash ctfuser && \
    echo 'ctfuser:ctf123456' | chpasswd && \
    usermod -aG sudo ctfuser

# 设置Python虚拟环境
RUN python3 -m venv /opt/ctf-venv && \
    echo 'source /opt/ctf-venv/bin/activate' >> /home/ctfuser/.bashrc

# 安装Python工具（使用国内PyPI镜像）
RUN /opt/ctf-venv/bin/pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && \
    /opt/ctf-venv/bin/pip install --upgrade pip && \
    /opt/ctf-venv/bin/pip install \
    pwntools \
    ropgadget \
    z3-solver \
    ropper \
    unicorn \
    keystone-engine \
    capstone \
    angr \
    LibcSearcher

# 安装pwndbg
RUN git clone https://github.com/pwndbg/pwndbg /opt/pwndbg && \
    cd /opt/pwndbg && ./setup.sh

# 配置gdbinit
RUN echo "source /opt/pwndbg/gdbinit.py" >> /home/ctfuser/.gdbinit && \
    chown -R ctfuser:ctfuser /home/ctfuser/.gdbinit

# 创建工作目录
RUN mkdir /ctf && chown -R ctfuser:ctfuser /ctf

# 暴露SSH端口
EXPOSE 22

# 启动SSH服务
CMD ["/usr/sbin/sshd", "-D"]
```

#### 2.3 创建docker-compose.yml（可选但推荐）
```yaml
# ~/ctf-pwn-environment/docker-compose.yml
version: '3.8'

services:
  ctf-pwn:
    build: .
    container_name: ctf-pwn-env
    restart: unless-stopped
    ports:
      - "25000:22"  # SSH端口映射
    volumes:
      - ./ctf-problems:/ctf  # 挂载CTF题目目录
      - ./scripts:/scripts    # 挂载脚本目录
    environment:
      - TZ=Asia/Shanghai
    stdin_open: true
    tty: true
```

#### 2.4 构建Docker镜像
```bash
# 构建镜像（使用缓存加速）
cd ~/ctf-pwn-environment
docker build -t ctf-pwn-env:latest .

# 或者使用docker-compose构建
docker-compose build
```

#### 2.5 创建并运行容器
```bash
# 使用docker run
docker run -d \
  --name ctf-pwn-container \
  -p 25000:22 \
  -v ~/ctf-problems:/ctf \
  -v ~/scripts:/scripts \
  --restart unless-stopped \
  ctf-pwn-env:latest

# 或者使用docker-compose
docker-compose up -d
```

### 步骤3：配置SSH访问

#### 3.1 生成SSH密钥对（在服务器上）
```bash
# 在服务器上生成密钥对
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ctf_pwn_key -N ""

# 将公钥复制到容器中
docker cp ~/.ssh/ctf_pwn_key.pub ctf-pwn-container:/tmp/
docker exec ctf-pwn-container bash -c "mkdir -p /root/.ssh && cat /tmp/ctf_pwn_key.pub >> /root/.ssh/authorized_keys"
docker exec ctf-pwn-container bash -c "mkdir -p /home/ctfuser/.ssh && cat /tmp/ctf_pwn_key.pub >> /home/ctfuser/.ssh/authorized_keys"
```

#### 3.2 配置SSH服务
```bash
# 进入容器配置
docker exec -it ctf-pwn-container bash

# 在容器内设置权限
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
chown -R ctfuser:ctfuser /home/ctfuser/.ssh
chmod 700 /home/ctfuser/.ssh
chmod 600 /home/ctfuser/.ssh/authorized_keys

# 退出容器
exit
```

#### 3.3 测试SSH连接
```bash
# 从服务器本地测试
ssh -p 25000 root@localhost
# 密码：ctf123456

ssh -p 25000 ctfuser@localhost
# 密码：ctf123456
```

---

## 🍎 阶段二：Mac端配置（ARM MacBook Pro）

### 步骤4：Mac环境准备

#### 4.1 安装必要的工具
```bash
# 确保SSH客户端已安装（macOS自带）
ssh -V

# 安装Homebrew（如果尚未安装）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 安装有用的工具
brew install \
  tmux \
  screen \
  htop \
  netcat \
  wget \
  curl \
  jq \
  yq \
  tree
```

#### 4.2 配置SSH密钥对
```bash
# 在Mac上生成SSH密钥对
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ctf_pwn_mac_key -N ""

# 查看公钥
cat ~/.ssh/ctf_pwn_mac_key.pub

# 将公钥复制到服务器（需要手动操作）
# 1. 将公钥内容复制到剪贴板
# 2. 登录到服务器，将公钥添加到容器的authorized_keys文件中
```

#### 4.3 配置SSH配置文件
```bash
# 编辑SSH配置文件
nano ~/.ssh/config
```

添加以下内容：
```ssh-config
# CTF-Pwn 环境配置
Host ctf-pwn-server
    HostName your-server-ip  # 替换为您的服务器IP
    Port 25000
    User ctfuser
    IdentityFile ~/.ssh/ctf_pwn_mac_key
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    Compression yes
    ForwardAgent yes
    
Host ctf-pwn-root
    HostName your-server-ip  # 替换为您的服务器IP
    Port 25000
    User root
    IdentityFile ~/.ssh/ctf_pwn_mac_key
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

#### 4.4 设置本地开发环境
```bash
# 创建本地工作目录
mkdir -p ~/CTF/{problems,scripts,tools,writeups}

# 创建同步脚本
cat > ~/CTF/sync-to-server.sh << 'EOF'
#!/bin/bash
# 同步本地文件到服务器
rsync -avz -e "ssh -p 25000" \
    ~/CTF/problems/ \
    ctfuser@your-server-ip:/ctf/
EOF

chmod +x ~/CTF/sync-to-server.sh
```

### 步骤5：连接与使用

#### 5.1 测试SSH连接
```bash
# 测试连接（首次连接需要确认指纹）
ssh ctf-pwn-server

# 测试root连接
ssh ctf-pwn-root
```

#### 5.2 配置VS Code Remote SSH
1. 安装VS Code扩展：**Remote - SSH**
2. 按 `Cmd+Shift+P`，输入 "Remote-SSH: Connect to Host"
3. 选择 "ctf-pwn-server"
4. 首次连接需要输入密码：`ctf123456`

#### 5.3 配置文件同步
```bash
# 安装rsync（如果尚未安装）
brew install rsync

# 创建同步脚本
cat > ~/CTF/sync-scripts.sh << 'EOF'
#!/bin/bash
# 双向同步脚本
LOCAL_DIR="~/CTF/scripts"
REMOTE_DIR="/scripts"
SERVER="ctfuser@your-server-ip"
PORT="25000"

echo "同步脚本到服务器..."
rsync -avz -e "ssh -p $PORT" "$LOCAL_DIR/" "$SERVER:$REMOTE_DIR/"

echo "从服务器同步脚本..."
rsync -avz -e "ssh -p $PORT" "$SERVER:$REMOTE_DIR/" "$LOCAL_DIR/"
EOF

chmod +x ~/CTF/sync-scripts.sh
```

---

## ⚙️ 阶段三：优化与测试

### 步骤6：环境优化

#### 6.1 配置tmux（推荐）
```bash
# 在容器内安装和配置tmux
docker exec -it ctf-pwn-container bash

# 安装tmux插件
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# 创建tmux配置
cat > ~/.tmux.conf << 'EOF'
# 启用鼠标支持
set -g mouse on

# 设置前缀键
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# 分割窗口
bind | split-window -h
bind - split-window -v

# 重新加载配置
bind r source-file ~/.tmux.conf

# 插件管理
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'

# 初始化TMUX插件管理器
run '~/.tmux/plugins/tpm/tpm'
EOF

# 为ctfuser用户也配置
cp ~/.tmux.conf /home/ctfuser/.tmux.conf
chown ctfuser:ctfuser /home/ctfuser/.tmux.conf
```

#### 6.2 配置开发工具链
```bash
# 在容器内配置开发环境
docker exec -it ctf-pwn-container bash

# 为ctfuser配置bashrc
cat >> /home/ctfuser/.bashrc << 'EOF'

# CTF环境配置
export PATH="/opt/ctf-venv/bin:$PATH"
export EDITOR=vim

# 别名配置
alias ll='ls -la'
alias gdb='gdb -q'
alias py='python3'
alias pip='/opt/ctf-venv/bin/pip'

# 工作目录
cd /ctf

# 欢迎信息
echo "=== CTF-Pwn 环境已就绪 ==="
echo "Python虚拟环境: /opt/ctf-venv"
echo "Pwntools版本: $(python3 -c "import pwn; print(pwn.__version__)" 2>/dev/null || echo "未安装")"
echo "当前用户: $(whoami)"
echo "工作目录: $(pwd)"
echo "=========================="
EOF
```

#### 6.3 配置图形界面转发（可选）
```bash
# 在Mac上配置SSH图形转发
# 编辑SSH配置
nano ~/.ssh/config
```

添加X11转发配置：
```ssh-config
Host ctf-pwn-server
    # ... 现有配置 ...
    ForwardX11 yes
    ForwardX11Trusted yes
    XAuthLocation /opt/X11/bin/xauth
```

### 步骤7：测试验证

#### 7.1 测试基本Pwn工具
```bash
# 连接到容器
ssh ctf-pwn-server

# 测试Python环境
python3 --version
pip list | grep pwn

# 测试pwntools
python3 -c "from pwn import *; print('pwntools版本:', version)"

# 测试gdb和pwndbg
gdb --version
python3 -c "import gdb; print('GDB Python支持: 正常')" 2>/dev/null || echo "GDB Python支持: 异常"
```

#### 7.2 运行示例CTF题目
```bash
# 创建测试题目
cat > /ctf/test_challenge.c << 'EOF'
#include <stdio.h>
#include <string.h>

void vulnerable_function() {
    char buffer[64];
    printf("输入你的payload: ");
    gets(buffer);
    printf("你输入了: %s\n", buffer);
}

int main() {
    vulnerable_function();
    return 0;
}
EOF

# 编译测试程序
gcc -fno-stack-protector -no-pie -z execstack -o /ctf/test_challenge /ctf/test_challenge.c

# 创建利用脚本
cat > /ctf/exploit.py << 'EOF'
#!/usr/bin/env python3
from pwn import *

context.binary = './test_challenge'
context.log_level = 'debug'

# 本地测试
p = process('./test_challenge')
p.sendline(b'A' * 100)
print(p.recvall())
EOF

# 运行利用脚本
python3 /ctf/exploit