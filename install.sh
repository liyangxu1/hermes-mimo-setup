#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Hermes 官方安装脚本。这里只做封装，不 fork Hermes。
HERMES_INSTALL_URL="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"

# Dashboard 依赖来自 Hermes 的 web extra。
DASHBOARD_DEPS=(
  "fastapi==0.133.1"
  "uvicorn[standard]==0.41.0"
)

DEFAULT_PORT=9119
PORT="$DEFAULT_PORT"
OPEN_TARGET="auto"
NO_OPEN=0
FORCE_INSTALL=0
SKIP_INSTALL=0
DRY_RUN=0
HERMES_BIN_OVERRIDE="${HERMES_BIN:-}"
HERMES_PYTHON_OVERRIDE="${HERMES_PYTHON:-}"
HERMES_BIN=""
HERMES_PYTHON=""

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf '警告：%s\n' "$*" >&2
}

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

format_command() {
  local arg quoted output=""
  for arg in "$@"; do
    printf -v quoted '%q' "$arg"
    output="${output}${quoted} "
  done
  printf '%s\n' "${output% }"
}

usage() {
  cat <<'EOF'
一键安装 Hermes Agent 并打开小米 MiMo 的 Dashboard 配置入口。

用法：
  curl -fsSL https://raw.githubusercontent.com/liyangxu1/hermes-mimo-setup/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/liyangxu1/hermes-mimo-setup/main/install.sh | bash -s -- --port 9120

选项：
  --port PORT          Dashboard 起始端口，默认 9119；被占用时自动递增
  --no-open            启动 Dashboard 后不自动打开浏览器
  --force-install      即使已检测到 hermes，也重新运行 Hermes 官方安装脚本
  --skip-install       未检测到 hermes 时直接失败，不自动安装
  --open auto|env|models
                       打开页面，默认 auto：未配置 XIAOMI_API_KEY 打开 /env，已配置打开 /models
  --dry-run            只打印将执行的动作，不安装、不启动、不打开浏览器
  -h, --help           显示帮助

说明：
  本脚本不会接收或保存 API Key。请在 Hermes Dashboard 的 Keys 页面填写 XIAOMI_API_KEY。
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --port)
        [ "$#" -ge 2 ] || die "--port 缺少参数"
        PORT="$2"
        shift 2
        ;;
      --no-open)
        NO_OPEN=1
        shift
        ;;
      --force-install)
        FORCE_INSTALL=1
        shift
        ;;
      --skip-install)
        SKIP_INSTALL=1
        shift
        ;;
      --open)
        [ "$#" -ge 2 ] || die "--open 缺少参数"
        OPEN_TARGET="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "未知参数：$1"
        ;;
    esac
  done

  case "$PORT" in
    ''|*[!0-9]*) die "--port 必须是数字" ;;
  esac

  if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    die "--port 必须在 1 到 65535 之间"
  fi

  case "$OPEN_TARGET" in
    auto|env|models) ;;
    *) die "--open 只支持 auto、env、models" ;;
  esac
}

resolve_path() {
  local target="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$target" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY
    return 0
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -MCwd=realpath -e 'print realpath($ARGV[0]), "\n"' "$target"
    return 0
  fi

  printf '%s\n' "$target"
}

resolve_hermes() {
  local candidate real_candidate

  if [ -n "$HERMES_BIN_OVERRIDE" ] && [ -x "$HERMES_BIN_OVERRIDE" ]; then
    real_candidate="$(resolve_path "$HERMES_BIN_OVERRIDE")"
    HERMES_BIN="$real_candidate"
    return 0
  fi

  if command -v hermes >/dev/null 2>&1; then
    HERMES_BIN="$(command -v hermes)"
    return 0
  fi

  for candidate in \
    "$HOME/.local/bin/hermes" \
    "$HOME/.hermes/bin/hermes" \
    "$HOME/.hermes/hermes-agent/.venv/bin/hermes" \
    "/opt/homebrew/bin/hermes" \
    "/usr/local/bin/hermes"
  do
    if [ -x "$candidate" ]; then
      HERMES_BIN="$candidate"
      return 0
    fi
  done

  return 1
}

