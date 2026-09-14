#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT_DIR
readonly CLIENT="$ROOT_DIR/bin/lsky-upload"
readonly SERVER="$ROOT_DIR/bin/lsky-server"
readonly FIXTURE_B64="$ROOT_DIR/tests/fixtures/sample.png.base64"
TEST_DIR=$(mktemp -d)
readonly TEST_DIR
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  printf 'E2E FAIL: %s\n' "$1" >&2
  exit 1
}

assert_status() {
  local expected=$1 name=$2
  shift 2
  set +e
  "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
  local actual=$?
  set -e
  [[ "$actual" -eq "$expected" ]] || fail "$name exit status (got $actual)"
}

config_file=${LSKY_E2E_CONFIG:-}
server_data=${LSKY_SERVER_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/lsky-upload/server/data}
server_port=${LSKY_SERVER_PORT:-8080}
[[ -n "$config_file" ]] || fail '请设置 LSKY_E2E_CONFIG 指向用户私有 config.env'
[[ -f "$config_file" ]] || fail "E2E 配置不存在：$config_file"
[[ -f "$FIXTURE_B64" ]] || fail "测试图片源不存在：$FIXTURE_B64"

mkdir -p "$TEST_DIR/images"
base64 --decode "$FIXTURE_B64" > "$TEST_DIR/images/source.png"
cp -- "$TEST_DIR/images/source.png" "$TEST_DIR/images/first.png"
cp -- "$TEST_DIR/images/source.png" "$TEST_DIR/images/second.png"
[[ "$(file -b --mime-type "$TEST_DIR/images/source.png")" == image/png ]] || fail '测试 fixture 不是 PNG'

LSKY_SERVER_DATA_DIR="$server_data" LSKY_SERVER_PORT="$server_port" "$SERVER" start
if ! docker exec lsky-upload-local test -f /var/www/html/installed.lock; then
  fail 'Lsky 尚未初始化；请先执行 docker exec lsky-upload-local php artisan lsky:install --connection=sqlite，并按参考流程注册管理员'
fi

url=$("$CLIENT" --config "$config_file" "$TEST_DIR/images/first.png")
[[ "$url" =~ ^https?:// ]] || fail '上传没有返回 HTTP(S) URL'
curl --silent --show-error --fail --max-time 20 "$url" -o "$TEST_DIR/downloaded.png"
[[ "$(file -b --mime-type "$TEST_DIR/downloaded.png")" == image/png ]] || fail '返回 URL 不是 PNG'

mapfile -t urls < <("$CLIENT" --config "$config_file" "$TEST_DIR/images/first.png" "$TEST_DIR/images/second.png")
[[ "${#urls[@]}" -eq 2 ]] || fail '多图上传没有返回两个 URL'
[[ "${urls[0]}" =~ ^https?:// && "${urls[1]}" =~ ^https?:// ]] || fail '多图上传返回了无效 URL'

cp -- "$config_file" "$TEST_DIR/invalid.env"
sed -i 's/^LSKY_TOKEN=.*/LSKY_TOKEN=invalid-e2e-token/' "$TEST_DIR/invalid.env"
chmod 0600 "$TEST_DIR/invalid.env"
assert_status 1 'invalid token' "$CLIENT" --config "$TEST_DIR/invalid.env" "$TEST_DIR/images/first.png"

LSKY_SERVER_DATA_DIR="$server_data" LSKY_SERVER_PORT="$server_port" "$SERVER" stop
assert_status 1 'stopped service' "$CLIENT" --config "$config_file" "$TEST_DIR/images/first.png"
LSKY_SERVER_DATA_DIR="$server_data" LSKY_SERVER_PORT="$server_port" "$SERVER" start
curl --silent --show-error --fail --max-time 20 "$url" -o "$TEST_DIR/downloaded-after-restart.png"
[[ "$(file -b --mime-type "$TEST_DIR/downloaded-after-restart.png")" == image/png ]] || fail '重启后历史 URL 不是 PNG'

printf 'PASS: real Lsky upload, multi-image, invalid-token, stopped-service and restart persistence E2E\n'
