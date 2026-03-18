#!/bin/bash
# CTF-Pwn 环境自动化配置脚本
# 作者：Cline AI Assistant
# 日期：2026-03-18

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "命令 $1 未找到，请先安装"
        return 1
    fi
    return 0
}

# 显示菜单
show_menu() {
    clear
    echo "========================================="
    echo "    CTF-Pwn 环境配置工具"
    echo "========================================="
    echo "1. 生成服务器端配置脚本"
    echo "2. 生成Mac端配置脚本"
    echo "3. 生成Dockerfile"
    echo "4. 生成docker-compose.yml"
    echo "5. 生成SSH配置模板"
    echo "6. 生成测试脚本"
    echo "7. 生成完整配置包"
    echo "8. 退出"
    echo "========================================="
    echo -n "请选择 (1-8): "
}

# 生成服务器端配置脚本
generate_server_script() {
    local script_file="setup-ctf-pwn-server.sh"
    
    cat > $script_file << 'EOF'
#!/bin/bash
# CTF-Pwn 服务器端自动化配置脚本

set -e

echo "=== CTF-Pwn 服务器端配置开始 ==="

# 1. 安装Docker
echo "[1/6] 安装Docker..."
if ! command -v docker &> /dev/null; then
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
    echo "Docker 安装完成"
else
    echo "Docker 已安装，跳过"
fi

# 2. 配置Docker镜像加速（国内用户）
echo "[2/6] 配置Docker镜像加速..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://registry.docker-cn.com", "https://docker.mirrors.ustc.edu.cn"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker

# 3. 安装Docker Compose
echo "[3/6] 安装Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose 安装完成"
else
    echo "Docker Compose 已安装，跳过"
fi

# 4. 创建项目目录
echo "[4/6] 创建项目目录..."
mkdir -p ~/ctf-pwn-environment/{ctf-problems,scripts,tools}
cd ~/ctf-pwn-environment

# 5. 生成Dockerfile
echo "[5/6] 生成Dockerfile..."
cat > Dockerfile << 'DOCKERFILE_EOF'
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
    vim nano netcat-openbsd openssh-server git unzip curl tmux wget sudo \
    build-essential gcc-multilib g++-multilib \
    gcc gdb gdbserver gdb-multiarch clang lldb make cmake \
    python3 python3-pip python3-venv python3-dev python3-setuptools \
    lib32z1 libc6-dbg libc6-dbg:i386 libgcc-s1:i386 \
    qemu-system-x86 qemu-user qemu-user-binfmt \
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

# 安装Python工具
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

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
DOCKERFILE_EOF

# 6. 生成docker-compose.yml
echo "[6/6] 生成docker-compose.yml..."
cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  ctf-pwn:
    build: .
    container_name: ctf-pwn-env
    restart: unless-stopped
    ports:
      - "25000:22"
    volumes:
      - ./ctf-problems:/ctf
      - ./scripts:/scripts
      - ./tools:/tools
    environment:
      - TZ=Asia/Shanghai
    stdin_open: true
    tty: true
COMPOSE_EOF

echo "=== 服务器端配置脚本生成完成 ==="
echo "请执行以下步骤："
echo "1. 运行: cd ~/ctf-pwn-environment"
echo "2. 构建镜像: docker-compose build"
echo "3. 启动容器: docker-compose up -d"
echo "4. 测试连接: ssh -p 25000 ctfuser@localhost (密码: ctf123456)"
EOF

    chmod +x $script_file
    log_success "服务器端配置脚本已生成: $script_file"
}

