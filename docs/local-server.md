# 本地 Lsky Pro 服务

本服务仅用于客户端验收，默认只监听 loopback，不是生产部署方案。服务由 `bin/lsky-server` 管理，默认地址为 `http://127.0.0.1:8080/`。

## 固定镜像和持久化

Compose 使用 `halcyonazure/lsky-pro-docker` 的固定多架构 index digest：

```text
sha256:64ad14908a41c818f023233253d2303bf091bf53884fd8e4faa32e48dc74f044
```

Lsky Pro 官方开源仓库没有官方 Docker 镜像，且当前提示开源版已停止维护；本项目因此明确采用上述第三方镜像作为验收依赖，而不是将其作为生产建议。

容器内 Web 端口为 8089，宿主机只绑定 `127.0.0.1`。默认数据目录为：

```text
~/.local/share/lsky-upload/server/data/
```

该目录整体挂载到 `/var/www/html`，包含 SQLite、应用状态和上传图片。`stop`、`restart`、容器重建不会清空数据。可以用 `LSKY_SERVER_DATA_DIR` 和 `LSKY_SERVER_PORT` 指定绝对数据目录和 loopback 端口。

## 操作

```sh
bin/lsky-server start
bin/lsky-server status
bin/lsky-server logs --tail 100
bin/lsky-server stop
bin/lsky-server restart
```

`start` 先执行 `docker compose config --quiet`，启动后再访问 HTTP 根路径进行探针检查；容器处于 running 但 HTTP 不可达时会报告失败。

## 命令行初始化

本项目验收使用参考项目中的命令行流程，不依赖 Web 安装页面。首次启动后执行：

```sh
docker exec lsky-upload-local php artisan lsky:install --connection=sqlite
```

随后通过 Lsky 应用自身的 PHP/ORM 入口创建管理员，再调用官方 `POST /api/v1/tokens` 生成上传 Token；管理员密码和 Token 只能通过 stdin 或用户私有配置传递。参考项目的初始化还要求确保 `/var/www/html/public/i` 是指向 `/var/www/html/storage/app/uploads` 的软链接。

当前第三方镜像的模型保存事件会把软链接尝试创建在 `/var/www/html/i`，而 Apache DocumentRoot 是 `/var/www/html/public`；若返回图片 URL 为 404，需要按上述路径补建 `public/i`，不能把图片目录改为容器临时目录。

管理员初始化完成后，通过 Lsky 官方 `POST /api/v1/tokens` 创建上传 Token，再写入用户配置：

```text
${XDG_CONFIG_HOME:-$HOME/.config}/lsky-upload/config.env
```

真实 E2E 验收使用用户私有配置路径，不把 Token 放入命令行：

```sh
LSKY_E2E_CONFIG="$XDG_CONFIG_HOME/lsky-upload/config.env" \
LSKY_SERVER_DATA_DIR="$HOME/.local/share/lsky-upload/server/data" \
LSKY_SERVER_PORT=8080 \
scripts/test_e2e.sh
```

首次初始化不由 E2E 脚本自动猜测管理员凭据；请先按上面的 Artisan/CLI 流程完成初始化和 Token 配置。

删除测试数据只能显式执行，并要求交互确认：

```sh
bin/lsky-server purge
```

## 配置检查

```sh
bin/lsky-server config
```

也可以复制 `server/.env.example` 作为本地参考，但它不是必需文件，且禁止放入敏感信息。
