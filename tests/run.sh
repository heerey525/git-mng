#!/usr/bin/env bash
# git-mng 自测：全程在临时 HOME 沙箱里跑，绝不碰真实 ~/.gitconfig 或网络。
# 用法: tests/run.sh   （退出码 0 = 全部通过）
set -u

TOOL="$(cd "$(dirname "$0")/.." && pwd)/bin/git-mng"
[ -x "$TOOL" ] || { echo "找不到可执行的 $TOOL"; exit 1; }

pass=0; fail=0
eq() { # eq <描述> <期望> <实际>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"
  else fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n       期望=[%s] 实际=[%s]\n' "$1" "$2" "$3"; fi
}
has() { # has <描述> <片段> <文本>
  case "$3" in *"$2"*) pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1" ;;
    *) fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n       文本里找不到 [%s]\n' "$1" "$2" ;; esac
}

SB=$(mktemp -d)/home
mkdir -p "$SB"
cat > "$SB/.gitconfig" <<'EOF'
[user]
	name = Fallback
	email = fallback@example.com
EOF

export HOME="$SB"
export GITMNG_HOSTS="gh.test gl.test"
export GITMNG_SCAN_ROOTS="$SB/code"
export GITMNG_OWNER_ACCOUNT="me"

mkrepo() { # mkrepo <name> <remote-url 或 NONE>
  d="$SB/code/$1"; mkdir -p "$d"
  git -C "$d" init -q
  [ "$2" = "NONE" ] || git -C "$d" remote add origin "$2"
  printf '%s' "$d"
}
mkr() { # mkr <name> <url> [局部 name email]
  d="$SB/code/$1"; mkdir -p "$d"; git -C "$d" init -q
  [ "$2" = "NONE" ] || git -C "$d" remote add origin "$2"
  if [ "$#" -ge 4 ]; then git -C "$d" config --local user.name "$3"; git -C "$d" config --local user.email "$4"; fi
}
eff_email() { git -C "$1" config user.email; }

echo "== 1. URL 解析（经 identity 输出间接验证 host 归类） =="
mkr a "https://gh.test/x/y.git"
mkr b "git@gh.test:x/y.git"
mkr c "ssh://git@gh.test/x/y.git"
mkr d "https://gl.test/x/y.git"
mkr e "NONE"
mkr f "https://gh-proxy.com/https://gh.test/me/proxy-residue.git"
mkr g "https://gh.test/x/y.git" LocalName local@ex.com

echo "-- init（喂身份，验证规则块生成）--"
printf 'Alice <alice@example.com>\nBob <bob@example.com>\n' | "$TOOL" init >/tmp/gm-init.log 2>&1
has "init 写了 gh.test 身份文件" "alice@example.com" "$(cat "$SB/.config/git-mng/identity/gh.test")"
has "init 写了 gl.test 身份文件" "bob@example.com" "$(cat "$SB/.config/git-mng/identity/gl.test")"
has "规则块含 HTTPS 形式" 'hasconfig:remote.*.url:https://gh.test/**' "$(cat "$SB/.gitconfig")"
has "规则块含 scp 形式 */**" 'hasconfig:remote.*.url:git@gh.test:*/**' "$(cat "$SB/.gitconfig")"
eq "规则块写在 [user] 之后（覆盖才生效）" "after" "$(awk '/^\[user\]/{u=NR} /# >>> git-mng/{print (NR>u)?"after":"before"}' "$SB/.gitconfig" | head -1)"
"$TOOL" init <<< 'Alice <alice@example.com>
Bob <bob@example.com>' >/dev/null 2>&1
eq "重复 init 幂等（只保留一块）" "1" "$(grep -c '# >>> git-mng identity routing' "$SB/.gitconfig")"
has "init 留下备份文件" ".gitconfig.bak.gitmng." "$(ls -a "$SB")"

echo "== 2. 三种 remote 写法都要命中同一身份（这是网上教程的坑） =="
eq "https://gh.test/**    → alice" "alice@example.com" "$(eff_email "$SB/code/a")"
eq "git@gh.test:x/y 式   → alice" "alice@example.com" "$(eff_email "$SB/code/b")"
eq "ssh://git@gh.test/…  → alice" "alice@example.com" "$(eff_email "$SB/code/c")"
eq "另一主机 gl.test     → bob"  "bob@example.com"   "$(eff_email "$SB/code/d")"
eq "无远程仓库落回兜底"           "fallback@example.com" "$(eff_email "$SB/code/e")"
eq "局部 user.email 优先于规则"    "local@ex.com"    "$(eff_email "$SB/code/g")"

echo "== 3. 反证：网上常见的 host:** 写法对 scp 式地址静默失效 =="
cat > "$SB/naive.gitconfig" <<'EOF'
[user]
	name = Fallback
	email = fallback@example.com
