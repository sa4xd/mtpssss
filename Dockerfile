FROM ubuntu:24.04

RUN apt-get update && apt-get install -y wget curl openssl && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY mtp.sh /app/mtp.sh
RUN chmod +x /app/mtp.sh

ENTRYPOINT ["/app/mtp.sh"]
