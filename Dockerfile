FROM ubuntu:24.04

# 安装依赖
RUN apt-get update && apt-get install -y wget curl openssl jq python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 拷贝脚本
COPY mtp.sh /app/mtp.sh
COPY index.html /app/index.html
RUN chmod +x /app/mtp.sh

# 声明环境变量（可在 docker run 时覆盖）
ENV MODE=tls \
    DOMAIN=www.cloudflare.com \
    PORT=443 \
    MTP_PORT=444 \
    SECRET=""

# 启动脚本和 Web 服务
CMD ["/bin/bash", "-c", "/app/mtp.sh & python3 -m http.server 3000 --directory /app"]
