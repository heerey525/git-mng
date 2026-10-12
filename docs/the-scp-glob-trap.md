# `git@github.com:**` 为什么不生效：includeIf hasconfig 的通配符陷阱

## TL;DR

按远程地址自动切换提交身份，是 Git 2.36 引入的 `includeIf "hasconfig:..."` 条件包含。网上流传的写法（包括很多中文教程）长这样：

```gitconfig
[includeIf "hasconfig:remote.*.url:git@github.com:**"]
	path = ~/.gitconfig-github
```

**它对 `git@github.com:you/repo.git` 形式的远程地址完全不生效，而且不报任何错**——你的提交会静默使用兜底身份。这正是"我配了自动切换，怎么还是串号"的根因。

正确写法（git-mng `init` 自动生成的就是这个）：

```gitconfig
[includeIf "hasconfig:remote.*.url:git@github.com:*/**"]
	path = ~/.gitconfig-github
```

## 复现

```bash
bash docs/the-scp-glob-trap.sh
```

它在一个临时沙箱里反复改写 `remote.origin.url`，用不同的 `includeIf` 模式读回 `user.email`，实测输出（git 2.39.2 / macOS）：

| remote 值 | includeIf 模式 | 结果 |
|---|---|---|
| `https://github.com/me/x.git` | `https://github.com/**` | 命中 |
| `https://github.com/me/x.git` | `https://github.com/*` | **未命中** |
| `ssh://git@github.com/me/x.git` | `ssh://git@github.com/**` | 命中 |
| `git@github.com:me/x.git` | `git@github.com:**` | **未命中** |
| `git@github.com:me/x.git` | `git@github.com:*` | **未命中** |
| `git@github.com:me/x.git` | `git@github.com:*/*` | 命中 |
| `git@github.com:me/group/x.git` | `git@github.com:*/*` | **未命中** |
| `git@github.com:me/group/x.git` | `git@github.com:*/**` | 命中 |

## 原因

`hasconfig` 的值匹配走的是 **路径语义的通配**（wildmatch 的 `WM_PATHNAME` 行为）：

- `*` **不跨越 `/`**。所以 `https://github.com/*` 匹配不了 `https://github.com/me/x.git`，因为 `me/x.git` 里还有一个 `/`。
- `**` 只有"自成一段"时（前面是 `/` 或位于串首）才升级为"跨段通配"。`https://github.com/**` 里的 `**` 前面是 `/`，所以生效；`git@github.com:**` 里的 `**` 前面是 `:`，**不是一段开头**，于是被当成两个连续的 `*`，等价于单个 `*`，仍然跨不过 `/`。

scp 式地址 `git@host:owner/repo.git` 冒号后面天然含 `/`，所以任何 `host:**` / `host:*` 写法都匹配不上。而 `*/**` 把 `owner` 用 `*` 吃掉、`/` 对齐、`**` 自成一段吃掉 `repo.git` 及其可能的子组层级，才覆盖完整。

## 附带坑：规则块必须写在 `[user]` 之后

Git 的配置是"后写入者胜出"。把 `includeIf` 块放在 `[user]` 之前，包含进来的身份会被后面的 `[user]` 覆盖掉，看起来"配了但没用"。git-mng 生成的块固定追加在文件末尾，并用测试项 `规则块写在 [user] 之后（覆盖才生效）` 锁住。

## 另一处静默失效：仓库自己的局部配置优先

`git config --local user.email` 的优先级高于全局文件里的任何 `includeIf`。清理历史遗留的局部配置后，自动切换才会真正生效：

```bash
git config --local --unset user.name
git config --local --unset user.email
git-mng identity    # 逐仓库确认到底谁在生效
```
