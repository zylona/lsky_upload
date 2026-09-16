# 实施状态

## 当前阶段

P4：Release 构建、安装、升级和卸载验收已完成。

## 已完成

- 建立仓库级 `AGENTS.md`，固定项目边界、敏感信息、Shell/Docker 工具和阶段门禁；
- 建立 `mise.toml`、`.editorconfig` 和 `.gitignore`；
- 建立 P0→P4 的具体实施计划 `docs/implementation-plan.md`。
- 实现独立运行的 Bash 客户端 `bin/lsky-upload`；
- 增加 `config.env.example` 和客户端使用文档 `docs/client.md`；
- 增加不依赖 Docker 的客户端 mock 测试 `scripts/test_client.sh`；
- 实现配置白名单、重复字段/权限/布尔值校验、loopback HTTP 例外和远程 HTTP 拒绝；
- 实现 Lsky API 成功语义、URL 提取、多图顺序和首个失败停止；
- curl 通过 stdin 配置接收认证头，避免 Token 出现在命令行参数中。
- 增加固定 digest 的本地 Lsky Compose 服务 `server/compose.yml`；
- 增加 `bin/lsky-server`，支持 `start`、`stop`、`restart`、`status`、`logs`、`config` 和显式确认的 `purge`；
- 默认仅绑定 `127.0.0.1:8080`，数据整体持久化到 `~/.local/share/lsky-upload/server/data`；
- 增加非敏感服务环境模板 `server/.env.example` 和本地服务文档 `docs/local-server.md`；
- `status` 同时检查容器运行状态和 HTTP 根路径，不以 Docker running 单独判定服务就绪。

## 当前未完成

- 第三方镜像存在 SQLite 权限和 `public/i` 软链接行为偏差，运行时验收已通过权限收敛和公开链接修复处理；
- E2E 测试 fixture 使用 Base64 源文件在临时目录还原为真实 PNG，不把二进制测试数据写入源码补丁；

## 风险与前置条件

- 已固定实际使用的 Lsky Pro 镜像版本、CLI 初始化方式和 HTTP 健康检查接口；
- 本地测试依赖 Docker、Docker Compose、curl、jq；
- Token 和管理员密码只能由本地用户在测试时提供，不进入仓库。

## P1 验证记录

- `bash -n bin/lsky-upload scripts/test_client.sh`：通过；
- `shellcheck bin/lsky-upload scripts/test_client.sh`：通过；
- `scripts/test_client.sh`：通过，覆盖配置缺失、未知字段、权限过宽、远程 HTTP、缺少图片、业务失败、畸形 JSON、缺少 URL、Token 输出泄露和多图顺序；
- `git diff --check`：通过；
- 未运行 `docker compose config`：P2 的 `server/compose.yml` 尚未实现。

## P2 验证记录

- `docker compose -f server/compose.yml config --quiet`：通过；
- `mise run check-shell`：通过（包含 `bin/` 和 `scripts/` 的 Bash 语法及 ShellCheck）；
- `LSKY_SERVER_DATA_DIR=/tmp/lsky-upload-p2-check LSKY_SERVER_PORT=18080 bin/lsky-server status`：正确报告 `stopped` 并返回非零；
- 固定 digest 镜像真实拉取并启动：通过；
- `php artisan lsky:install --connection=sqlite`：通过；
- 参考项目 CLI/ORM 管理员注册：通过；
- 官方 `POST /api/v1/tokens` 与 Bearer `/api/v1/profile`：通过；
- 真实 PNG 上传、返回 URL、HTTP 下载和图片像素校验：通过；
- `docker compose down` 后重新 `start`，历史图片 URL 仍可访问且像素校验通过；
- `git diff --check`：通过；
- 明文管理员凭据和客户端临时配置位于 `/tmp`，验收结束后应清理，不进入仓库。

## P3 验证记录

- `scripts/test_e2e.sh`：通过真实 Lsky API 上传单图和多图；
- 返回 URL 下载并验证 `image/png`；
- 无效 Token：非零失败；
- 服务停止：非零失败；
- 容器停止并重建后，历史图片 URL 仍可访问；
- E2E 使用的临时管理员密码和 Token 配置已在测试后删除。
- 本机已移除 re_debian 旧上传命令和旧配置；当前项目已安装到用户目录，并使用默认 `127.0.0.1:8080` 实际部署；
- 本机真实部署验收：命令行初始化、官方 Token API、单图/多图上传、图片下载、无效 Token、服务停止和重启持久化均通过；
- `bin/lsky-server` 增加启动后的 HTTP 就绪等待，避免容器启动与 Apache 探针之间的时序竞争。

## P4 验证记录

- `scripts/build_release.sh`：通过 Git 跟踪文件组装 `lsky-upload-v0.1.0-linux.tar.gz`；
- Release 内容审计：仅包含客户端、安装/卸载脚本、配置模板、VERSION、LICENSE 和 README；
- 敏感信息审计：通过，未包含用户配置、Token、管理员密码、服务数据或测试目录；
- `sha256sum -c`：通过；
- 临时干净 HOME 安装 0.1.0：通过；
- 临时干净 HOME 升级至 0.1.1：通过，已有用户配置内容未改变；
- 临时干净 HOME 卸载：通过，用户配置仍保留，客户端命令链接已移除；
- CI 门禁已加入 `.github/workflows/ci.yml`，覆盖 ShellCheck、mock 测试、Compose 校验、Release 构建和 SHA256。
- CI 已增加 `v*.*.*` tag 触发、`VERSION` 一致性校验、GitHub Release 创建和 tar.gz/SHA256 附件上传；尚未在真实远程 tag 上执行发布。