install_hermes_if_needed() {
  if [ "$FORCE_INSTALL" -eq 0 ] && resolve_hermes; then
    log "检测到 Hermes：$HERMES_BIN"
    return 0
  fi

  if [ "$SKIP_INSTALL" -eq 1 ]; then
    die "未检测到 Hermes，且已指定 --skip-install"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run：将执行 curl -fsSL $HERMES_INSTALL_URL | bash -s -- --skip-setup"
    HERMES_BIN="${HERMES_BIN:-hermes}"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载安装 Hermes"
  log "安装 Hermes Agent"
  curl -fsSL "$HERMES_INSTALL_URL" | bash -s -- --skip-setup
  hash -r 2>/dev/null || true

  resolve_hermes || die "Hermes 安装完成后仍找不到 hermes 命令，请检查 PATH"
  log "Hermes 安装完成：$HERMES_BIN"
}

candidate_pythons() {
  local hermes_real hermes_dir shebang interpreter
  hermes_real="$(resolve_path "$HERMES_BIN")"
  hermes_dir="$(dirname "$hermes_real")"

  if [ -x "$hermes_dir/python" ]; then
    printf '%s\n' "$hermes_dir/python"
  fi
  if [ -x "$hermes_dir/python3" ]; then
    printf '%s\n' "$hermes_dir/python3"
  fi

  shebang="$(head -n 1 "$hermes_real" 2>/dev/null || true)"
  case "$shebang" in
    '#!'*python*)
      interpreter="${shebang#\#!}"
      if [ "${interpreter%% *}" = "/usr/bin/env" ]; then
        interpreter="${interpreter#* }"
        interpreter="${interpreter%% *}"
        command -v "$interpreter" 2>/dev/null || true
      elif [ -x "${interpreter%% *}" ]; then
        interpreter="${interpreter%% *}"
        printf '%s\n' "$interpreter"
      fi
      ;;
  esac

  if command -v python3 >/dev/null 2>&1; then
    command -v python3
  fi
}

resolve_hermes_python() {
  local py

  if [ -n "$HERMES_PYTHON_OVERRIDE" ] && "$HERMES_PYTHON_OVERRIDE" -c "import hermes_cli" >/dev/null 2>&1; then
    HERMES_PYTHON="$HERMES_PYTHON_OVERRIDE"
    return 0
  fi

  while IFS= read -r py; do
    if [ -n "$py" ] && "$py" -c "import hermes_cli" >/dev/null 2>&1; then
      HERMES_PYTHON="$py"
      return 0
    fi
  done < <(candidate_pythons | awk '!seen[$0]++')

  return 1
}

python_has_dashboard_deps() {
  "$HERMES_PYTHON" - <<'PY' >/dev/null 2>&1
import fastapi
import uvicorn
PY
}

install_python_packages() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run：将安装 Dashboard 依赖：${DASHBOARD_DEPS[*]}"
    return 0
  fi

  if "$HERMES_PYTHON" -m pip --version >/dev/null 2>&1; then
    "$HERMES_PYTHON" -m pip install "${DASHBOARD_DEPS[@]}"
    return 0
  fi

  if command -v uv >/dev/null 2>&1; then
    uv pip install --python "$HERMES_PYTHON" "${DASHBOARD_DEPS[@]}"
    return 0
  fi

  die "Hermes Python 环境缺少 pip，且系统没有 uv，无法安装 Dashboard 依赖"
}

ensure_dashboard_deps() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run：将检查 Hermes Dashboard 依赖 fastapi/uvicorn"
    return 0
  fi

  resolve_hermes_python || die "找不到能导入 hermes_cli 的 Python 解释器"
  log "Hermes Python：$HERMES_PYTHON"

  if python_has_dashboard_deps; then
    log "Dashboard 依赖已可用"
    return 0
  fi

  log "安装 Dashboard 依赖"
  install_python_packages

  python_has_dashboard_deps || die "Dashboard 依赖安装后仍不可用"
}

find_free_port() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "$PORT"
    return 0
  fi

  "$HERMES_PYTHON" - "$PORT" <<'PY'
import socket
import sys

start = int(sys.argv[1])
for port in range(start, min(start + 100, 65536)):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            continue
    print(port)
    sys.exit(0)

raise SystemExit("no free port found")
PY
}

dashboard_log_path() {
  local base="${TMPDIR:-/tmp}"
  printf '%s/hermes-mimo-dashboard-%s.log\n' "${base%/}" "$1"
}

