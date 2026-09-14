# 兰空图床本地上传命令：顶层设计方案

## 1. 文档目的

本文是本项目的第一版顶层设计，定义一个面向普通 Linux 用户的兰空图床（Lsky Pro）本地上传客户端，并定义一个仅用于验收客户端的本地 Lsky Pro 服务。

本项目的交付顺序是：先在本地完成“配置 → 上传命令 → Lsky API → 返回图片 URL”的闭环，再形成不包含任何敏感配置的可安装 Release 制品。

参考实现：

- `re_debian/scripts/image_hosting_upload.sh`：上传协议、配置读取、错误处理和 JSON 响应解析的基础实现；
- `re_debian/scripts/image_hosting_upload_install.sh`：用户级安装方式；
- `re_debian/roles/image_hosting`：Lsky Pro Docker、持久化目录和初始化思路；
- `re_remote_dev/docs/release.md` 与 `scripts/build_orchestrator_release.sh`：版本化安装目录、`current` 符号链接、用户级 systemd 和 tar.gz + SHA256 发布方式。

## 2. 目标与非目标

### 2.1 目标

第一版必须做到：

1. 提供 Linux 用户级命令，例如 `lsky-upload`；
2. 从符合 Linux/XDG 习惯的配置文件读取图床地址和上传 Token；
3. 支持一个或多个图片路径，按命令行顺序上传；
4. 成功时在标准输出逐行返回图片 URL，失败时返回非零退出码并将脱敏错误写入标准错误；
5. 在本地用 Docker Compose 部署可重复启动的 Lsky Pro 测试服务；
6. 使用真实的 Lsky API 完成端到端测试，不通过伪造响应或直接写数据库验收；
7. 发布不携带 Token、管理员密码、用户配置、运行数据或本地图片；
8. 安装时若用户配置不存在，提供一个权限安全的配置模板，并给出明确提示。

### 2.2 非目标

第一版不实现：

- 公网域名、HTTPS、ACME 证书或反向代理；
- PicGo、Typora 插件或其他编辑器专用集成；
- 多图床账户管理、自动 Token 轮换和图片管理/删除；
- 把本地测试服务作为生产部署方案；
- 将上传 Token 放入命令行参数、项目随附的固定环境文件、日志或 Release 制品。

## 3. 总体架构

```text
用户图片路径
     │
     ▼
 lsky-upload  ──读取──> ~/.config/lsky-upload/config.env (0600)
     │                         │
     │ HTTP 本地测试 / HTTPS 生产│ Bearer Token
     ▼                         │
 http://127.0.0.1:<port>        │
     ▼                         │
 Lsky Pro Docker Compose <─────┘
     │
     ├── SQLite / 应用状态持久化
     └── 图片文件持久化
```

客户端和服务端通过 Lsky Pro API `/api/v1/upload` 通信，上传字段为 `file`，认证头为 `Authorization: Bearer <token>`，从响应的 `.data.links.url` 提取最终 URL。

生产环境可以把配置中的 URL 改为 HTTPS 域名；客户端只需要改变配置，不依赖本地服务的部署方式。

## 4. 本地测试服务设计

### 4.1 部署边界

本地服务由项目提供的 Compose 文件和管理命令控制，默认只绑定 `127.0.0.1`，例如 `127.0.0.1:8080`，不暴露到局域网或公网。服务目录建议为：

```text
~/.local/share/lsky-upload/server/
├── compose.yml
└── data/
    ├── database/
    └── uploads/
```

镜像必须使用固定版本或 digest，不使用 `latest`。数据库和上传文件必须挂载到宿主机，容器重启或重新创建不能丢失测试图片。

### 4.2 初始化

服务管理命令负责检查容器状态和 API 可达性；首次启动时允许用户在本地 Web 页面完成 Lsky 管理员初始化，或在确认镜像支持稳定 CLI/API 后提供显式初始化子命令。不能仅凭容器为 `running` 就判定服务可用。

