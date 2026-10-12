#!/usr/bin/env bash
# 可复现验证：includeIf hasconfig 的通配符语义，以及 scp 式地址为什么常用写法不生效
# 直接跑：bash docs/the-scp-glob-trap.sh
set -u

SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
git init -q "$SB/repo"
cat > "$SB/gh-identity" <<'EOF'
[user]
	name = ShouldApply
	email = should@example.com
EOF

check() { # check <remote-url> <pattern>
  git -C "$SB/repo" remote set-url origin "$1" 2>/dev/null
  git -C "$SB/repo" remote add origin "$1" 2>/dev/null
  cat > "$SB/cfg" <<EOF
[user]
	name = Fallback
	email = fallback@example.com
[includeIf "hasconfig:remote.*.url:$2"]
	path = $SB/gh-identity
EOF
  GIT_CONFIG_GLOBAL="$SB/cfg" git -C "$SB/repo" config user.email
}

printf '%-42s %-34s %s\n' "remote 值" "includeIf 模式" "解析出的 email"
printf '%s\n' "------------------------------------------------------------------------------------------"
for row in \
  "https://github.com/me/x.git|https://github.com/**" \
  "https://github.com/me/x.git|https://github.com/*" \
  "ssh://git@github.com/me/x.git|ssh://git@github.com/**" \
  "git@github.com:me/x.git|git@github.com:**" \
  "git@github.com:me/x.git|git@github.com:*" \
  "git@github.com:me/x.git|git@github.com:*/*" \
  "git@github.com:me/x.git|git@github.com:*/**" \
  "git@github.com:me/group/x.git|git@github.com:*/*" \
  "git@github.com:me/group/x.git|git@github.com:*/**"
do
  url=$(printf '%s' "$row" | cut -d'|' -f1)
  pat=$(printf '%s' "$row" | cut -d'|' -f2)
  got=$(check "$url" "$pat")
  case "$got" in
    should@example.com) verdict="命中规则" ;;
    *) verdict="未命中 → 落回兜底" ;;
  esac
  printf '%-42s %-34s %s\n' "$url" "$pat" "$got ($verdict)"
done

cat <<'EOF'

结论（git 2.39.2 / macOS 实测）：
  1. 模式按“路径”语义匹配：* 不跨越 /，** 只有在自成一段（前面是 / 或行首）时才是“跨段通配”。
  2. 因此 https://host/** 与 ssh://git@host/** 正常；
     而 scp 式 git@host:owner/repo 里冒号后的 owner/repo 含 /，
     git@host:** 与 git@host:* 都不命中 —— 且不报错，静默用兜底身份提交。
  3. scp 式正确写法：git@host:*/**（同时覆盖 owner/repo 与子组 owner/group/repo）。
     只写 git@host:*/* 会漏掉带子组的仓库。
EOF
