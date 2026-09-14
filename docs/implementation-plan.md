# 兰空图床本地上传命令：分阶段落地计划

## 1. 实施原则

本计划把 `docs/top-level-design.md` 转换为可以逐阶段执行和验收的任务清单。每阶段都必须有明确产物、测试和退出门禁；阶段状态记录在 `docs/implementation-status.md`。

实现优先复用 `re_debian` 的上传行为，但不直接依赖 `re_debian` 仓库运行时文件。最终客户端必须是本项目自包含的可发布内容。

## 2. 阶段总览

| 阶段 | 目标 | 主要产物 | 退出门禁 |
| --- | --- | --- | --- |
| P0 | 约束、工具和契约固定 | `AGENTS.md`、`mise.toml`、实施文档 | 文档一致、基础检查通过 |
| P1 | 完成可独立运行的上传客户端 | `bin/lsky-upload`、配置模板、客户端测试 | 本地 mock/API 语义测试通过 |
| P2 | 部署本地 Lsky 服务 | `server/compose.yml`、服务管理命令 | 服务持久化且 API 可达 |
| P3 | 真实端到端上传验收 | E2E 测试、测试 fixture、验收脚本 | 返回 URL 且图片可访问 |
| P4 | 形成 Release | 构建、安装、卸载、CI 文档 | 干净目录安装和敏感信息审计通过 |

## 3. P0：方案、Agent 和工具基线

### 3.1 任务

- 创建仓库根目录 `AGENTS.md`，让后续 agent 先读取顶层设计、实施计划和状态；
- 明确客户端/本地服务边界，以及不进入 Release 的敏感数据；
- 创建 `mise.toml`，当前仅固定 ShellCheck，不引入 Python；
- 创建 `.editorconfig` 和 `.gitignore`；
- 建立状态文件，记录未验证风险和每阶段退出条件。

### 3.2 门禁

- `mise run check-shell` 可执行；
- `git diff --check` 通过；
- Git 状态不包含 `.local/`、真实配置或测试数据；
- 文档明确本地 HTTP 例外和生产 HTTPS 默认值。

## 4. P1：客户端实现

### 4.1 目录和文件

```text
bin/lsky-upload                 # 用户命令，Bash
config.env.example              # 制品内模板
scripts/test_client.sh          # 不依赖 Docker 的客户端测试
tests/fixtures/sample.png       # 非敏感、极小测试图片
docs/client.md                  # 命令和配置使用说明
```

### 4.2 配置处理

1. 解析 `LSKY_UPLOAD_CONFIG`，否则使用 XDG 默认路径；
2. 检查路径存在、为普通文件、可读且权限不宽于 `0600`；
3. 按白名单读取 `LSKY_URL`、`LSKY_TOKEN`、`LSKY_ALLOW_INSECURE_HTTP`；
4. 拒绝空值、未知键、重复键和未识别布尔值；
5. 校验 URL scheme/host：loopback HTTP 可用，其他 HTTP 需要显式开发开关，HTTPS 默认允许；
6. 只将 Token 保存在当前进程内存变量，不写临时文件。

### 4.3 API 处理

- 使用 `curl --fail-with-body --silent --show-error --location`；
- 设置连接超时 10 秒、单文件最大耗时 120 秒；
- 请求为 `POST <LSKY_URL>/api/v1/upload`，Header 为 Bearer Token，表单字段为 `file`；
- 使用 `jq -e` 验证 JSON、业务成功字段和 `.data.links.url`；
- 返回 URL 必须是有效的 HTTP/HTTPS URL，且在安全策略允许范围内；
- 任何失败都只输出脱敏摘要到 stderr，退出码区分配置错误、输入错误和上传失败即可，不为此阶段制造复杂错误框架。

### 4.4 P1 测试

使用一个本地 mock HTTP 服务或可控响应 fixture，覆盖：配置缺失、权限过宽、未知字段、缺 Token、空参数、图片不存在、HTTP 错误、`status=false`、畸形 JSON、无 URL、单图和多图顺序。测试必须确认 Token 不出现在输出。

## 5. P2：本地 Lsky 服务

### 5.1 目录和接口

```text
server/compose.yml
server/.env.example                  # 仅非敏感端口/路径占位符
bin/lsky-server                      # start/stop/restart/status/logs/config
docs/local-server.md
```

