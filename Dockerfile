# GUI-Less Bing Search — 无头 QtWebEngine 容器镜像
#
# 构建:  docker build -t guiless-bing-search .
# 运行:  docker run -d -p 8765:8765 -v ./data:/data guiless-bing-search
# 基础镜像: python:3.12-slim-bookworm(与 PySide6 manylinux_2_28 glibc 兼容)
FROM python:3.12-slim-bookworm

LABEL org.opencontainers.image.title="GUI-Less Bing Search" \
      org.opencontainers.image.description="Headless Bing search service powered by Qt6 WebEngine (PySide6), with automatic pagination aggregation" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.source="https://github.com/cshdotcom/GUILessBingSearch"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # Qt 离屏渲染 + WebEngine 禁 GPU(容器无显示/无显卡)
    QT_QPA_PLATFORM=offscreen \
    # 容器内以 root 运行,Chromium 用户态沙箱必须显式关闭
    QTWEBENGINE_DISABLE_SANDBOX=1 \
    QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --disable-software-rasterizer --no-sandbox" \
    # 容器网络语义:绑定所有接口(默认 127.0.0.1 在容器里无意义)
    HOST=0.0.0.0 \
    PORT=8765 \
    # 浏览器 profile 持久化目录(挂载 /data 卷即可保留 Cookie 会话)
    XDG_DATA_HOME=/data

# QtWebEngine 无头运行所需的系统库全集
# (经 bookworm rootfs + proot 导入链逐库枚举校准:
#  apt 自动解析 libglvnd/libxau/libfreetype 等间接依赖,
#  但 libglib2.0-0 / libxkbfile1 / libatomic1 无上游触发,必须显式声明)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 libegl1 \
        libnss3 libnspr4 \
        libxkbcommon0 libxkbcommon-x11-0 \
        libxcomposite1 libxdamage1 libxrandr2 libxfixes3 libxi6 libxtst6 \
        libxrender1 libx11-xcb1 \
        libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-shm0 \
        libxcb-sync1 libxcb-xfixes0 libxcb-xkb1 \
        libasound2 libdbus-1-3 libfontconfig1 \
        libglib2.0-0 libxkbfile1 libatomic1 \
        fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# 完整 PySide6:QtWebEngine 实体库(QtWebEngineProcess/libQt6WebEngineCore)位于 Addons 分包
RUN pip install --no-cache-dir PySide6==6.9.3

WORKDIR /app
COPY guiless_bing_search.py .
COPY COPYING ./COPYING

VOLUME ["/data"]
EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT','8765'), timeout=3)" || exit 1

CMD ["python", "guiless_bing_search.py"]
