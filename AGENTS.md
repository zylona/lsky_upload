# lsky-upload Agent 约束

本文件适用于仓库根目录及全部子目录，约束参与本项目设计、实现、测试、部署和发布的 agent。

## 1. 项目边界

本项目包含两个彼此分离的部分：

1. 用户级 `lsky-upload` 客户端：读取本地配置，调用 Lsky Pro `/api/v1/upload`，输出图片 URL；
2. 仅用于验收的本地 Lsky Pro 服务：由 Docker Compose 启动，默认只监听 loopback。

生产图床的远程部署不属于本项目第一版职责。`re_debian` 只作为上传协议和服务部署的只读参考；不得复制生产环境凭据、域名、ACME 配置或运行数据。

用户在当前任务中的明确要求高于本文档。若实现改变顶层设计中的架构边界、配置契约或安全默认值，必须先同步更新设计/实施文档并说明原因。

## 2. 规范来源与工作顺序

开始实现前必须阅读：

1. `docs/top-level-design.md`：顶层目标和架构边界；
2. `docs/implementation-plan.md`：当前阶段、实现顺序和门禁；
3. `docs/implementation-status.md`：已完成内容和未验证风险；
4. `re_debian`/`re_remote_dev` 中被实施文档明确引用的只读参考。

实施必须按 P0 → P1 → P2 → P3 → P4 顺序推进。未完成前一阶段门禁时，不得把后一阶段标记为完成。

## 3. 工具链

当前项目是 Shell + Docker Compose 项目，不预置 Python 工程，不创建 `pyproject.toml` 或 `uv.lock`。

- 项目级工具版本由 `mise.toml` 管理；首次进入项目或版本变化后执行 `mise install`；
- Shell 代码使用 Bash，默认 `set -euo pipefail`，并通过 ShellCheck；
- 客户端运行依赖只允许明确检查 Bash、curl、jq；本地服务额外检查 Docker 和 `docker compose`；
- 如果未来确实需要 Python，必须先更新本文件和 `mise.toml`，由 mise 提供 Python/uv，再用 `uv add`/`uv lock` 管理依赖；禁止 pip、手工 `.venv` 和系统 Python 作为项目依赖来源；
- 不使用未经固定版本审阅的 `curl | sh`、浮动 Docker `latest` 镜像或未校验的下载脚本。

## 4. 配置和敏感信息

用户配置唯一默认路径：

```text
${XDG_CONFIG_HOME:-$HOME/.config}/lsky-upload/config.env
```

配置文件由用户持有，目录权限为 `0700`、文件权限不宽于 `0600`。Token 只能存在于该文件或用户明确指定的等价配置路径中，不得进入：

- 命令行参数、shell history 或进程标题；
- Compose 文件、仓库源码、测试 fixture、CI 日志和 Release 制品；
- stdout、stderr、异常信息、临时报告或构建清单。

仓库只能提交 `config.env.example`，只能使用占位符。`.local/`、测试上传目录、Docker 数据和本机配置必须被 Git 忽略。

## 5. 客户端实现约束

- 配置解析只接受白名单字段，未知字段报错；不执行配置文件内容；
- 默认拒绝非 HTTPS URL；仅允许 loopback 本地服务使用 HTTP，或由用户显式开启开发开关；
- API 使用 Bearer Token 和 multipart 字段 `file`；响应必须验证业务成功语义并提取 `.data.links.url`；
- stdout 只输出 URL，诊断信息进入 stderr；错误必须非零退出；
- 多图按输入顺序处理；首个失败停止，不输出虚假或不完整成功结果；
- 不把完整 API 响应写入日志；任何脱敏都必须在输出前完成；
- 版本安装不得覆盖已有用户配置。

## 6. 本地服务约束

- Compose 镜像必须固定版本或 digest，不使用 `latest`；
- 默认端口只绑定 `127.0.0.1`；不新增公网/LAN 暴露；
- SQLite、图片目录和必要应用状态必须持久化；停止、重启和容器重建不能清空数据；
- 服务状态不能只由 Docker `running` 判定，必须有 HTTP/API 验收；
- 管理员初始化和 Token 创建必须使用 Lsky 官方入口或明确记录的稳定接口，不直接改数据库；
- 删除测试数据必须是显式命令，不能由普通启动、升级或卸载隐式执行。

## 7. 测试和发布门禁

每个阶段必须同步更新文档、测试和状态记录。至少运行与变更对应的最小检查：

- `bash -n` 和 `shellcheck`；
- 配置/安装行为测试；
- `docker compose config`；
- P3 的真实本地 Lsky 上传闭环；
- P4 的干净用户目录安装、升级不覆盖配置、制品敏感信息审计和 SHA256 校验。

完成前必须运行 `git diff --check`，确认 `git status` 中没有 `.local/`、Token、密码、图片或 Docker 数据。不得自行提交、推送、切换分支或改写历史。
