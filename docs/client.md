# lsky-upload 客户端

## 配置

默认读取 `${XDG_CONFIG_HOME:-$HOME/.config}/lsky-upload/config.env`，也可以通过 `LSKY_UPLOAD_CONFIG` 指定测试或备用路径，或使用 `--config PATH`。

配置文件必须是普通文件，权限不宽于 `0600`，只接受以下字段：

```dotenv
LSKY_URL=https://example.invalid
LSKY_TOKEN=由 Lsky 管理页面创建的上传 Token
LSKY_ALLOW_INSECURE_HTTP=false
```

`LSKY_ALLOW_INSECURE_HTTP=true` 仅用于开发测试。`http://localhost`、`http://127.0.0.1` 和 `http://[::1]` 默认允许；其他 HTTP 地址默认拒绝。

## 使用

```sh
lsky-upload image.png
lsky-upload image-a.png image-b.jpg
lsky-upload --config /path/to/config.env image.png
```

成功时标准输出只有图片 URL，每行一个；错误写入标准错误并以非零状态退出。多图按输入顺序上传，首个失败即停止。

客户端依赖 Bash、curl 和 jq。它调用 Lsky Pro `/api/v1/upload`，使用 multipart 字段 `file` 和 Bearer Token，并验证响应的 `status` 与 `.data.links.url`。
