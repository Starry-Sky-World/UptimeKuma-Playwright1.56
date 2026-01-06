# 设定运行时的基础镜像
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
# 阶段 3: 构建层 (使用官方 Node 镜像，确保所有命令可用)
############################################
FROM node:18-bullseye AS build
WORKDIR /app

# 设置 Playwright 浏览器存放路径
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

# 1. 从 fetch-source 拷贝源码
COPY --from=fetch-source /src /app

# 2. 升级 Playwright 并安装依赖
# 不再使用 sed，直接用 npm install 强制升级，这会自动修改 package.json
RUN npm install playwright@1.56.0 && \
    npm ci --omit=dev

# 3. 安装 Playwright 浏览器内核 (Chromium)
RUN npx playwright install chromium

# 4. 拷贝健康检查程序
COPY --from=build_healthcheck /app/extra/healthcheck /app/extra/healthcheck

# 5. 准备数据目录并处理权限
RUN mkdir -p ./data && chown -R 1000:1000 /app

############################################
# 阶段 4: ⭐ 最终运行镜像
############################################
FROM $BASE_IMAGE AS release
WORKDIR /app

ENV UPTIME_KUMA_IS_CONTAINER=1
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers

# 从构建阶段拷贝完整的 /app 目录
# 此时已经包含了升级好的 node_modules 和浏览器内核
COPY --chown=node:node --from=build /app /app

# 切换到 node 用户（ID 为 1000）
USER node

EXPOSE 3001
HEALTHCHECK --interval=60s --timeout=30s --start-period=180s --retries=5 CMD extra/healthcheck

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "server/server.js"]
