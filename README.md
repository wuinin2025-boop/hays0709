# 瀚纳仕 AI 打工命盘 H5

这是一个纯静态 H5 项目，生产入口为 `瀚纳仕H5 demo-启动舱.html`，运行时依赖只有两个 HTML 页面和 `assets/` 图片资源。不需要 Node.js、数据库或后端服务。

## Ubuntu + Nginx 部署

仓库提供 `scripts/deploy.sh`，适用于 Ubuntu 22.04 及更新版本。脚本会从 GitHub 拉取指定分支/标签，使用时间戳 release 目录发布到 `/opt/hays0709`，再原子切换 `current` 软链接。Nginx 始终指向这个稳定软链接，因此更新过程中不会暴露半套文件。

### 部署前准备

服务器需要满足：

- Ubuntu 22.04+、`sudo`、`systemd`、`apt` 和出站网络；
- 域名的 A/AAAA 记录已经指向服务器；
- 防火墙或云安全组放行 TCP `80` 和 `443`；
- 如果仓库是私有仓库，服务器已经配置 GitHub Deploy Key 或其他 Git 凭据。不要把凭据写进脚本或仓库。

脚本首次运行会自动安装 `git`、`nginx`、`rsync` 和 `curl`。执行 HTTPS 部署时，还会安装 `certbot` 和 `python3-certbot-nginx`。

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
sudo systemctl is-active nginx
sudo journalctl -u nginx -e --no-pager
ls -la /opt/hays0709
ls -la /opt/hays0709/releases
```

正常情况下 `/opt/hays0709/current` 指向当前 release，`/opt/hays0709/previous` 指向上一 release。Nginx 配置会保留在 `/etc/nginx/sites-available/hays0709.conf`，后续部署不会覆盖 Certbot 添加的 HTTPS 配置。

### 常见问题

- **域名访问到默认 Nginx 页面**：确认 DNS 已指向该服务器，并检查 `sudo nginx -t`、站点配置中的 `server_name` 和 80 端口安全组。
- **HTTPS 申请失败**：确认域名已解析到本机、80/443 没有被其他服务占用，且 Certbot 能从公网完成验证。
- **提示 `server_name` 不一致**：脚本不会覆盖同名但非本项目管理的配置。请先检查 `/etc/nginx/sites-available/hays0709.conf`，确认域名后再运行。
- **更新失败**：脚本在健康检查失败时会恢复原来的 `current`。检查 Nginx 日志和 `/opt/hays0709/releases` 后，可再次执行 `--rollback`。

## 本地检查

仓库中的页面断言测试可以直接运行：

```bash
node tests/homepage-launch-cabin.test.mjs
node tests/homepage-structure.test.mjs
node tests/activity-flow-design.test.mjs
node tests/deployment-files.test.mjs
```
