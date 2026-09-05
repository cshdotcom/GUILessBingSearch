# Docker 部署指南(GUI-Less Bing Search)

本项目已容器化。GitHub CI(`.github/workflows/docker.yml`)在每次代码变更时自动构建 **amd64** 镜像并推送到 GitHub 容器仓库,开箱即用(PySide6 6.9+ 上游不再发布 aarch64 wheel,故暂不提供 arm64 镜像)。

| 项 | 值 |
|---|---|
| 镜像地址 | `ghcr.io/cshdotcom/guiless-bing-search` |
| 常用标签 | `latest`(master 最新)、`vX.Y.Z`(版本)、`sha-xxxxxxx`(提交) |
| 基础镜像 | `python:3.12-slim-bookworm` |
| 镜像体积 | 压缩约 500 MB(QtWebEngine 自带完整 Chromium,属正常水平) |
| 监听端口 | 容器内 `8765`(由 `PORT` 环境变量控制) |
| 架构 | linux/amd64(arm64 因 PySide6 停发 aarch64 wheel 暂不发布) |

## 快速开始

```bash
# 一行启动(大陆网络一般可直连 ghcr.io)
docker run -d --name bing-search \
  -p 8765:8765 \
  -v $PWD/data:/data \
  ghcr.io/cshdotcom/guiless-bing-search:latest

# 健康检查
curl http://127.0.0.1:8765/health
# → {"status": "ok"}

# 首次搜索(同时完成浏览器 profile 热身)
curl -s -X POST http://127.0.0.1:8765/search \
  -H "Content-Type: application/json" \
  -d '{"query": "云计算", "count": 5}'
```

或使用仓库里的 `docker-compose.yml`:

```bash
docker compose up -d
docker compose logs -f        # 观察启动与搜索日志
```

## 多结果自动翻页聚合(本 fork 增强)

当请求的 `count` 超过单页结果数(约 10 条)时,引擎自动跟随 Bing 自家的下一页链接(携带原生 FORM/FPIG 签名参数,浏览器自然行为)跨页聚合,**按去重后链接凑满 `count` 即停止**,不会无限抓取:

- 达到 `count` → 立即停止聚合并返回
- Bing 返回"无更多结果"页 → 停止
- 下一页无新增(重复页)→ 停止
- 最多 8 页(80 条)硬上限
- 聚合中途网络失败 → 返回已聚合的部分结果

```bash
# 要 30 条?直接说,服务自己翻页凑齐
curl -s -X POST http://127.0.0.1:8765/search \
  -H "Content-Type: application/json" \
  -d '{"query": "cloud computing", "count": 30}' | python3 -m json.tool
```

`/mcp` 端点(Model Context Protocol,`search_bing` 工具)同样享受该能力,`count` 上限 30。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | `8765` | 容器内监听端口 |
| `API_KEY` | (空) | 设置后所有端点要求 `Authorization: Bearer <KEY>` |
| `SEARCH_INTERVAL` | `1` | 相邻搜索最小间隔秒数(自动加 0~50% 抖动,善待上游) |
| `BING_BASE_URL` | `https://www.bing.com` | 大陆网络若被重定向,可固定为 `https://cn.bing.com` |
| `BING_ENSEARCH` | (自适应) | `1` 强制国际版 / `0` 强制国内版(cn 域名时有效) |
| `BING_U_COOKIE` | (空) | 排障用,注入已知良好 `_U` Cookie |
| `USER_AGENT` | (自动) | 自定义 UA |

容器内置(一般无需覆盖):`QT_QPA_PLATFORM=offscreen`、`QTWEBENGINE_DISABLE_SANDBOX=1`、`QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --disable-software-rasterizer --no-sandbox"`(容器内 root 运行必需)、`HOST=0.0.0.0`、`XDG_DATA_HOME=/data`。

## 数据持久化

浏览器 profile(Cookie、本地存储)存放在容器内 `/data`,**务必挂载卷**:

```bash
-v $PWD/data:/data
```

持久会话的意义:保留 Bing 下发的 Cookie 可显著提升深翻页可靠性(本工具用真实浏览器内核,非裸 HTTP 抓取,这正是它比传统 scraper 翻页更稳的原因)。删除 `data/` 目录即重置会话。

## 大陆网络注意事项

1. **拉取镜像**:ghcr.io 大陆一般可直连;若超时可配 `https://ghcr.nju.edu.cn` 等镜像加速。
2. **搜索流量**:服务本身访问 `www.bing.com` 在大陆无需代理。若你的网络把 `www.bing.com` 重定向到 `cn.bing.com`,建议显式设 `BING_BASE_URL=https://cn.bing.com`。
3. **国际版结果**:`cn.bing.com` 域名下默认自动附加 `ensearch=1` 保持国际结果路径;`BING_ENSEARCH=0` 可切回国内版。

## 本地构建(不依赖 GHCR)

```bash
git clone https://github.com/cshdotcom/GUILessBingSearch.git
cd GUILessBingSearch
docker build -t guiless-bing-search .
docker run -d -p 8765:8765 -v $PWD/data:/data guiless-bing-search
```

## 常见问题

**Q: 启动后 `/health` 一直不通?**
`docker logs bing-search` 查看。首次启动需初始化 QtWebEngine(数秒);若见 `lib*.so: cannot open` 说明镜像系统库不完整(CI 已实测校准,本地魔改 Dockerfile 时注意保留依赖清单)。

**Q: 搜索返回 0 条?**
查看日志中 `navigate` 行之后的页面情况。偶发为 Bing 对新会话的质询页(challenge),稍等重试即可;频繁出现时删除 `data/` 重置 profile,或配置 `BING_U_COOKIE`。

**Q: 内存占用?**
QtWebEngine 渲染进程典型 300~500 MB RSS;低内存设备建议 `docker run --shm-size=512m --memory=1g`。

**Q: 与上游 wszqkzqk/GUILessBingSearch 的差异?**
本 fork 增加多页自动聚合(count>10 场景),并新增 Docker/CI 交付链。上游其余功能(HTTP API、MCP 端点、Cookie 注入、systemd 部署等)完全一致。
