#!/bin/bash

red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }

HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

WORKDIR="$HOME/mtp" && mkdir -p "$WORKDIR"
pgrep -x mtg > /dev/null && pkill -9 mtg >/dev/null 2>&1

# ===== Config knobs =====
# MODE: tls | secure | simple
MODE=${MODE:-tls}
DOMAIN=${DOMAIN:-www.wikipedia.org}      # Used only when MODE=tls
PORT=${PORT:-}                           # For non-serv00 hosts; if empty, auto
MTP_PORT=${MTP_PORT:-}                   # For serv00 hosts; set by check_port()

# If SECRET is not provided, auto-generate depending on MODE
generate_secret() {
  case "$MODE" in
    tls)
      # "ee" + 16-byte random hex (clients infer fake-TLS; DOMAIN required for SNI)
      basehex=$(openssl rand -hex 16)
      SECRET="ee${basehex}"
      ;;
    secure)
      # "dd" + 16-byte random hex (secure mode)
      basehex=$(openssl rand -hex 16)
      SECRET="dd${basehex}"
      ;;
    simple|*)
      # plain 32-hex
      SECRET=$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32)
      ;;
  esac
}

validate_secret() {
  case "$MODE" in
    tls)
      [[ -z "$DOMAIN" ]] && { red "TLS模式需要设置 DOMAIN"; exit 1; }
      [[ "$SECRET" != ee* ]] && yellow "提示: TLS模式通常使用以'ee'开头的secret"
      ;;
    secure)
      [[ "$SECRET" != dd* ]] && yellow "提示: 安全模式通常使用以'dd'开头的secret"
      ;;
    simple)
      [[ "$SECRET" == ee* || "$SECRET" == dd* ]] && yellow "提示: simple模式不需要ee/dd前缀"
      ;;
  esac
}

# Init SECRET if missing
if [[ -z "$SECRET" ]]; then
  generate_secret
else
  validate_secret
fi
export SECRET

# ===== Serv00/ct8 port management =====
check_port () {
  port_list=$(devil port list)
  tcp_ports=$(echo "$port_list" | grep -c "tcp")
  udp_ports=$(echo "$port_list" | grep -c "udp")

  if [[ $tcp_ports -lt 1 ]]; then
      red "没有可用的TCP端口,正在调整..."

      if [[ $udp_ports -ge 3 ]]; then
          udp_port_to_delete=$(echo "$port_list" | awk '/udp/ {print $1}' | head -n 1)
          devil port del udp $udp_port_to_delete
          green "已删除udp端口: $udp_port_to_delete"
      fi

      while true; do
          tcp_port=$(shuf -i 10000-65535 -n 1)
          result=$(devil port add tcp $tcp_port 2>&1)
          if [[ $result == *"Ok"* ]]; then
              green "已添加TCP端口: $tcp_port"
              tcp_port1=$tcp_port
              break
          else
              yellow "端口 $tcp_port 不可用，尝试其他端口..."
          fi
      done
  else
      tcp_ports=$(echo "$port_list" | awk '/tcp/ {print $1}')
      tcp_port1=$(echo "$tcp_ports" | sed -n '1p')
  fi
  devil binexec on >/dev/null 2>&1
  MTP_PORT=$tcp_port1
  green "使用 $MTP_PORT 作为TG代理端口"
}

