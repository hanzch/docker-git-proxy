#!/usr/bin/env bash

# 检查必要的环境变量
if [ -z "$API_TOKEN" ] || [ -z "$ZONE_ID" ] || [ -z "$DOMAIN" ]; then
    echo "错误: 必须设置环境变量 API_TOKEN, ZONE_ID, DOMAIN"
    echo "请使用以下命令设置环境变量："
    echo "export API_TOKEN='your_api_token'"
    echo "export ZONE_ID='your_zone_id'"
    echo "export DOMAIN='xxxx.com'"
    exit 1
fi

# 配置参数
RECORDS="ui,hub,gcr,ghcr,k8sgcr,k8s,quay,mcr,elastic,nvcr"
AUTO_INSTALL=true
TTL="1"
PROXY="false"






# Docker Proxy 自动安装函数
autoinstall() {
    echo -e "1"        # 选择安装服务
    sleep 1
    echo -e "1"        # 选择一键部署所有服务
    sleep 1
    echo -e "y"        # 开启BBR
    sleep 1  
    echo -e "y"        # 安装软件包
    sleep 1
    echo -e "y"        # 安装WEB服务
    sleep 1
    echo -e "caddy"    # 选择Caddy作为WEB服务器
    sleep 1
    echo -e "y"        # 配置Caddy
    sleep 1
    echo -e "${DOMAIN}"  # 输入域名
    sleep 1
    echo -e "${RECORDS}" # 输入主机记录
    sleep 1
    echo -e "1"        # 选择国外环境
    sleep 1
    echo -e "1"        # 选择国外环境
    sleep 1
    echo -e "10"       # 选择安装所有服务
    sleep 1
    echo -e "n"        # 不修改缓存时间
    sleep 1
    echo -e "n"        # 不添加代理
}

# 更新单个DNS记录的函数
update_dns_record() {
    local subdomain=$1
    local record_name="${subdomain}.${DOMAIN}"
    
    # 获取当前公网 IP
    CURRENT_IP=$(curl -s http://ipv4.icanhazip.com)
    
    # 获取已存在的 DNS 记录
    RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$record_name" \
         -H "Authorization: Bearer $API_TOKEN" \
         -H "Content-Type: application/json")
    
    # 提取记录 ID 和已存在的 IP
    RECORD_ID=$(echo $RECORD | jq -r '.result[0].id')
    EXISTING_IP=$(echo $RECORD | jq -r '.result[0].content')
    
    # 如果记录不存在，创建新记录
    if [ "$RECORD_ID" = "null" ]; then
        echo "创建新记录: $record_name"
        CREATE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
             -H "Authorization: Bearer $API_TOKEN" \
             -H "Content-Type: application/json" \
             --data "{\"content\":\"${CURRENT_IP}\",\"name\":\"${record_name}\",\"proxied\":${PROXY},\"type\":\"A\",\"ttl\":${TTL}}")
        
        if [ "$(echo $CREATE_RESPONSE | jq -r '.success')" = "true" ]; then
            echo "DNS 记录创建成功: $record_name -> $CURRENT_IP"
        else
            echo "DNS 记录创建失败: $record_name"
            echo $CREATE_RESPONSE
        fi
        return
    fi
    
    # 如果 IP 没有变化，跳过更新
    if [ "$CURRENT_IP" = "$EXISTING_IP" ]; then
        echo "IP 没有变化，跳过更新: $record_name"
        return
    fi
    
    # 更新现有记录
    UPDATE_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
         -H "Authorization: Bearer ${API_TOKEN}" \
         -H "Content-Type: application/json" \
         --data "{\"content\":\"${CURRENT_IP}\",\"name\":\"${record_name}\",\"proxied\":${PROXY},\"type\":\"A\",\"ttl\":${TTL}}")
    
    if [ "$(echo $UPDATE_RESPONSE | jq -r '.success')" = "true" ]; then
        echo "DNS 记录更新成功: $record_name -> $CURRENT_IP"
    else
        echo "DNS 记录更新失败: $record_name"
        echo $UPDATE_RESPONSE
    fi
}

# 更新所有DNS记录的函数
update_all_dns_records() {
    echo "开始更新 DNS 记录..."
    RECORDS="git,$RECORDS"
    IFS=',' read -ra SUBDOMAIN_ARRAY <<< "$RECORDS"
    for subdomain in "${SUBDOMAIN_ARRAY[@]}"; do
        update_dns_record "$subdomain"
    done
    echo "DNS 记录更新完成"
}


install_docker() {
    apt update
    apt upgrade -y
    apt install git curl vim wget gnupg dpkg apt-transport-https lsb-release ca-certificates -y

    curl -sS https://download.docker.com/linux/debian/gpg | gpg --dearmor > /usr/share/keyrings/docker-ce.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-ce.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian $(lsb_release -sc) stable" > /etc/apt/sources.list.d/docker.list


    apt update
    apt install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y
}


install_gh-proxy() {

    docker run -d --name="gh-proxy-py"   -p 0.0.0.0:60000:80   --restart=always  hunsh/gh-proxy-py:latest
    cat << 'EOF' >> /etc/caddy/Caddyfile

git.acap.cc {
    reverse_proxy localhost:60000 {
        header_up Host {host}
        header_up X-Real-IP {remote_addr}
        header_up X-Forwarded-For {remote_addr}
        header_up X-Nginx-Proxy true
    }
}
EOF

    systemctl reload caddy
}


# 主函数
main() {
    echo "开始安装 docker..."
    install_docker

    echo "开始安装 Docker Proxy..."
    # 下载并执行Docker Proxy安装脚本
    curl -fsSL https://raw.githubusercontent.com/dqzboy/Docker-Proxy/main/install/DockerProxy_Install.sh -o docker_proxy_install.sh
    chmod +x docker_proxy_install.sh
    autoinstall | bash docker_proxy_install.sh
    rm -f docker_proxy_install.sh
    
    echo "Docker Proxy 安装完成"
    
    # 等待一段时间确保服务启动
    sleep 10
    
    echo "开始配置 Cloudflare DNS..."
    update_all_dns_records

    echo "安装 gh-proxy..."
    install_gh-proxy



}

# 执行主函数
main "$@"