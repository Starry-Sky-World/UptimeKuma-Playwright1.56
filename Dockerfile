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
# 阶段 3: Node.js 构建层 (核心修改：升级 Playwright)
############################################
FROM louislam/uptime-kuma:base2 AS build
USER node
WORKDIR /app

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers

# 从第一阶段拷贝源码
COPY --chown=node:node --from=fetch-source /src /app

# --- 核心逻辑：强制升级 Playwright 至 1.56 ---
RUN sed -i 's/"playwright": ".*"/"playwright": "1.56.0"/' package.json && \
    npm install playwright@1.56.0 && \
    npm ci --omit=dev && \
    npx playwright install chromium

# 拷贝健康检查程序
COPY --chown=node:node --from=build_healthcheck /app/extra/healthcheck /app/extra/healthcheck
RUN mkdir ./data

############################################
# 阶段 4: ⭐ 主运行镜像 (Release)
############################################
FROM $BASE_IMAGE AS release
WORKDIR /app

ENV UPTIME_KUMA_IS_CONTAINER=1
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers

# 拷贝所有产物
COPY --chown=node:node --from=build /app /app

EXPOSE 3001
HEALTHCHECK --interval=60s --timeout=30s --start-period=180s --retries=5 CMD extra/healthcheck

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "server/server.js"]
