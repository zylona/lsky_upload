#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT_DIR
readonly CLIENT="$ROOT_DIR/bin/lsky-upload"
TEST_DIR=$(mktemp -d)
readonly TEST_DIR
trap 'rm -rf "$TEST_DIR"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "$3 (got: $1)"; }
assert_status() {
  local expected=$1 name=$2
  shift 2
  set +e
  "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
  local actual=$?
  set -e
  assert_eq "$actual" "$expected" "$name exit status"
}

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/config" "$TEST_DIR/images"
printf 'test image\n' > "$TEST_DIR/images/a.png"
printf 'test image b\n' > "$TEST_DIR/images/b.png"

cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
config=$(cat)
[[ "$config" == *'Authorization: Bearer unit-test-placeholder'* ]] || exit 91
[[ "$config" == *'form = "file=@'* ]] || exit 92
case "${MOCK_RESPONSE:-success}" in
  success) printf '%s\n' '{"status":true,"data":{"links":{"url":"http://127.0.0.1:8080/i/test.png"}}}' ;;
  failure) printf '%s\n' '{"status":false,"message":"bad token"}' ;;
  malformed) printf '%s\n' 'not-json' ;;
  missing-url) printf '%s\n' '{"status":true,"data":{"links":{}}}' ;;
  *) exit 1 ;;
esac
EOF
chmod 0755 "$TEST_DIR/bin/curl"

write_config() {
  local path=$1 content=$2
  printf '%s\n' "$content" > "$path"
  chmod 0600 "$path"
}

write_config "$TEST_DIR/config/valid.env" $'LSKY_URL=http://127.0.0.1:8080\nLSKY_TOKEN=unit-test-placeholder\nLSKY_ALLOW_INSECURE_HTTP=false'
PATH="$TEST_DIR/bin:$PATH" MOCK_RESPONSE=success "$CLIENT" --config "$TEST_DIR/config/valid.env" "$TEST_DIR/images/a.png" "$TEST_DIR/images/b.png" > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
[[ ! -s "$TEST_DIR/stderr" ]] || fail 'successful upload wrote diagnostics'
assert_eq "$(wc -l < "$TEST_DIR/stdout" | tr -d ' ')" 2 'multi-image output count'
assert_eq "$(sed -n '1p' "$TEST_DIR/stdout")" 'http://127.0.0.1:8080/i/test.png' 'URL output'
! rg -n 'unit-test-placeholder' "$TEST_DIR/stdout" "$TEST_DIR/stderr" || fail 'token leaked to output'

assert_status 2 'missing config' env PATH="$PATH" "$CLIENT" --config "$TEST_DIR/config/missing.env" "$TEST_DIR/images/a.png"
# shellcheck disable=SC2016
assert_status 2 'unknown field' bash -c 'printf "%s\n" "$1" > "$2"; chmod 600 "$2"; exec "$3" --config "$2" "$4"' _ $'LSKY_URL=http://127.0.0.1:8080\nLSKY_TOKEN=x\nUNKNOWN=x' "$TEST_DIR/config/unknown.env" "$CLIENT" "$TEST_DIR/images/a.png"
# shellcheck disable=SC2016
assert_status 2 'wide config permissions' bash -c 'printf "%s\n" "$1" > "$2"; chmod 644 "$2"; exec "$3" --config "$2" "$4"' _ $'LSKY_URL=http://127.0.0.1:8080\nLSKY_TOKEN=x' "$TEST_DIR/config/wide.env" "$CLIENT" "$TEST_DIR/images/a.png"
# shellcheck disable=SC2016
assert_status 2 'remote HTTP rejected' bash -c 'printf "%s\n" "$1" > "$2"; chmod 600 "$2"; exec "$3" --config "$2" "$4"' _ $'LSKY_URL=http://example.com\nLSKY_TOKEN=x' "$TEST_DIR/config/remote-http.env" "$CLIENT" "$TEST_DIR/images/a.png"
assert_status 1 'missing image' env PATH="$TEST_DIR/bin:$PATH" "$CLIENT" --config "$TEST_DIR/config/valid.env" "$TEST_DIR/images/missing.png"

for response in failure malformed missing-url; do
  assert_status 1 "$response response" env PATH="$TEST_DIR/bin:$PATH" MOCK_RESPONSE="$response" "$CLIENT" --config "$TEST_DIR/config/valid.env" "$TEST_DIR/images/a.png"
done

printf 'PASS: client configuration, security, API and multi-image checks\n'
