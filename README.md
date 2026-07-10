# 瀚纳仕 AI 打工命盘 H5

这是一个瀚纳仕 AI 打工命盘 H5 项目，生产入口为 `瀚纳仕H5 demo-启动舱.html`。页面可以在没有接口时使用本地兜底文案；如果要让“AI 算卦”每次生成不同标题和内容，需要通过 `server.mjs` 启动同源 API 代理，由服务端读取 API Key 后请求模型接口。

不要把 API Key 写进 HTML、脚本或 Git 仓库。请在服务器环境变量里配置密钥，本仓库只保留 `.env.example` 占位示例。

## 本地 AI 预览

Node.js 18+ 可以直接运行内置代理服务：

```bash
export HAYS_AI_API_KEY="replace-with-your-key"
export HOST="0.0.0.0"
node server.mjs
```

服务默认只监听 `127.0.0.1:5173`。需要手机同网段直接预览时，临时设置 `HOST=0.0.0.0`，再访问电脑局域网 IP 的 `5173` 端口。

可选环境变量：

- `HAYS_AI_API_KEY`：模型 API Key；也兼容 `DEEPSEEK_API_KEY` 和 `AI_API_KEY`。
- `HAYS_AI_API_BASE_URL`：默认 `https://api.deepseek.com`。
- `HAYS_AI_MODEL`：默认 `deepseek-v4-flash`。
- `HAYS_AI_TIMEOUT_MS`：模型接口超时时间，默认 `45000`。
- `HOST`：监听地址，默认 `127.0.0.1`；生产环境由 Nginx 反代，不需要直接暴露 `5173`。
- `PORT`：默认 `5173`。

如果没有配置密钥，页面会自动回退到本地内置文案，流程不会中断。

可以用状态接口确认线上是否真的启用了模型调用：

```bash
curl https://你的域名/api/fortune/status
```

`"configured":true` 表示服务端已经读到密钥；`false` 表示页面仍会使用本地兜底。状态接口只返回配置状态、服务商类型和模型名，不会返回密钥。

## Ubuntu + Nginx 部署

仓库提供 `scripts/deploy.sh`，适用于 Ubuntu 22.04 及更新版本。脚本会从 GitHub 拉取指定分支/标签，使用时间戳 release 目录发布到 `/opt/hays0709`，再原子切换 `current` 软链接。Nginx 始终指向这个稳定软链接，因此更新过程中不会暴露半套文件。

部署脚本会自动安装 Node.js 22（服务器已有 Node.js 18+ 时复用现有版本），注册 `hays0709.service` 常驻运行 `server.mjs`，并让 Nginx 把 `/api/fortune` 反代到本机 `127.0.0.1:5173`。页面文件和 AI 接口因此使用同一个域名访问，服务器不需要向公网开放 `5173`。

### 部署前准备

服务器需要满足：

- Ubuntu 22.04+、`sudo`、`systemd`、`apt` 和出站网络；
- 域名的 A/AAAA 记录已经指向服务器；
- 防火墙或云安全组放行 TCP `80` 和 `443`；
- 如果仓库是私有仓库，服务器已经配置 GitHub Deploy Key 或其他 Git 凭据。不要把凭据写进脚本或仓库。

脚本首次运行会自动安装 `git`、`nginx`、`rsync` 和 `curl`。执行 HTTPS 部署时，还会安装 `certbot` 和 `python3-certbot-nginx`。

### 配置 AI 密钥

首次部署会创建仅 `root` 和 `www-data` 可读的 `/etc/hays0709.env`。编辑该文件填入真实密钥：

```bash
sudo nano /etc/hays0709.env
sudo systemctl restart hays0709
```

至少配置：

```dotenv
HAYS_AI_API_KEY=replace-with-your-key
```

不要提交这个服务器环境文件。没有配置密钥时，`/api/fortune` 会返回未配置状态，前端自动使用本地兜底文案，页面仍可正常访问。

部署结束时脚本会检查 `/api/fortune/status`。代理可访问但密钥缺失时会输出明确警告，不再把 `OPTIONS 204` 当作“AI 已配置”的依据。

### 首次部署 HTTP

```bash
git clone https://github.com/wuinin2025-boop/hays0709.git
cd hays0709
sudo bash scripts/deploy.sh --domain example.com
```

将 `example.com` 换成实际域名。脚本会生成 `/etc/nginx/sites-available/hays0709.conf`，启用站点，校验 `nginx -t`，启动或重载 Nginx，并检查域名虚拟主机是否返回 HTTP 200 且包含 `今天的班`。

### 首次部署 HTTPS

确认域名 DNS 已生效且 80/443 端口可访问后执行：

```bash
sudo bash scripts/deploy.sh --domain example.com --https --email admin@example.com
```

`--email` 是 Certbot 的证书联系邮箱，不能省略。脚本使用非交互模式申请证书，并配置 HTTP 到 HTTPS 跳转。证书和私钥保存在服务器的 `/etc/letsencrypt/`，不会进入 Git。

