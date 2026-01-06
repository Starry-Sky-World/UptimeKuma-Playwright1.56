# 设定运行时的基础镜像
ARG BASE_IMAGE=louislam/uptime-kuma:base2

############################################
# 阶段 1: 克隆源码
############################################
FROM alpine/git AS fetch-source
WORKDIR /src
# 这里克隆 2.x 版本的代码
RUN git clone --depth 1 https://github.com/louislam/uptime-kuma.git .

############################################
# 阶段 2: 构建 Go 健康检查工具
############################################
FROM louislam/uptime-kuma:builder-go AS build_healthcheck

############################################
# 阶段 3: 构建层 (完整构建前端 + 后端)
############################################
FROM node:20-bullseye AS build
WORKDIR /app

# 设置变量
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

# 1. 拷贝源码
COPY --from=fetch-source /src /app

# 2. 安装所有依赖 (包括构建前端所需的 devDependencies)
# 使用绝对路径确保在所有环境下 npm 都能找到
RUN /usr/local/bin/npm install

# 3. 【关键步骤】执行前端构建，生成 dist 目录
RUN /usr/local/bin/npm run build

# 4. 【你的特殊需求】升级并安装 Playwright 1.56
RUN /usr/local/bin/npm install playwright@1.56.0 && \
    /usr/local/bin/node /app/node_modules/playwright/cli.js install chromium

# 5. 清理开发依赖，减小镜像体积 (只保留运行必需的)
RUN /usr/local/bin/npm prune --omit=dev

# 6. 拷贝健康检查程序
COPY --from=build_healthcheck /app/extra/healthcheck /app/extra/healthcheck
RUN mkdir -p ./data && chown -R 1000:1000 /app

############################################
# 阶段 4: ⭐ 最终运行镜像
############################################
FROM $BASE_IMAGE AS release
WORKDIR /app

# 设置环境变量
ENV UPTIME_KUMA_IS_CONTAINER=1
ENV PLAYWRIGHT_BROWSERS_PATH=/app/pw-browsers
ENV NODE_ENV=production

# 拷贝构建好的所有文件（包含 dist, node_modules, pw-browsers 等）
COPY --chown=node:node --from=build /app /app

# 切换到 node 用户
USER node

EXPOSE 3001
HEALTHCHECK --interval=60s --timeout=30s --start-period=180s --retries=5 CMD extra/healthcheck

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "server/server.js"]
