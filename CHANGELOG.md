# Changelog

遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## 0.1.0

首次公开版本，仅支持 macOS。

### Added

- `init`：按 `remote.origin.url` 生成提交身份自动切换规则块（写入 `~/.gitconfig`，先备份，支持 `--dry-run` / `--revert`）。同时覆盖 `https://host/**`、`ssh://git@host/**`、`git@host:*/**` 三种形式，避开常见教程对 scp 式地址静默失效的坑。
- `doctor`：体检 git 版本与 `hasconfig` 支持、`credential.helper`、超时兜底、`safe.directory`、访问路由、各主机钥匙串凭据 / SSH / 连通性、身份一致性。
- `identity`：逐仓库打印生效的 `user.name`/`user.email` 并与期望值比对，标出不一致及其成因（局部覆盖 / 主机未配置）。
- `repos`：按主机分组列本机仓库（分支、脏文件数、领先/落后），识别被写死进 remote 的镜像前缀残留。
- `fix-ssh`：自有账号仓库转 `git@host:` 以恢复推送通道；第三方仓库还原直连 HTTPS。
- `route bench` / `route ssh|proxy|direct|status`：用同一公共仓库实测 direct / 镜像 / SSH 三条链路成功率（测量时绕过全局配置，避免当前路由的重写规则污染结果），并互斥地设置 `url.<...>.insteadOf`。
- `login <host>`：交互录入 HTTPS 凭据（不回显），先经真实 `ls-remote` 验证，失败自动从钥匙串撤销，不留半坏凭据。
- `probe-url [host]`：打印 `doctor` 对某主机的探测方式与地址。只有 `GITMNG_ROUTE_HOST` 会用 `GITMNG_PROBE_REPO` 做链路实测，其余主机只测 HTTPS 可达性——拿 GitHub 的公共仓库去 Gitee 做 `ls-remote` 必然失败，多平台用户不应看到那条假警报。
- `tests/run.sh`：30 项自测，全程临时 HOME 沙箱，不触碰真实配置与网络。
- `docs/the-scp-glob-trap.sh`：可执行的通配符行为验证，输出与文档表格一致。
