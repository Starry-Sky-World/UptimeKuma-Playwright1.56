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
# 阶段 3: 构建层 (使用最新 Node 20 镜像，确保环境最新)
############################################
FROM node:20-bullseye AS build
WORKDIR /app

# 设置核心变量
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

# 1. 拷贝源码
COPY --from=fetch-source /src /app

# 2. 【核心修复】强制升级 Playwright
# 使用绝对路径指向 npm，并确保全局和本地都安装，以绝后患
RUN /usr/local/bin/npm install -g playwright@1.56.0 && \
    /usr/local/bin/npm install playwright@1.56.0 && \
    /usr/local/bin/npm ci --omit=dev

# 3. 【核心修复】使用全局命令下载浏览器内核
# 如果 npx 找不到，就直接调用全局安装好的 playwright
RUN /usr/local/bin/node /usr/local/lib/node_modules/playwright/cli.js install chromium

# 4. 拷贝健康检查程序并处理权限
COPY --from=build_healthcheck /app/extra/healthcheck /app/extra/healthcheck
RUN mkdir -p ./data && chown -R 1000:1000 /app

############################################
# 阶段 4: ⭐ 最终运行镜像
############################################
FROM $BASE_IMAGE AS release
WORKDIR /app

ENV UPTIME_KUMA_IS_CONTAINER=1
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers

# 拷贝构建产物
COPY --chown=node:node --from=build /app /app

# 确保以 node 用户运行
USER node

EXPOSE 3001
HEALTHCHECK --interval=60s --timeout=30s --start-period=180s --retries=5 CMD extra/healthcheck

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "server/server.js"]
