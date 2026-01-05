FROM ubuntu:24.04

# 安装依赖
RUN apt-get update && apt-get install -y wget curl openssl jq python3 git golang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# -------------------------
# 1. 构建 cftun
# -------------------------
RUN git clone https://github.com/fmnx/cftun.git /app/cftun-src \
    && cd /app/cftun-src \
    && go build -o /usr/local/bin/cftun .

# -------------------------
# 2. 拷贝 MTProxy 脚本
# -------------------------
COPY mtp.sh /app/mtp.sh
COPY index.html /app/index.html
RUN chmod +x /app/mtp.sh

# -------------------------
# 3. 环境变量（可 docker run 覆盖）
# -------------------------
ENV MODE=tls \
    DOMAIN=azure.microsoft.com \
    PORT=443 \
    MTP_PORT=6443 \
    SECRET="" \
    ARGO_TOKEN="" \
    ARGO_HOSTNAME=""

# -------------------------
# 4. 启动脚本：MTProxy + cftun + Web
# -------------------------
CMD /bin/bash -c "\
    echo '启动 MTProxy...' && \
    /app/mtp.sh & \
    echo '生成 cftun 配置...' && \
    echo \"tunnels:\n  - hostname: ${ARGO_HOSTNAME}\n    service: tcp://127.0.0.1:${MTP_PORT}\n    protocol: tcp\" > /app/cftun.yaml && \
    echo '启动 cftun...' && \
    cftun --config /app/cftun.yaml --token ${ARGO_TOKEN} & \
    echo '启动 Web 服务 (3000)...' && \
    python3 -m http.server 3000 --directory /app \
"
