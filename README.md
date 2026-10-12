# git-mng

> **English (TL;DR)** — A zero-dependency single-file bash tool for macOS that keeps multiple
> Git forges (GitHub / Gitee / self-hosted GitLab) straight on one machine: commit identity is
> picked automatically from `remote.origin.url`, network routes (direct / mirror / SSH) are
> benchmarked before you switch them, and `doctor` tells you whether credentials, timeouts and
> identity rules are actually in effect for every local repo. It does not proxy traffic or
> "accelerate" GitHub — see [docs/the-scp-glob-trap.md](docs/the-scp-glob-trap.md) for the
> subtle `includeIf` glob bug that makes most published recipes silently fail on
> `git@host:owner/repo` remotes.

一台 Mac 上同时管 GitHub、Gitee、公司自建 Git 时，最容易出的三类事故：

1. **提交身份串号**——所有仓库共用一个全局 `user.email`，开源仓库里出现了公司邮箱，或者反过来。
2. **网络路由选错**——`https://github.com` 间歇连不上，镜像前缀被写死进每个仓库的 remote，代理规则还顺手把推送通道堵死。
3. **凭据半坏**——令牌过期后钥匙串里留下一条坏凭据，每次操作都弹认证失败，你却不知道它存在。

`git-mng` 是一个零依赖的单文件 bash 工具，只解决这三件事：**按远程地址自动切换提交身份**、**实测哪条链路能用并一键切换**、**把本机所有仓库的凭据与身份状态体检出来**。它不代理流量、不下载加速、不替你管理代码托管平台的 API。

- 平台：macOS（凭据后端用系统钥匙串）
- 依赖：`git >= 2.36`、系统自带 `bash`（3.2 即可）、`ssh`、`curl`、`security`
- 不改动任何仓库的工作区与提交历史；写配置前先备份，并可一条命令撤销

## 安装

```bash
git clone git@github.com:heerey525/git-mng.git   # 或 https://github.com/heerey525/git-mng.git
cd git-mng && ./install.sh
```

`install.sh` 只做三件事：检查依赖、把 `bin/git-mng` 放进 `~/.local/bin`、跑一遍自测。它会打印 PATH 检查结果，如果 `~/.local/bin` 不在 PATH 里会提示你怎么加。

卸载：删掉 `~/.local/bin/git-mng`，再 `git-mng init --revert` 移除写进 `~/.gitconfig` 的规则块。

## 快速上手

```bash
# 1) 声明你有哪些平台、各平台用什么身份（交互式，会备份 ~/.gitconfig）
git-mng init

# 2) 复查：每个本机仓库当前会用什么身份提交
git-mng identity

# 3) 网络抽风时，先看哪条链路能用，再切过去
git-mng route bench
git-mng route ssh

# 4) 全量体检（配置 + 身份 + 凭据 + 连通性）
git-mng doctor
```

## 命令

| 命令 | 作用 |
|---|---|
| `git-mng init` | 生成「按 `remote.origin.url` 自动加载提交身份」的规则块，写入 `~/.gitconfig`（先备份）。`--dry-run` 只打印不写；`--revert` 移除规则块 |
| `git-mng doctor` | 体检：git 版本、凭据后端、`credential.helper`、超时兜底、`safe.directory`、访问路由、各主机凭据/SSH/连通性、身份一致性 |
| `git-mng identity` | 逐仓库打印生效的 `user.name`/`user.email`，并和期望值比对，标出不一致及原因 |
| `git-mng repos [--fetch]` | 按主机分组列本机仓库：分支、脏文件数、领先/落后、remote 里残留的镜像前缀 |
| `git-mng fix-ssh [host]` | 自有账号的仓库转 `git@host:` 以便推送；第三方仓库还原成直连 HTTPS |
| `git-mng route bench` | 用同一个公共仓库，把 `direct` / `proxy` / `ssh` 各测 3 次，打印成功率 |
| `git-mng route ssh\|proxy\|direct\|status` | 互斥地设置 `url.<...>.insteadOf` 重写；`status` 查看当前路由 |
| `git-mng login <host>` | 交互录入该主机的 HTTPS 凭据（令牌不回显），先用真实 `ls-remote` 验证，失败自动从钥匙串撤销 |
| `git-mng probe-url [host]` | 打印 `doctor` 对该主机的探测方式与地址：路由主机走链路实测，其余主机只测 HTTPS 可达性 |
| `git-mng version` | 版本与生效配置自检 |

