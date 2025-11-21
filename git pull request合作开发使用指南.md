## Guides:git tools utilizing in cooperative dev

####  实验环境：github+git+shell

### 1. 前期准备
* 账号 A (项目组长/维护者): 拥有原始合作库的所有权和合并权限。
* 账号 B (组员/开发者): 负责 Fork 库，开发功能，并提交 PR。
* 账户 C（组员/其他合作开发者）：负责fork库，开发功能，同时在B提交之后同步更新远程合作库的内容到C：fork库的main分支

A创建了一个test_cooperation库，并在其中添加了一些基础的文件
![](./git%20pull%20request%20img/截屏2025-11-21%20下午3.46.58.png)

B和C fork了这个库，并克隆到本地的文件夹


### 2. 组员创建分支、开发、并push到远程库的新分支里
创建新分支并转到新分支`git checkout -b tag/your_new_branch`
进行开发操作（略）
完成工作之后，
```bash
git add .
git commit -m "commit message"
git push origin tag/your_new_branch
```

（这里出现了一个问题，就是push的时候权限错误，原因是我全局配置的git用户是我的账号A，但是我现在应该作为账号B push回去，所以我该改用ssh连接远程库）
![](./git%20pull%20request%20img/Snipaste_2025-11-21_16-40-21.png)
解决方案在 [通过ssh密钥连接远程库](#ssh-key-connection) 模块


### 3. 组员pull request
进入github，进入你的fork的库，可以看到在main分支里面你的文件还是和合作库相同的，但是在你的tag/your_new_branch分支里面，已经有了你的开发之后的文件和更改

这个时候，请点击上方选项栏里面的pull request ，选择new，创建一个新的pull request，如下图，应该是
```
head repository: account B/your_fork_repo_name 
compare:tag/your_new_branch
---->
base repository: account A/cooperative_repo_name 
base:main
```
![](./git%20pull%20request%20img/Snipaste_2025-11-21_17-42-16.png)

记得pull request的时候做好说明，如：你实现了什么功能，你完成了什么工作，你修改了什么文件 etc.

完成之后，你会在你们的合作库的pull requests选项卡里面看到你的pull request
![](./git%20pull%20request%20img/Snipaste_2025-11-21_17-45-16.png)

### 4. 回到账号A：组长，查看pull request并审核，最后并入main分支
打开合作库的pull requests界面，找到刚才我们提交的request

作为合作库的拥有者和审查员，我们可以先检查他的代码，并进行评论，给出修改建议等
![](./git%20pull%20request%20img/Snipaste_2025-11-21_17-53-51.png)

如果审查通过并且没有冲突，我们就可以直接点击`Merge pull request`合并分支进入合作库的main分支了。完成合并之后，request会话会自动关闭

如果审查完毕之后，发现冲突，如果全部是对方的责任，请给他评论哪里出现了问题，让他整改之后再提交。这段时间内，无需审查者关闭request，只需等待对方将冲突处理之后，再push提交一次，合作库这边的request会自动更新，审查者可以二次审查

如果审查完毕之后，发现冲突，但是不是对方的问题，是双方有些文件存在冲突但是可以各自保留一部分，就需要审查员fetch对方的分支
1. 本地回到合作库main分支，检查是否处于最新状态
```bash
git checkout main
git pull origin main
```

2. 获取组员的pr分支
```bash
git remote add contributor-B git@github.com-contributor_account:contributor_account/fork_repo.git # git remote加上组员仓库的ssh链接或者https链接
git fetch contributor-B tag/contributor-new-branch # git fetch下来组员创建的分支
```

3. 尝试合并并处理冲突
```bash
git merge contributor-B/tag/contributor-new-branch # 先尝试合并
git status # 识别冲突文件
```
找到冲突文件之后，需要你手动打开冲突文件并进行对应的修改（保留和删除）

4. 标记“已解决”冲突并push到合作库的main分支，github会自动检测到这是一个分支合并，会把之前无法merge的pull request对话关闭
```bash
git add .
git commit # 注意：这里不需要填写commit信息，git会自动生成合并提交信息
git push origin main
```
上述操作成功后，远程github上PR的状态会为Merged并关闭

5. 清理本地的临时远程源
通过`git remote remove contributor-B`指令移除审查员本地git配置里面对组员fork库分支的远程链接

### 5. 来到其他合作开发者，例如账户C，同步合并PR之后的远程合作库
C先cd进工作项目文件夹，利用`git remote add upstream `添加原始合作库url
ssh：`git remote add upstream git@github.com-AccountA:AccountA/Collaborative-Project.git`
https：`git remote add upstream https://github.com/AccountA/Collaborative-Project.git`
通过`git remote -v`验证，看是否有(upstream)的url配置，如果有，说明配置成功

C再将自己的fork库工作目录切换回main分支，利用`git pull upstream main`更新

利用`git push origin main`将main分支的更新同步远程fork库，保证本地和远程两个项目文件库的main函数同步且干净

* 如果想要将更新后的main合并入C现在正在开发的分支feature/Cdev，还需要进行加下来的操作
1. `git checkout feature/Cdev`切换到开发分支
2. `git merge main`尝试合并，如有冲突则继续以下操作
3. 通过`git status`查看冲突文件，并手动修改
4. 通过`git add .`暂存和`git commit -m "MERGE: Sync with the upstream main to include B's dev"`提交保存合并
5. 最后在开发完毕之后，这些修改会随你的开发文件一起被push和pull request

<h3 id="ssh-key-connection">* 通过ssh密钥连接远程库(macos linux等类unix操作系统版)</h3>
1. 首先在本地终端生成ssh密钥，用指令` ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_your_accout -C "your_account_email@example.com"`
这里几个选项的表示分别为:

```c
//  -t 指定算法 (ed25519 是推荐的现代算法,也可以用rsa等经典非对称加密算法)
//  -f 指定文件名 (我们使用 your_account_rsa 或 your_account_ed25519)
//  -C 添加注释 (用于识别是哪个账号的密钥),可以随意填写
```

添加过程中会让你设置一个访问这个密钥的密码，请记住它，之后也是有用的

2. 将公钥添加到对应的github账号上面，注意添加内容要严格复制粘帖公钥文件里面的内容
可以通过命令`cat ~/.ssh/id_ed25519_your_account.pub`来查看
结果应该如`ssh-ed25519 jfjalssdfd(这一长串都是你的公钥)jffasfaaseecdxcsalfs your_account_email@example.com`

3. github上面把公钥填进去之后，再回到终端上面来，通过`vim ~/.ssh/config`查看整台机器保存和配置过的ssh连接账号，在里面添加
```bash
# 这里Host项里面的your_account你可以随便填，但我建议你填你的github账号用户名
Host github.com-your_account
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_your_account
  # 启用 SSH 代理自动记住密码
  UseKeychain yes
```
vim的编辑和保存：按`I`进入insert模式编辑，按`esc`退出编辑模式，输入`:wq`保存并退出,`:q!`强制退出不保存

4. cd回到你的项目开发文件夹，通过
`git remote set-url origin git@github.com-your_account:your_acount/Collaborative-Project.git`
配置git远程连接ssh链接，其中第一个your_account是你在`~/.ssh/config`文件里面Host处写过的，第二个your_account应该是你的准确的github账号用户名称，`Collaborative-Project`为你的项目库名称

* 通过`git remote -v`查看，发现已经改好了
在push之前先ssh测试一下链接：`ssh -T git@github.com-your_account`
测试成功之后，直接git继续push即可
![](./git%20pull%20request%20img/Snipaste_2025-11-21_16-52-15.png)