### 服务器 443 已被 x-ui/Xray 占用

如果服务器已经用 x-ui/Xray 在公网 `443` 提供 VLESS + TLS，不要停止 Xray，也不要运行普通的 `--https` 部署覆盖它。新版部署脚本会在 Certbot 执行前检测端口冲突，并提示使用共存脚本。

先完成普通 HTTP 部署，再执行：

```bash
sudo bash scripts/deploy.sh --domain wuininyyy2026.xyz
sudo bash scripts/configure-xray-fallback.sh --domain wuininyyy2026.xyz
```

共存脚本要求 x-ui 中已经存在一个启用的 `443` VLESS + TLS 入站，并且该入站已经配置域名证书。脚本不会申请或替换 Xray 证书，而是：

- 保留 Xray 监听公网 `443`，现有代理客户端不受影响；
- 将普通浏览器的 ALPN `h2` 流量回落到 Nginx `127.0.0.1:8444`；
- 将 `http/1.1` 和默认流量回落到 Nginx `127.0.0.1:8443`；
- 让公网 `80` 继续由 Nginx 监听并跳转到 HTTPS；
- 修改前备份 `/etc/nginx/sites-available/hays0709.conf` 和 x-ui 数据库，验证失败时自动回滚。

默认数据库路径是 `/etc/x-ui/x-ui.db`。如安装位置不同，或内部端口已占用，可显式指定：

```bash
sudo bash scripts/configure-xray-fallback.sh \
  --domain example.com \
  --x-ui-db /etc/x-ui/x-ui.db \
  --http1-port 8443 \
  --http2-port 8444
```

配置成功后，后续更新网页只需运行普通部署命令，不要再附加 `--https`：

```bash
sudo bash scripts/deploy.sh --domain wuininyyy2026.xyz --branch main
```

### 更新、指定版本和回滚

从仓库目录再次执行即可更新：

```bash
sudo bash scripts/deploy.sh --domain example.com --branch main
```

也可以指定其他分支/标签或镜像仓库：

```bash
sudo bash scripts/deploy.sh \
  --domain example.com \
  --branch release \
  --repo-url https://github.com/your-org/your-mirror.git
```

脚本默认保留当前版本、上一版本和另外三个 release。若新版本有问题，切回上一版本：

```bash
sudo bash scripts/deploy.sh --domain example.com --rollback
```

首次部署没有 `previous` 版本，回滚会明确报错，不会删除当前版本。

### 查看服务状态和日志

```bash
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo systemctl status hays0709 --no-pager
sudo systemctl is-active nginx
sudo systemctl is-active hays0709
sudo journalctl -u nginx -e --no-pager
sudo journalctl -u hays0709 -e --no-pager
curl -i -X OPTIONS http://127.0.0.1:5173/api/fortune
ls -la /opt/hays0709
ls -la /opt/hays0709/releases
```

正常情况下 `/opt/hays0709/current` 指向当前 release，`/opt/hays0709/previous` 指向上一 release。Nginx 配置会保留在 `/etc/nginx/sites-available/hays0709.conf`，后续部署不会覆盖 Certbot 添加的 HTTPS 配置。

### 常见问题

- **域名访问到默认 Nginx 页面**：确认 DNS 已指向该服务器，并检查 `sudo nginx -t`、站点配置中的 `server_name` 和 80 端口安全组。
- **HTTPS 申请失败**：确认域名已解析到本机、80/443 没有被其他服务占用，且 Certbot 能从公网完成验证。
- **提示 `Port 443 is occupied`**：使用 `sudo ss -ltnp | grep ':443'` 确认占用者。如果是 x-ui/Xray，请按上面的共存步骤运行 `scripts/configure-xray-fallback.sh`，不要停止仍有代理客户端使用的 Xray。
- **提示 `server_name` 不一致**：脚本不会覆盖同名但非本项目管理的配置。请先检查 `/etc/nginx/sites-available/hays0709.conf`，确认域名后再运行。
- **更新失败**：脚本在健康检查失败时会恢复原来的 `current`。检查 Nginx 日志和 `/opt/hays0709/releases` 后，可再次执行 `--rollback`。
- **页面正常但 AI 一直使用兜底内容**：检查 `/etc/hays0709.env` 中的 `HAYS_AI_API_KEY`，再运行 `sudo systemctl restart hays0709` 和 `sudo journalctl -u hays0709 -e --no-pager`。
- **`/api/fortune` 返回 502**：先确认 `sudo systemctl is-active hays0709`，再用 `curl -i -X OPTIONS http://127.0.0.1:5173/api/fortune` 检查本机 Node 服务。

## 本地检查

仓库中的页面断言测试可以直接运行：

```bash
node tests/ai-fortune-api.test.mjs
node tests/homepage-launch-cabin.test.mjs
node tests/homepage-structure.test.mjs
node tests/activity-flow-design.test.mjs
node tests/deployment-files.test.mjs
```