get_ip() {
  IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
  API_URL="https://status.eooce.com/api"
  IP1=""; IP2=""; IP3=""
  AVAILABLE_IPS=()

  for ip in "${IP_LIST[@]}"; do
      RESPONSE=$(curl -s --max-time 2 "${API_URL}/${ip}")
      if [[ -n "$RESPONSE" ]] && [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
          AVAILABLE_IPS+=("$ip")
      fi
  done

  [[ ${#AVAILABLE_IPS[@]} -ge 1 ]] && IP1=${AVAILABLE_IPS[0]}
  [[ ${#AVAILABLE_IPS[@]} -ge 2 ]] && IP2=${AVAILABLE_IPS[1]}
  [[ ${#AVAILABLE_IPS[@]} -ge 3 ]] && IP3=${AVAILABLE_IPS[2]}

  if [[ -z "$IP1" ]]; then
      red "所有IP都被墙, 请更换服务器安装"
      exit 1
  fi
}

download_run(){
  if [ -e "${WORKDIR}/mtg" ]; then
      cd ${WORKDIR} && chmod +x mtg
      nohup  ./mtg run -b 0.0.0.0:$MTP_PORT $SECRET --stats-bind=127.0.0.1:$MTP_PORT >/dev/null 2>&1 &
  else
      mtg_url="https://github.com/eooce/test/releases/download/freebsd/mtg-freebsd-amd64"
      wget -q -O "${WORKDIR}/mtg" "$mtg_url"

      if [ -e "${WORKDIR}/mtg" ]; then
          cd ${WORKDIR} && chmod +x mtg
         nohup   ./mtg run -b 0.0.0.0:$MTP_PORT $SECRET --stats-bind=127.0.0.1:$MTP_PORT >/dev/null 2>&1 &
      fi
  fi
}

generate_info() {
  purple "\n分享链接:\n"
  LINKS=""
  tls_note=""
  if [[ "$MODE" == "tls" ]]; then
    tls_note=" (TLS伪装域名: $DOMAIN)"
  fi

  [[ -n "$IP1" ]] && LINKS+="tg://proxy?server=$IP1&port=$MTP_PORT&secret=$SECRET"
  [[ -n "$IP2" ]] && LINKS+="\n\ntg://proxy?server=$IP2&port=$MTP_PORT&secret=$SECRET"
  [[ -n "$IP3" ]] && LINKS+="\n\ntg://proxy?server=$IP3&port=$MTP_PORT&secret=$SECRET"

  green "$LINKS$tls_note\n"
  echo -e "$LINKS" > "$WORKDIR/link.txt"

  cat > ${WORKDIR}/restart.sh <<EOF
#!/bin/bash
pkill mtg
cd ${WORKDIR}
nohup   ./mtg run -b 0.0.0.0:$MTP_PORT $SECRET --stats-bind=127.0.0.1:$MTP_PORT >/dev/null 2>&1 &
EOF
  chmod +x ${WORKDIR}/restart.sh
}

download_mtg(){
  cmd=$(uname -m)
  if [ "$cmd" == "x86_64" ] || [ "$cmd" == "amd64" ] ; then
      arch="amd64"
  elif [ "$cmd" == "aarch64" ] || [ "$cmd" == "arm64" ] ; then
      arch="arm64"
  else
      arch="amd64"
  fi

  wget -qO "${WORKDIR}/mtg" "https://$arch.ssss.nyc.mn/mtg-linux-$arch"

  # If user didn’t set PORT, choose a random one for normal hosts.
  if [[ -z "$PORT" ]]; then
    PORT=$(shuf -i 200-1000 -n 1)
  fi
  [[ -z "$MTP_PORT" ]] && MTP_PORT=$((PORT + 1))

  if [ -e "${WORKDIR}/mtg" ]; then
      cd ${WORKDIR} && chmod +x mtg
      nohup  ./mtg run -b 0.0.0.0:$PORT $SECRET --stats-bind=127.0.0.1:$MTP_PORT >/dev/null 2>&1 &
  fi
}

show_link(){
  ip=$(curl -s ip.sb)
  purple "\nTG分享链接(如获取的是ipv6,可自行将ipv6换成ipv4):\n"
  tls_note=""
  if [[ "$MODE" == "tls" ]]; then
    tls_note=" (TLS伪装域名: $DOMAIN)"
  fi
  LINKS="tg://proxy?server=$ip&port=$PORT&secret=$SECRET"
  green "$LINKS$tls_note\n"
  echo -e "$LINKS" > "$WORKDIR/link.txt"

  purple "\n一键卸载命令: rm -rf mtp && pkill mtg"
}

install(){
  purple "正在安装中,请稍等...\n"
  if [[ "$HOSTNAME" =~ serv00.com|ct8.pl|useruno.com ]]; then
      check_port
      get_ip
      download_run
      generate_info
  else
      download_mtg
      show_link
  fi
}

# ===== Entry =====
install
