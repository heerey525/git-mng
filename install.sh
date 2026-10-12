#!/usr/bin/env bash
# git-mng 安装脚本：检查依赖 → 复制到 ~/.local/bin → 跑自测
set -u

here=$(cd "$(dirname "$0")" && pwd)
bin_dir="${GIT_MNG_INSTALL_DIR:-$HOME/.local/bin}"

fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '  %s\n' "$*"; }

echo "== 依赖检查 =="
command -v git >/dev/null 2>&1 || { fail "找不到 git"; exit 1; }
gv=$(git --version | sed -E 's/git version ([0-9]+)\.([0-9]+).*/\1.\2/')
num=$(printf '%s' "$gv" | tr -d '.' )
maj=$(printf '%s' "$gv" | cut -d. -f1); min=$(printf '%s' "$gv" | cut -d. -f2)
if [ "$maj" -lt 2 ] || { [ "$maj" -eq 2 ] && [ "$min" -lt 36 ]; }; then
  fail "git $gv 过低：按远程地址自动切换提交身份需要 git >= 2.36（includeIf hasconfig）"
  note "macOS 可用 brew install git 升级后重试"
  exit 1
fi
note "git $gv  OK"

[ "$(uname -s)" = "Darwin" ] || fail "警告：本版本仅支持 macOS 凭据后端（钥匙串），其他系统 doctor 会给出提示"
command -v security >/dev/null 2>&1 || fail "警告：找不到 security 命令，凭据相关子命令不可用"
command -v curl >/dev/null 2>&1 || note "提示：缺 curl 时 route bench 仍可用，但 doctor 的 HTTP 检查会跳过"
note "bash $BASH_VERSION"

echo "== 安装到 $bin_dir =="
mkdir -p "$bin_dir"
install -m 0755 "$here/bin/git-mng" "$bin_dir/git-mng" 2>/dev/null \
  || { cp "$here/bin/git-mng" "$bin_dir/git-mng" && chmod +x "$bin_dir/git-mng"; }
note "已安装 $bin_dir/git-mng"

case ":$PATH:" in
  *":$bin_dir:"*) note "PATH 检查 OK" ;;
  *) fail "PATH 里没有 $bin_dir，请在 ~/.zshrc 加：export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo "== 自测 =="
if [ -x "$here/tests/run.sh" ]; then
  "$here/tests/run.sh" | tail -3
else
  note "跳过（未找到 tests/run.sh）"
fi

echo
note "下一步：git-mng init    # 声明各平台的提交身份"
note "        git-mng doctor  # 体检本机配置与连通性"