[includeIf "hasconfig:remote.*.url:git@gh.test:**"]
	path = $HOME/.config/git-mng/identity/gh.test
EOF
sed -i '' "s#\$HOME#$SB#g" "$SB/naive.gitconfig" 2>/dev/null || sed -i "s#\$HOME#$SB#g" "$SB/naive.gitconfig"
naive=$(GIT_CONFIG_GLOBAL="$SB/naive.gitconfig" git -C "$SB/code/b" config user.email)
eq "naive host:** 在 scp 式地址上不生效（故须用 */**）" "fallback@example.com" "$naive"

echo "== 4. identity 体检输出 =="
out=$("$TOOL" identity 2>&1)
has "列出各主机期望身份" "gh.test → Alice <alice@example.com>" "$out"
has "scp 式仓库判定一致" "一致" "$out"
has "局部覆盖的仓库标出不一致" "不一致，期望 Alice <alice@example.com>" "$out"

echo "== 5. fix-ssh：自有账号转 SSH，镜像前缀残留清掉，第三方留直连 =="
mkr h "https://gh.test/me/own.git"
mkr i "https://gh.test/someone/else.git"
mkr j "https://gh-proxy.com/https://gh.test/someone/third.git"
"$TOOL" fix-ssh gh.test >/tmp/gm-fix.log 2>&1
eq "自有仓库转 scp 式" "git@gh.test:me/own.git" "$(git -C "$SB/code/h" config --get remote.origin.url)"
eq "第三方仓库转直连 https" "https://gh.test/someone/else.git" "$(git -C "$SB/code/i" config --get remote.origin.url)"
eq "自有账号的镜像残留 → 转 SSH" "git@gh.test:me/proxy-residue.git" "$(git -C "$SB/code/f" config --get remote.origin.url)"
eq "第三方的镜像残留 → 还原直连 https" "https://gh.test/someone/third.git" "$(git -C "$SB/code/j" config --get remote.origin.url)"
unset GITMNG_OWNER_ACCOUNT
out=$(HOME="$SB" "$TOOL" fix-ssh gh.test 2>&1)
has "缺 OWNER_ACCOUNT 时拒绝猜测并给出提示" "GITMNG_OWNER_ACCOUNT" "$out"

echo "== 6. 配置文件生效顺序（先 source 再算派生变量） =="
mkdir -p "$SB/.config/git-mng"
cat > "$SB/.config/git-mng/config" <<EOF
GITMNG_HOSTS="only.test"
GITMNG_SCAN_ROOTS="$SB/code"
EOF
out=$(HOME="$SB" "$TOOL" version 2>&1)
has "配置文件里的 GITMNG_HOSTS 生效" "hosts=only.test" "$out"

echo "== 7. probe-url：只有路由主机做链路实测，其他主机不去 ls-remote 别人的探针仓库 =="
out=$(HOME="$SB" GITMNG_ROUTE_HOST=gh.test GITMNG_PROBE_REPO=o/r "$TOOL" probe-url gh.test 2>&1)
eq "路由主机 → 走路由 + 探针仓库" "route https://gh.test/o/r" "$out"
out=$(HOME="$SB" GITMNG_ROUTE_HOST=gh.test GITMNG_PROBE_REPO=o/r "$TOOL" probe-url gl.test 2>&1)
eq "非路由主机 → 只测 HTTPS 可达性" "web https://gl.test/" "$out"

echo "== 8. init --revert 干净移除规则块 =="
"$TOOL" init --revert >/tmp/gm-revert.log 2>&1
eq "revert 后规则块数量为 0" "0" "$(grep -c '# >>> git-mng identity routing' "$SB/.gitconfig")"
eq "revert 后原 [user] 兜底身份仍在" "fallback@example.com" "$(git -C "$SB/code/a" config user.email)"
has "revert 未删除身份文件" "alice@example.com" "$(cat "$SB/.config/git-mng/identity/gh.test")"

echo "== 9. 空输入取消，不写任何文件 =="
SB2=$(mktemp -d)/home; mkdir -p "$SB2/code"
cat > "$SB2/.gitconfig" <<'EOF'
[user]
	name = Fallback
	email = fallback@example.com
EOF
out=$(printf '\n\n' | HOME="$SB2" GITMNG_HOSTS="x.test" GITMNG_SCAN_ROOTS="$SB2/code" "$TOOL" init 2>&1)
has "非法格式被拒并提示正确格式" "格式应为" "$out"
out2=$(printf 'someuser\n\n' | HOME="$SB2" GITMNG_HOSTS="x.test" GITMNG_SCAN_ROOTS="$SB2/code" "$TOOL" login x.test 2>&1)
has "login 空凭据时取消且不碰钥匙串" "已取消" "$out2"

echo
printf '通过 %d 项，失败 %d 项\n' "$pass" "$fail"
rm -rf "$(dirname "$SB")" "$SB2" 2>/dev/null
[ "$fail" = "0" ]
