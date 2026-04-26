# VLESS + REALITY 自动部署

这个目录提供一个本地执行的部署脚本。你只需要改服务器地址和 SSH 登录方式，就可以把 `sing-box` 的 `VLESS + REALITY` 服务端部署到远端 Linux 服务器。

## 前提

- 远端系统需要能访问 GitHub 下载 `sing-box` 发布包
- 远端需要 `systemd`
- 本机需要 `ssh`、`scp`、`python3`、`uuidgen`、`openssl`
- 如果使用密码登录，本机还需要 `sshpass`

## 使用方式

1. 复制配置模板：

```bash
cp /Users/jeff/Projects/VPN/deploy/vless-reality.env.example /Users/jeff/Projects/VPN/deploy/vless-reality.env
```

2. 编辑 `/Users/jeff/Projects/VPN/deploy/vless-reality.env`

最少只要改这些：

- `SERVER_HOST`
- `SSH_USER`
- `SSH_KEY_PATH` 或 `SSH_PASSWORD`

常用可选项：

- `SERVER_PORT`
- `REALITY_SERVER_NAME`
- `UUID`
- `REALITY_SHORT_ID`
- `LOCAL_MIXED_PORT`
- `OUTPUT_DIR`

3. 执行部署：

```bash
bash /Users/jeff/Projects/VPN/deploy/deploy-vless-reality.sh
```

也可以指定别的环境文件：

```bash
bash /Users/jeff/Projects/VPN/deploy/deploy-vless-reality.sh /path/to/your.env
```

## 脚本会做什么

- 通过 SSH 登录远端
- 检查并安装 `sing-box`
- 在远端生成 REALITY 密钥对
- 渲染并上传 `/etc/sing-box/config.json`
- 创建或复用 `systemd` 服务
- 如果远端启用了 `ufw`，自动放行服务端口的 TCP 入站
- 启动并重启 `sing-box`
- 输出客户端所需的 `UUID`、`public_key`、`short_id`
- 在本地生成 `sing-box` 客户端配置
- 在本地生成 `sing-box` 手机客户端配置
- 在本地生成 Clash Verge 可导入配置

## 说明

- 默认使用 `xtls-rprx-vision`
- 默认监听 `443`
- 默认伪装目标是 `www.cloudflare.com:443`
- 如果你要换伪装域名，只改 `REALITY_SERVER_NAME` 和 `REALITY_SERVER_PORT`
- 默认本地代理端口是 `7777`
- 默认输出根目录是 `/Users/jeff/Projects/VPN/deploy/output`，实际配置会写入按服务器地址命名的子目录，比如 `output/203.0.113.10/`
- `sing-box-desktop.json` 适合桌面本地代理模式
- `sing-box-mobile.json` 适合手机 `sing-box` 的 VPN/TUN 模式
