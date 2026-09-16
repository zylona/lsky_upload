# lsky-upload

![CI](../../actions/workflows/ci.yml/badge.svg)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Docker Compose](https://img.shields.io/badge/docker-compose-2496ED?logo=docker&logoColor=white)
![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)

面向 Linux 用户的 Lsky Pro 图片上传命令，配套一个仅用于本地验收的 Docker Compose 服务。

支持从安全的 XDG 配置文件读取 Token，批量上传一张或多张图片，并在标准输出中逐行返回图片 URL。项目同时提供真实 Lsky API 的端到端测试、用户级 Release 安装器和 SHA256 校验。

## ✨ 特性

- 🚀 Bash 实现，安装简单，无需 root；
- 🔐 Token 只从用户私有配置读取，不进入命令行参数、日志或 Release；
- 🖼️ 支持单图和多图上传，保持输入顺序，首个失败立即停止；
- 🛡️ 严格校验配置字段、重复键、文件权限、URL 和 API 成功语义；
- 🧪 提供 mock 测试与真实 Lsky API E2E 测试；
- 🐳 本地服务默认只绑定 `127.0.0.1`，SQLite、应用状态和图片持久化；
- 📦 提供版本化 tar.gz、SHA256、用户级安装和卸载；
- 🔄 升级不覆盖已有用户配置，卸载不删除用户配置或服务数据。

## 🧭 工作方式

```text
图片路径
   │
   ▼
lsky-upload ── Bearer Token + multipart ──▶ Lsky Pro API
   │                                             │
   └────────────── 输出图片 URL ◀────────────────┘
```

默认配置路径：

```text
${XDG_CONFIG_HOME:-$HOME/.config}/lsky-upload/config.env
```

生产环境默认要求 HTTPS；本地 `localhost`、`127.0.0.1` 和 `::1` 允许 HTTP。

## 🚀 快速开始

### 安装 Release

```sh
tar -xzf lsky-upload-v0.1.1-linux.tar.gz
cd lsky-upload-v0.1.1-linux
./install
```

安装器会将客户端放入用户目录，并在配置不存在时创建模板：

```text
~/.local/share/lsky-upload/versions/<version>/
~/.local/share/lsky-upload/current
~/.local/bin/lsky-upload
~/.config/lsky-upload/config.env.example
```

### 配置并上传

```sh
cp ~/.config/lsky-upload/config.env.example ~/.config/lsky-upload/config.env
chmod 600 ~/.config/lsky-upload/config.env
${EDITOR:-vi} ~/.config/lsky-upload/config.env

lsky-upload image.png
lsky-upload image-a.png image-b.jpg
```

配置示例：

```dotenv
LSKY_URL=https://img.example.com
LSKY_TOKEN=由 Lsky 管理页面创建的上传 Token
LSKY_ALLOW_INSECURE_HTTP=false
```

成功时 stdout 只有 URL，每行一个；诊断信息写入 stderr，失败时返回非零退出码。

## 📝 配置 Typora 图片自动上传（Linux）

本项目的主要使用场景是 Typora：在 Typora 中粘贴、拖拽或插入本地图片时，由 Typora 调用 `lsky-upload`，上传成功后自动把本地图片地址替换为 Lsky Pro 图片 URL。

### 前置要求

- 使用支持 **Image Upload / Custom Command** 的 Typora Linux 版本；
- 已完成本项目安装，并确认命令可执行：

  ```sh
  command -v lsky-upload
  lsky-upload --version
  ```

- 已配置用户私有的 `config.env`，且 `LSKY_URL` 和 `LSKY_TOKEN` 有效；
- 客户端依赖 `bash`、`curl` 和 `jq` 可用；
- Typora 运行用户能够访问 Lsky Pro 服务。

### 设置自定义命令

1. 打开 Typora：`File` → `Preferences` → `Image`；
2. 在 `When Insert...` 中选择 `Upload Image`；
3. 在 `Image Uploader` 中选择 `Custom Command`；
4. 填入 `lsky-upload` 的绝对路径，例如：

   ```text
   /home/你的用户名/.local/bin/lsky-upload
   ```

   可通过 `command -v lsky-upload` 获取实际路径；
5. 点击 `Test Uploader` 验证配置。

Typora 会自动把待上传图片路径追加到自定义命令后面。例如配置命令为：

```text
/home/你的用户名/.local/bin/lsky-upload
```

Typora 可能实际执行：

```text
/home/你的用户名/.local/bin/lsky-upload /tmp/image-a.png /tmp/image-b.png
```

本客户端支持多个图片参数，并按 Typora 传入的顺序逐行输出 URL。不要在自定义命令中再次手写图片路径或 Token。

### 启用自动上传

在 Typora 的 `Image` 设置中启用 `When Insert... → Upload Image`，并建议只勾选 `Apply above rules to local images`。这样通过粘贴、拖拽或 `Format → Image → Insert Local Images...` 插入本地图片时，Typora 会自动调用该命令。

也可以在 Markdown 文件 YAML front matter 中启用自动上传：

```yaml
---
typora-copy-images-to: upload
---
```

该方式需要先在 Typora 偏好设置中开启 `Allow upload images automatically based on YAML settings`。

### Typora 使用注意事项

- 自定义命令必须是可执行文件的绝对路径；桌面程序的 `PATH` 可能与终端不同，直接填写 `lsky-upload` 可能出现 `command not found`；
- 命令标准输出只能包含图片 URL，客户端的错误诊断会写入标准错误，这是 Typora 解析上传结果的必要条件；
- Typora 需要收到以 `http://` 或 `https://` 开头的 URL，Lsky Pro 的站点 URL 应配置为可访问的完整地址；
- 如果上传失败，先在终端执行同一命令测试，再点击 Typora 的 `Test Uploader` 查看错误；
- Typora 会将本次传入的图片路径追加到命令末尾，因此不要把 `$1`、`$2` 或固定图片路径写进自定义命令；
- 详细行为可参考 [Typora 官方图片上传说明](https://support.typora.io/Upload-Image/)。

## 🐳 本地 Lsky 验收服务

本地服务只用于开发和验收，不是生产部署方案：

```sh
bin/lsky-server start
bin/lsky-server status
bin/lsky-server logs --tail 100
bin/lsky-server stop
```

默认地址和数据目录：

```text
http://127.0.0.1:8080/
~/.local/share/lsky-upload/server/data/
```

首次初始化使用命令行流程：

```sh
docker exec lsky-upload-local php artisan lsky:install --connection=sqlite
```

然后按 [本地服务文档](docs/local-server.md) 中的参考流程创建管理员和上传 Token。

## 🧪 测试

运行不依赖 Docker 的客户端测试：

```sh
scripts/test_client.sh
```

运行真实 Lsky API E2E。需要先完成本地初始化，并将 Token 放入用户私有配置：

```sh
LSKY_E2E_CONFIG="$HOME/.config/lsky-upload/config.env" \
LSKY_SERVER_DATA_DIR="$HOME/.local/share/lsky-upload/server/data" \
LSKY_SERVER_PORT=8080 \
scripts/test_e2e.sh
```

E2E 覆盖真实上传、多图、无效 Token、服务停止和容器重建后的历史图片持久化。

## 📦 构建 Release

```sh
scripts/build_release.sh
(cd dist && sha256sum -c lsky-upload-v0.1.1-linux.tar.gz.sha256)
```

Release 仅包含客户端、配置模板、安装/卸载脚本、版本信息、许可证和 README，不包含：

- Token、管理员密码或用户配置；
- SQLite、图片、日志和 Docker 数据；
- 本地服务 Compose 文件和测试目录。

推送匹配 `vMAJOR.MINOR.PATCH` 的 Git tag 后，GitHub Actions 会在门禁通过后自动创建 GitHub Release，并上传 tar.gz 与 `.sha256` 文件：

```sh
git tag v0.1.1
git push origin v0.1.1
```

tag 去掉 `v` 后必须与 `VERSION` 完全一致。

## 🔒 安全边界

- 配置文件权限必须不宽于 `0600`；
- 未知配置字段和重复字段直接失败；
- 非 loopback HTTP 默认拒绝；
- stdout 只输出成功 URL；
- curl 通过 stdin 配置接收认证头，避免 Token 出现在进程参数中；
- 卸载不会删除 `config.env` 或本地服务数据。

## 📚 文档

- [客户端使用说明](docs/client.md)
- [本地 Lsky 服务](docs/local-server.md)
- [顶层设计](docs/top-level-design.md)
- [实施计划](docs/implementation-plan.md)
- [实施状态](docs/implementation-status.md)

## 📄 许可证

本项目采用 [GNU GPL v3.0 或更高版本](LICENSE) 授权。
