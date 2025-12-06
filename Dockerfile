FROM ubuntu:24.04

# 安装依赖
RUN apt-get update && apt-get install -y wget curl openssl jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY mtp.sh /app/mtp.sh
RUN chmod +x /app/mtp.sh

# 声明环境变量（可在 docker run 时覆盖）
ENV MODE=tls \
    DOMAIN=www.cloudflare.com \
    PORT=443 \
    MTP_PORT=444 \
    SECRET=""

ENTRYPOINT ["/app/mtp.sh"]