测试用 Token 由 Lsky 管理员通过官方 Token API 生成，并由用户写入客户端配置。项目不把管理员密码或 Token 写入 Compose 文件、脚本源码或 Git。

### 4.3 本地 HTTP 约束

本地测试没有 HTTPS 是预期条件。客户端 URL 校验采用以下规则：

- `http://127.0.0.1`、`http://localhost` 或明确配置的本地测试地址允许 HTTP；
- 非本地地址默认要求 HTTPS；
- 可用显式 `allow_insecure_http=true` 作为开发开关，但只允许在用户配置中出现，不能作为默认值；
- 服务返回的图片 URL 在本地测试阶段也允许 HTTP，生产模式仍拒绝非 HTTPS URL。

这样可以保留生产安全默认值，同时不牺牲本地闭环验收。

## 5. 用户配置契约

配置文件采用 dotenv 风格的简单 `KEY=VALUE` 格式，路径遵循 XDG：

```text
${XDG_CONFIG_HOME:-$HOME/.config}/lsky-upload/config.env
```

建议模板：

```dotenv
# chmod 600 ~/.config/lsky-upload/config.env
LSKY_URL=http://127.0.0.1:8080
LSKY_TOKEN=REPLACE_WITH_LSKY_UPLOAD_TOKEN
# 本地 HTTP 测试才需要；生产 HTTPS 配置保持 false 或删除
LSKY_ALLOW_INSECURE_HTTP=true
```

约束：

- 文件必须是普通文件且权限不宽于 `0600`；安装器创建目录 `0700`、文件 `0600`；
- 只接受定义过的字段，未知字段直接报错，避免拼写错误静默生效；
- Token 不从命令行读取，避免出现在 shell history 和进程列表；
- 支持 `LSKY_UPLOAD_CONFIG` 环境变量覆盖路径，便于测试，但不改变默认路径；
- 配置模板只包含占位符，不包含真实地址以外的环境秘密。

## 6. 上传命令设计

### 6.1 命令接口

建议命令名：`lsky-upload`。

```text
lsky-upload IMAGE [IMAGE ...]
lsky-upload --config PATH IMAGE [IMAGE ...]
lsky-upload --version
lsky-upload --help
```

行为约定：

- 至少需要一个存在且为普通文件的图片路径；
- 使用 `curl` 发起 multipart 上传，使用 `jq` 解析 JSON；
- 每张图片独立上传，但首个失败立即退出，避免输出部分不完整结果；
- 成功输出与输入数量一致的 URL，每行一个，不输出其他信息到 stdout；
- stderr 只显示路径、HTTP/API 错误摘要等脱敏信息，不显示 Token 或完整响应中的敏感字段；
- 超时、连接失败、HTTP 错误、API 返回 `status=false`、响应缺少 URL、URL scheme 不符合策略，均返回非零退出码；
- 通过临时文件或进程替换处理响应时，不在磁盘持久化 Token。

### 6.2 依赖与兼容性

第一版以 POSIX/Linux 常见工具为基础：Bash、`curl`、`jq`。安装器应在安装前检查依赖并给出发行版无关的安装提示。首要验收平台为 Linux amd64；脚本本身不绑定架构，为后续 ARM64 保留空间。

## 7. 安装与配置体验

安装器是用户级的，不使用 root，不写 `/usr/bin` 或系统 systemd。默认布局：

```text
~/.local/share/lsky-upload/versions/<version>/   # 版本文件
~/.local/share/lsky-upload/current               # 当前版本链接
~/.local/bin/lsky-upload                         # 命令链接
~/.config/lsky-upload/config.env.example         # 配置模板
```

安装流程：

1. 校验包版本和文件完整性；
2. 将文件复制到版本目录；
3. 原子更新 `current` 符号链接；
4. 创建命令链接；
5. 若默认配置不存在，创建模板但不覆盖用户已有配置；
6. 检查 `~/.local/bin` 是否在 `PATH` 中并输出后续配置说明。