start_dashboard_once() {
  local port="$1"
  local log_path="$2"
  local skip_build="$3"
  local pid
  local args=(
    dashboard
    --host 127.0.0.1
    --port "$port"
    --no-open
  )

  if [ "$skip_build" -eq 1 ]; then
    args+=(--skip-build)
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run：将后台启动 $(format_command "$HERMES_BIN" "${args[@]}")"
    return 0
  fi

  nohup "$HERMES_BIN" "${args[@]}" >"$log_path" 2>&1 &
  pid="$!"
  sleep 3

  if kill -0 "$pid" >/dev/null 2>&1; then
    printf '%s\n' "$pid"
    return 0
  fi

  return 1
}

start_dashboard() {
  local port="$1"
  local log_path pid
  log_path="$(dashboard_log_path "$port")"

  log "启动 Hermes Dashboard：http://127.0.0.1:$port"
  if [ "$DRY_RUN" -eq 1 ]; then
    start_dashboard_once "$port" "$log_path" 1
    return 0
  fi

  if pid="$(start_dashboard_once "$port" "$log_path" 1)"; then
    log "Dashboard 已启动，PID：$pid，日志：$log_path"
    return 0
  fi

  warn "使用 --skip-build 启动失败，将让 Hermes 自行构建 Web UI 后重试"
  if [ -f "$log_path" ]; then
    sed -n '1,20p' "$log_path" >&2 || true
  fi

  if pid="$(start_dashboard_once "$port" "$log_path" 0)"; then
    log "Dashboard 已启动，PID：$pid，日志：$log_path"
    return 0
  fi

  if [ -f "$log_path" ]; then
    sed -n '1,80p' "$log_path" >&2 || true
  fi
  die "Dashboard 启动失败"
}

hermes_env_path() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s/.hermes/.env\n' "$HOME"
    return 0
  fi

  "$HERMES_BIN" config env-path 2>/dev/null || printf '%s/.hermes/.env\n' "$HOME"
}

has_xiaomi_api_key() {
  local env_path="$1"
  local line value

  [ -f "$env_path" ] || return 1

  while IFS= read -r line; do
    case "$line" in
      XIAOMI_API_KEY=*)
        value="${line#XIAOMI_API_KEY=}"
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        [ -n "$value" ] && return 0
        ;;
    esac
  done <"$env_path"

  return 1
}

choose_open_path() {
  local env_path="$1"

  case "$OPEN_TARGET" in
    env)
      printf '/env\n'
      ;;
    models)
      printf '/models\n'
      ;;
    auto)
      if has_xiaomi_api_key "$env_path"; then
        printf '/models\n'
      else
        printf '/env\n'
      fi
      ;;
  esac
}

open_url() {
  local url="$1"

  if [ "$NO_OPEN" -eq 1 ]; then
    log "已启动 Dashboard，请手动打开：$url"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run：将打开浏览器：$url"
    return 0
  fi

  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 && return 0
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 && return 0
  fi

  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Start-Process '$url'" >/dev/null 2>&1 && return 0
  fi

  warn "未找到可用的浏览器打开命令，请手动打开：$url"
}

print_mimo_next_steps() {
  cat <<'EOF'

MiMo 配置步骤：
  1. 在 Dashboard 左侧进入 Keys，展开 Xiaomi MiMo。
  2. 按量 API：设置 XIAOMI_API_KEY=sk-...；XIAOMI_BASE_URL 留空或使用 https://api.xiaomimimo.com/v1。
  3. Token Plan：设置 XIAOMI_API_KEY=tp-...，并把 XIAOMI_BASE_URL 设置为订阅管理里的专属 Base URL。
  4. 保存后进入 Models，点击 Model Settings -> Main model -> Change。
  5. 搜索 Xiaomi MiMo，选择 mimo-v2.5-pro。

EOF
}

main() {
  parse_args "$@"
  install_hermes_if_needed
  ensure_dashboard_deps

  PORT="$(find_free_port)"
  start_dashboard "$PORT"

  local env_path open_path url
  env_path="$(hermes_env_path)"
  open_path="$(choose_open_path "$env_path")"
  url="http://127.0.0.1:$PORT$open_path"

  print_mimo_next_steps
  open_url "$url"
}

main "$@"