## 配置

可选文件 `~/.config/git-mng/config`，就是 shell 语法，直接 source：

```sh
GITMNG_HOSTS="github.com gitee.com gitlab.example.com"   # 参与身份/凭据检查的主机
GITMNG_OWNER_ACCOUNT="your-gh-login"                    # fix-ssh 用它区分自有/第三方
GITMNG_SCAN_ROOTS="$HOME/code $HOME/projects"           # 仓库扫描根目录
GITMNG_SCAN_MAXDEPTH=4
GITMNG_GHPROXY="https://gh-proxy.com/"                  # route proxy 的镜像前缀（换成你自己的）
GITMNG_ROUTE_HOST="github.com"                          # 路由重写作用的主机
GITMNG_PROBE_REPO="octocat/Hello-World"                 # 路由实测用的公共小仓库（仅 ROUTE_HOST 用它）
```

身份文件在 `~/.config/git-mng/identity/<host>`，一个主机一个，内容就是 `[user] name/email`。

## 为什么要用 `*/**` 而不是 `**`

网上流传的 `includeIf` 按远程地址切身份的写法基本都是这样：

```gitconfig
[includeIf "hasconfig:remote.*.url:git@github.com:**"]
	path = ~/.gitconfig-github
```

**这条对 `git@github.com:you/repo.git` 完全不生效，而且不报错。** 详见 [docs/the-scp-glob-trap.md](docs/the-scp-glob-trap.md)（含可复现的最小验证）。`git-mng init` 生成的规则块已经把三种 URL 形式都覆盖上，并用自测锁住这个行为。

## 与相邻工具的分工

- 想要浏览器/ releases / raw 文件的整体加速：用 [FastGithub](https://github.com/dotnetcore/FastGithub)、DevSidecar 这类代理工具。`git-mng route` 只负责在 git 这一层告诉你哪条链路当前可用，并在三者间切换。
- 想要 OAuth、2FA、多账号自动登录：用官方 [Git Credential Manager](https://github.com/GitCredentialManager/git-credential-manager)。`git-mng login` 是它的轻量替代，适合「只想把一枚私人令牌塞进钥匙串并且失败别留残渣」这种小需求；两者不冲突。
- 本工具的存在意义是**诊断与配置的一致性**：谁在用什么身份、哪条链路能用、凭据是不是坏的，一条命令看清。

## 已知边界

- 仅 macOS。Linux 的 `libsecret` 与 Windows 的凭据管理器后端尚未实现；`doctor` 会在非 macOS 上明确告诉你这一点。
- 只读探测为主。`fix-ssh` 会改 remote URL（打印每一项变更），`init` 会改 `~/.gitconfig`（先备份，可 `--revert`）。
- 仓库扫描靠目录遍历（`find`），不查数据库；`GITMNG_SCAN_ROOTS` 越精确越快。
- 子模块、worktree 的 `.git` 是文件而非目录，不在扫描范围内。
- 提交身份规则只影响**此后新建的提交**；历史提交要改只能 rebase 重写。

## 开发

```bash
./tests/run.sh     # 32 项自测，全程临时 HOME 沙箱，不碰真实配置和网络
```

`bash 3.2` 兼容（不用关联数组等 4.x 特性），CI 里建议 `shellcheck -s bash`。

## 协议

MIT，见 [LICENSE](LICENSE)。
