# 设定基础镜像
ARG BASE_IMAGE=louislam/uptime-kuma:base2

############################################
# 阶段 1: 克隆源码
############################################
FROM alpine/git AS fetch-source
WORKDIR /src
RUN git clone --depth 1 https://github.com/louislam/uptime-kuma.git .

############################################
# 阶段 2: 构建 Go 健康检查工具
############################################
FROM louislam/uptime-kuma:builder-go AS build_healthcheck

############################################
# 阶段 3: Node.js 构建层 (修正 127 错误)
############################################
FROM louislam/uptime-kuma:base2 AS build
# 切换回 root 以确保有权限修改文件和安装组件
USER root
WORKDIR /app

# 安装构建可能需要的基础工具
RUN apt-get update && apt-get install -y sed curl && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers

# 从第一阶段拷贝源码
COPY --from=fetch-source /src /app

# --- 核心逻辑：强制升级 Playwright ---
# 1. 使用 sed 修改版本
# 2. 直接用 npm install 安装指定版本（会自动更新 package.json）
# 3. 安装浏览器及其系统依赖 (--with-deps)
RUN sed -i 's/"playwright": ".*"/"playwright": "1.56.0"/' package.json && \
    npm install playwright@1.56.0 && \
    npm ci --omit=dev && \
    npx playwright install --with-deps chromium

# 拷贝健康检查程序
COPY --from=build_healthcheck /app/extra/healthcheck /app/extra/healthcheck

# 统一修改权限，确保 node 用户可以访问
RUN mkdir -p ./data && chown -R node:node /app

############################################
# 阶段 4: ⭐ 主运行镜像 (Release)
############################################
FROM $BASE_IMAGE AS release
WORKDIR /app

ENV UPTIME_KUMA_IS_CONTAINER=1
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers

# 拷贝构建产物
COPY --chown=node:node --from=build /app /app

# 务必切换到 node 用户运行，以保证安全
USER node

EXPOSE 3001
HEALTHCHECK --interval=60s --timeout=30s --start-period=180s --retries=5 CMD extra/healthcheck

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "server/server.js"]