# 生成Mac端配置脚本
generate_mac_script() {
    local script_file="setup-ctf-pwn-mac.sh"
    
    cat > $script_file << 'EOF'
#!/bin/bash
# CTF-Pwn Mac端自动化配置脚本

set -e

echo "=== CTF-Pwn Mac端配置开始 ==="

# 1. 检查Homebrew
echo "[1/5] 检查Homebrew..."
if ! command -v brew &> /dev/null; then
    echo "安装Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "Homebrew 已安装"
fi

# 2. 安装必要工具
echo "[2/5] 安装必要工具..."
brew install \
    tmux \
    htop \
    wget \
    curl \
    jq \
    tree \
    rsync

# 3. 生成SSH密钥
echo "[3/5] 生成SSH密钥..."
if [ ! -f ~/.ssh/ctf_pwn_mac_key ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/ctf_pwn_mac_key -N ""
    echo "SSH密钥已生成: ~/.ssh/ctf_pwn_mac_key"
else
    echo "SSH密钥已存在，跳过生成"
fi

# 4. 创建本地目录
echo "[4/5] 创建本地目录..."
mkdir -p ~/CTF/{problems,scripts,tools,writeups,bin}

# 5. 生成SSH配置
echo "[5/5] 生成SSH配置..."
cat >> ~/.ssh/config << 'SSH_CONFIG_EOF'

# CTF-Pwn 环境配置
Host ctf-pwn-server
    HostName YOUR_SERVER_IP  # 请替换为您的服务器IP
    Port 25000
    User ctfuser
    IdentityFile ~/.ssh/ctf_pwn_mac_key
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    Compression yes
    ForwardAgent yes
    
Host ctf-pwn-root
    HostName YOUR_SERVER_IP  # 请替换为您的服务器IP
    Port 25000
    User root
    IdentityFile ~/.ssh/ctf_pwn_mac_key
    ServerAliveInterval 60
    ServerAliveCountMax 3
SSH_CONFIG_EOF

echo "=== Mac端配置脚本生成完成 ==="
echo "请执行以下步骤："
echo "1. 查看公钥: cat ~/.ssh/ctf_pwn_mac_key.pub"
echo "2. 将公钥添加到服务器的authorized_keys文件中"
echo "3. 编辑 ~/.ssh/config，将 YOUR_SERVER_IP 替换为您的服务器IP"
echo "4. 测试连接: ssh ctf-pwn-server"
EOF

    chmod +x $script_file
    log_success "Mac端配置脚本已生成: $script_file"
}

# 生成测试脚本
generate_test_script() {
    local script_file="test-ctf-environment.sh"
    
    cat > $script_file << 'EOF'
#!/bin/bash
# CTF-Pwn 环境测试脚本

set -e

echo "=== CTF-Pwn 环境测试开始 ==="

# 测试SSH连接
echo "[1/4] 测试SSH连接..."
if ssh -o ConnectTimeout=5 -p 25000 ctfuser@localhost echo "SSH连接成功"; then
    echo "✓ SSH连接测试通过"
else
    echo "✗ SSH连接测试失败"
    exit 1
fi

# 测试Docker容器状态
echo "[2/4] 测试Docker容器状态..."
if docker ps | grep -q ctf-pwn-env; then
    echo "✓ Docker容器运行正常"
else
    echo "✗ Docker容器未运行"
    exit 1
fi

# 测试基本工具
echo "[3/4] 测试基本工具..."
docker exec ctf-pwn-env bash -c "
    echo '测试Python...'
    python3 --version
    echo '测试pip...'
    /opt/ctf-venv/bin/pip list | grep pwn
    echo '测试gdb...'
    gdb --version
    echo '测试pwntools...'
    python3 -c \"from pwn import *; print('pwntools版本:', version)\"
"

# 测试示例题目
echo "[4/4] 测试示例题目..."
docker exec ctf-pwn-env bash -c "
    cd /ctf
    echo '创建测试程序...'
    cat > test.c << 'TEST_EOF'
#include <stdio.h>
int main() {
    printf(\"Hello CTF-Pwn!\\n\");
    return 0;
}
TEST_EOF
    gcc -o test test.c
    ./test
    rm -f test test.c
"

echo "=== 环境测试完成 ==="
echo "所有测试通过！CTF-Pwn环境已准备就绪。"
EOF

    chmod +x $script_file
    log_success "测试脚本已生成: $script_file"
}

# 生成完整配置包
generate_full_package() {
    local package_dir="ctf-pwn-config-package-$(date +%Y%m%d)"
    
    log_info "生成完整配置包: $package_dir"
    mkdir -p $package_dir
    
    # 生成所有文件
    generate_server_script
    generate_mac_script
    generate_test_script
    
    # 移动文件到包目录
    mv setup-ctf-pwn-server.sh $package_dir/
    mv setup-ctf-pwn-mac.sh $package_dir/
    mv test-ctf-environment.sh $package_dir/
    
    # 复制指南文档
    cp CTF-Pwn-Environment-Setup-Guide.md $package_dir/
    
    # 创建README
    cat > $package_dir/README.md << 'EOF'
# CTF-Pwn 环境配置包

## 包含文件

1. **CTF-Pwn-Environment-Setup-Guide.md** - 完整配置指南
2. **setup-ctf-pwn-server.sh** - 服务器端自动化配置脚本
3. **setup-ctf-pwn-mac.sh** - Mac端自动化配置脚本
4. **test-ctf-environment.sh** - 环境测试脚本

## 使用步骤

### 阶段一：服务器配置
1. 将 `setup-ctf-pwn-server.sh` 上传到您的x86 Linux服务器
2. 运行: `chmod +x setup-ctf-pwn-server.sh`
3. 运行: `./setup-ctf-pwn-server.sh`
4. 按照脚本提示完成配置

### 阶段二：Mac配置
1. 在Mac上运行: `chmod +x setup-ctf-pwn-mac.sh`
2. 运行: `./setup-ctf-pwn-mac.sh`
3. 按照脚本提示完成配置

### 阶段三：测试
1. 在服务器上运行: `./test-ctf-environment.sh`
2. 验证所有测试通过

## 注意事项

1. 请确保服务器有足够的磁盘空间（建议至少10GB）
2. 配置过程中需要稳定的网络连接
3. 首次构建Docker镜像可能需要较长时间
4. 请妥善保管SSH密钥

## 故障排除

如果遇到问题，请参考完整指南文档或联系技术支持。
EOF
    
    # 创建压缩包
    tar -czf $package_dir.tar.gz $package_dir/
    
    log_success "完整配置包已生成: $package_dir.tar.gz"
    log_info "包含文件:"
    ls -la $package_dir/
}

# 主菜单循环
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            generate_server_script
            read -p "按回车键继续..."
            ;;
        2)
            generate_mac_script
            read -p "按回车键继续..."
            ;;
        3)
            log_info "Dockerfile已在指南文档中提供"
            read -p "按回车键继续..."
            ;;
        4)
            log_info "docker-compose.yml已在指南文档中提供"
            read -p "按回车键继续..."
            ;;
        5)
            log_info "SSH配置模板已在指南文档中提供"
            read -p "按回车键继续..."
            ;;
        6)
            generate_test_script
            read -p "按回车键继续..."
            ;;
        7)
            generate_full_package
            read -p "按回车键