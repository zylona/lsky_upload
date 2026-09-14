#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT_DIR
readonly DIST_DIR="$ROOT_DIR/dist"
stage_parent=''

die() {
  printf '%s\n' "$1" >&2
  exit "${2:-1}"
}

cleanup() {
  [[ -n "$stage_parent" ]] && rm -rf -- "$stage_parent"
}
trap cleanup EXIT

validate_version() {
  [[ "$1" =~ ^0\.[0-9]+\.[0-9]+$|^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]] || die "无效 SemVer 版本：$1" 2
}

require_tracked() {
  git -C "$ROOT_DIR" ls-files --error-unmatch "$1" >/dev/null 2>&1 || die "Release 文件未被 Git 跟踪：$1" 2
}

audit_package() {
  local package_dir=$1
  [[ ! -e "$package_dir/config.env" ]] || die 'Release 不得包含 config.env' 1
  [[ ! -e "$package_dir/server" && ! -e "$package_dir/tests" ]] || die 'Release 不得包含 server/ 或 tests/' 1
  if rg -n -P -i 'super-secret|unit-test-placeholder|BEGIN [A-Z ]*PRIVATE KEY' "$package_dir"; then
    die 'Release 敏感信息审计失败' 1
  fi
  local config_tokens
  config_tokens=$(rg -n '^LSKY_TOKEN=' "$package_dir" || true)
  [[ -z "$config_tokens" || "$config_tokens" == *'LSKY_TOKEN=REPLACE_WITH_LSKY_UPLOAD_TOKEN'* ]] || die 'Release 配置模板包含非占位 Token' 1
}

main() {
  local version=${1:-}
  if [[ -z "$version" ]]; then
    version=$(<"$ROOT_DIR/VERSION")
  fi
  validate_version "$version"
  [[ $# -le 1 ]] || die '用法：scripts/build_release.sh [VERSION]' 2

  local relative_file
  for relative_file in bin/lsky-upload config.env.example VERSION LICENSE README.md install uninstall; do
    require_tracked "$relative_file"
    [[ -f "$ROOT_DIR/$relative_file" ]] || die "Release 文件不存在：$relative_file" 2
  done
  command -v tar >/dev/null 2>&1 || die '缺少依赖：tar' 2
  command -v sha256sum >/dev/null 2>&1 || die '缺少依赖：sha256sum' 2
  command -v rg >/dev/null 2>&1 || die '缺少依赖：rg' 2

  mkdir -p "$DIST_DIR"
  local stage package_name archive checksum_file epoch
  stage_parent=$(mktemp -d "$DIST_DIR/.stage.XXXXXX")
  stage="$stage_parent/lsky-upload-v${version}-linux"
  package_name="lsky-upload-v${version}-linux"
  archive="$DIST_DIR/${package_name}.tar.gz"
  checksum_file="$archive.sha256"
  mkdir -p "$stage/bin"
  install -m 0755 "$ROOT_DIR/bin/lsky-upload" "$stage/bin/lsky-upload"
  install -m 0755 "$ROOT_DIR/install" "$stage/install"
  install -m 0755 "$ROOT_DIR/uninstall" "$stage/uninstall"
  install -m 0644 "$ROOT_DIR/config.env.example" "$stage/config.env.example"
  install -m 0644 "$ROOT_DIR/LICENSE" "$stage/LICENSE"
  install -m 0644 "$ROOT_DIR/README.md" "$stage/README.md"
  printf '%s\n' "$version" > "$stage/VERSION"
  audit_package "$stage"

  epoch=${SOURCE_DATE_EPOCH:-$(git -C "$ROOT_DIR" log -1 --format=%ct)}
  tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner -czf "$archive" -C "$stage_parent" "$package_name"
  (cd "$DIST_DIR" && sha256sum "$(basename -- "$archive")" > "$(basename -- "$checksum_file")")
  printf '已构建：%s\n校验：%s\n' "$archive" "$checksum_file"
}

main "$@"
