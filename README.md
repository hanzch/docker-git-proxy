# docker-git-proxy

一键自动部署 Docker Proxy + gh-proxy

## 快速安装

使用以下命令一键安装:

```bash
export API_TOKEN='Your token'
export ZONE_ID='Your zone_id'
export DOMAIN='xxxx.com'

apt -y install curl

bash -c "$(curl -fsSL https://raw.githubusercontent.com/hanzch/docker-git-proxy/main/install/install.sh)"
