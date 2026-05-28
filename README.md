# hermes-mimo-setup

一条命令安装 Hermes Agent，并直接打开适合配置小米 MiMo 的 Hermes Dashboard 页面。

```bash
curl -fsSL https://raw.githubusercontent.com/liyangxu1/hermes-mimo-setup/main/install.sh | bash
```

脚本会做这些事：

- 检测本机是否已有 `hermes` 命令；已有则跳过安装。
- 未检测到 Hermes 时，调用 Hermes 官方安装脚本并使用 `--skip-setup`。
- 检查 Hermes Dashboard 所需的 `fastapi`、`uvicorn` 依赖，缺失时自动安装。
- 从 `9119` 开始寻找可用端口，后台启动 Hermes Web Dashboard。
- 如果尚未配置 `XIAOMI_API_KEY`，打开 `http://127.0.0.1:<port>/env`。
- 如果已配置 `XIAOMI_API_KEY`，打开 `http://127.0.0.1:<port>/models`。

脚本不会接收、打印或保存 API Key。Key 只在 Hermes Dashboard 里填写，避免进入 shell history。

## MiMo 配置

第一次运行通常会打开 Dashboard 的 `Keys` 页面。展开 `Xiaomi MiMo` 后按自己的套餐填写：

按量 API：

- `XIAOMI_API_KEY=sk-...`
- `XIAOMI_BASE_URL` 留空，或使用 `https://api.xiaomimimo.com/v1`

Token Plan：

- `XIAOMI_API_KEY=tp-...`
- `XIAOMI_BASE_URL` 设置为订阅管理页面中的专属 Base URL

保存 Key 后，进入 `Models -> Model Settings -> Main model -> Change`，搜索 `Xiaomi MiMo`，选择 `mimo-v2.5-pro`。

官方教程：[小米 MiMo Hermes Agent 集成文档](https://platform.xiaomimimo.com/docs/zh-CN/integration/hermes-agent)

## 可选参数

```bash
curl -fsSL https://raw.githubusercontent.com/liyangxu1/hermes-mimo-setup/main/install.sh | bash -s -- --port 9120
curl -fsSL https://raw.githubusercontent.com/liyangxu1/hermes-mimo-setup/main/install.sh | bash -s -- --no-open
curl -fsSL https://raw.githubusercontent.com/liyangxu1/hermes-mimo-setup/main/install.sh | bash -s -- --open models
```

支持的参数：

- `--port PORT`：Dashboard 起始端口，默认 `9119`，端口被占用时自动递增。
- `--no-open`：启动 Dashboard 后不自动打开浏览器。
- `--force-install`：即使检测到 `hermes`，也重新运行 Hermes 官方安装脚本。
- `--skip-install`：未检测到 `hermes` 时直接失败，不自动安装。
- `--open auto|env|models`：指定打开页面；默认 `auto`。
- `--dry-run`：只打印将执行的动作，不安装、不启动、不打开浏览器。

## 当前范围

v1 只覆盖 MiMo 教程中的按量 API 和 Token Plan。Coding Plan 暂不在脚本里处理。

本仓库不修改 Hermes 源码，也不 fork Dashboard，只复用 Hermes 自带的 Web Dashboard。