卸载只删除本项目创建的命令、版本目录和模板，不删除用户的 `config.env`，避免误删 Token；如需清理测试服务数据，应提供单独且明确的命令。

## 8. Release 制品设计

制品采用可审计的版本化 tar.gz：

```text
lsky-upload-v<version>-linux.tar.gz
lsky-upload-v<version>-linux.tar.gz.sha256
```

制品内容只包括：

- `bin/` 或客户端脚本；
- `install`、可选的 `uninstall`；
- `config.env.example`；
- 本地 Compose/服务管理脚本（若决定随制品发布）；
- `VERSION`、许可证和用户文档。

明确排除：`.env`、`.local/`、Token、管理员密码、真实上传配置、数据库、图片、日志、缓存和构建临时文件。

构建脚本应从 Git 跟踪文件组成 staging 目录，清理 `__pycache__`/临时文件，使用稳定排序和可选 `SOURCE_DATE_EPOCH` 构建，然后生成 SHA256。发布门禁至少包括 shellcheck（若可用）、脚本语法检查、单元测试、Compose 配置检查、敏感信息扫描和端到端本地上传测试。

发布流程参考 `re_remote_dev`：使用 SemVer 版本，推送 `vMAJOR.MINOR.PATCH` tag 触发 CI 构建 Release asset；用户下载 tar.gz 与校验文件后先执行 `sha256sum -c`，再执行包内 `install`。

## 9. 测试与验收标准

### 9.1 自动测试

- 配置缺失、权限过宽、未知字段、缺少 Token 时失败；
- 本地 HTTP 允许，远程 HTTP 默认拒绝，HTTPS 地址允许；
- 图片不存在、空参数、依赖缺失时返回预期退出码；
- 模拟 Lsky 成功响应、业务失败响应、畸形 JSON 和无 URL 响应；
- Token 不出现在 stdout、stderr、测试报告和构建清单；
- 多文件输出顺序与输入顺序一致。

### 9.2 本地端到端验收

```text
启动本地 Lsky
  → 完成管理员初始化
  → 创建上传 Token
  → 写入 ~/.config/lsky-upload/config.env
  → lsky-upload ./tests/fixtures/sample.png
  → 得到一个可访问的本地图片 URL
  → curl 验证该 URL 返回图片
  → 重启/重建容器
  → 再次验证历史 URL 仍可访问
```

完成定义：标准安装后的 `lsky-upload sample.png` 成功上传并返回可访问 URL；无效 Token 和服务停止时命令明确失败；重新安装或升级不覆盖用户配置。

## 10. 分阶段实施

### P0：方案与契约

完成本文、命令名、配置路径、退出码、HTTP 安全策略和制品命名约定。

### P1：客户端复用

将 `re_debian` 上传脚本抽取为本项目实现，统一命令名和配置字段，补充本地 HTTP 例外、权限检查和测试。

### P2：本地 Lsky 服务

加入固定版本 Compose、持久化目录、服务启动/停止/status 命令和初始化说明；完成本地 API 健康检查。

### P3：端到端验收

自动启动服务，使用测试图片和真实 Token 完成上传、返回 URL、图片可读性、重启持久化及失败场景测试。

### P4：Release

加入构建脚本、安装/卸载脚本、模板配置、CHANGELOG 和 CI 门禁，构建 tar.gz + SHA256 并在干净用户目录安装验证。

## 11. 关键决策与待确认事项

当前默认决策：客户端使用 Bash 实现，本地服务使用 Docker Compose，默认绑定 `127.0.0.1:8080`，配置路径为 `~/.config/lsky-upload/config.env`，生产 HTTPS 为安全默认值。

实现前需要在 P2 固定以下内容：

- 采用的 Lsky Pro 镜像版本及其许可证/架构支持；
- 是否自动化管理员初始化，还是保留一次人工 Web 初始化；
- 服务管理命令是否随 Release 一起发布，还是仅作为开发仓库工具；
- CI 使用的 Docker 环境和是否将真实端到端测试标记为可选门禁。