`bin/lsky-server` 只管理本项目 Compose，不把管理员密码或 Token 传入命令行。默认数据目录为 `~/.local/share/lsky-upload/server/data`，允许 `LSKY_SERVER_DATA_DIR` 覆盖，但覆盖目录必须是用户明确指定的绝对路径。

### 5.2 Compose 设计

- 固定 Lsky Pro 镜像版本或 digest；
- 明确容器内部端口和宿主机 `127.0.0.1:<port>` 绑定；
- SQLite/应用状态和上传目录使用 bind mount；
- `docker compose config --quiet` 后才启动；
- 启动后用 HTTP/API 探针验证，不用容器状态代替服务健康；
- 不提交 `.env`、数据库、上传目录和管理员凭据；
- `stop` 保留数据，显式 `purge` 才允许删除数据，并要求交互确认。

### 5.3 初始化流程

P2 首选人工 Web 初始化，原因是避免依赖未确认的镜像内部命令或直接操作 Laravel 数据库。文档需记录：本地访问地址、管理员创建步骤、Token 创建步骤、配置文件写入步骤。若实测镜像存在稳定且官方支持的 CLI/API，再增加可重复的显式 `init` 子命令。

### 5.4 P2 门禁

- fresh 启动成功；
- 第二次 `start` 不无意义重建或清空数据；
- `status` 能区分容器停止、HTTP 不可达和 API 已就绪；
- 停止/启动后数据库和已上传文件仍存在；
- `docker compose config --quiet`、ShellCheck 和文档命令示例通过。

## 6. P3：真实端到端验收

### 6.1 流程

1. 检查 Docker、Compose、curl、jq 和测试图片；
2. 启动本地 Lsky；
3. 若服务未初始化，停止自动测试并输出人工初始化指引；
4. 使用用户提供的 Token 临时生成测试配置，测试结束不写回仓库；
5. 上传 PNG/JPEG，验证 stdout 只有 URL；
6. 用 curl 获取返回 URL，验证 HTTP 状态、Content-Type 和文件内容；
7. 测试多图顺序、无效 Token、服务停止；
8. 重启/重建容器，验证历史 URL 仍可访问；
9. 清理临时配置，但保留服务数据，除非用户显式执行 purge。

### 6.2 凭据规则

E2E 可从环境变量或用户配置读取 Token，但测试命令不能把 Token拼接进命令行参数。CI 默认不要求真实 Token；没有 Token 时运行 mock 测试并将真实 E2E 标记为 skipped/blocked，而不是伪造成功。

### 6.3 P3 门禁

标准安装后的 `lsky-upload tests/fixtures/sample.png` 能上传并返回可访问 URL；失败场景均为非零退出；输出和测试报告不泄露 Token；容器重启不影响历史图片。

## 7. P4：Release 和安装体验

### 7.1 制品 staging

构建脚本只从 Git 跟踪的客户端、安装器、模板、文档和许可证组装：

```text
lsky-upload-v<version>-linux/
├── bin/lsky-upload
├── config.env.example
├── install
├── uninstall
├── VERSION
├── LICENSE
└── README.md
```

服务端 Compose 可以作为开发源码的一部分，但是否进入 Release 必须在 P2 评估；若进入，不能把运行数据或 Secret 一起打包。

### 7.2 安装器

- 只写 `~/.local/share/lsky-upload/versions/<version>`、`current`、`~/.local/bin/lsky-upload` 和配置模板；
- 使用临时目录和原子 `ln -sfn` 更新当前版本；
- 已有 `config.env` 不覆盖、不改权限、不迁移 Token；
- 安装前检查 Bash、curl、jq，并在缺少依赖时明确失败；
- 卸载不删除用户配置和服务数据。

### 7.3 发布门禁

- SemVer 版本校验；
- `bash -n`、ShellCheck、客户端测试、Compose 校验；
- `tar -tzf` 审计内容；
- 对 staging 和 Git archive 执行敏感字段扫描；
- 生成 tar.gz 和 `.sha256`；
- 在干净临时 HOME 中安装、配置、运行 `--help/--version`；
- 二次安装/升级验证用户配置不被覆盖。

## 8. 每阶段完成后的状态更新

完成一个阶段后必须：

1. 更新 `docs/implementation-status.md` 的当前阶段、已完成、测试结果和风险；
2. 在本阶段文档中补充实际镜像版本、端口、退出码或实现偏差；
3. 运行最小门禁并记录真实命令及结果；
4. 只有门禁通过后，才进入下一阶段。
