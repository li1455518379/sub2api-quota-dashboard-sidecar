# sub2api-quota-dashboard-sidecar

为 `sub2api` 提供一个独立的账号额度统计页，使用 Docker sidecar 部署，不修改主服务代码。

提供账号总览、账号矩阵、周额度/5h 额度、恢复分组、历史快照，以及手动和定时刷新能力。

当前版本额外支持：

- 深色模式背景正确跟随主站主题
- 同源反向代理嵌入，菜单页可免 `secret`
- 支持 `x-api-key` / `x-admin-api` / Bearer Token 访问
- 定时刷新优先使用 Admin API Key，不必长期保存管理员密码

## 使用

### 1. 复制环境变量文件

```bash
cp .env.example .env
```

### 2. 修改 `.env`

至少填写：

- `POSTGRES_HOST`
- `POSTGRES_PORT`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_DB`
- `QUOTA_DASHBOARD_SUB2API_BASE_URL`
- `QUOTA_DASHBOARD_TOKEN`
- `QUOTA_DASHBOARD_PORT`

二选一填写后台刷新凭据：

- 推荐：`QUOTA_DASHBOARD_ADMIN_API_KEY`
- 兼容回退：`QUOTA_DASHBOARD_ADMIN_EMAIL` + `QUOTA_DASHBOARD_ADMIN_PASSWORD`

示例：

```env
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=sub2api
POSTGRES_PASSWORD=your-postgres-password
POSTGRES_DB=sub2api
QUOTA_DASHBOARD_SUB2API_BASE_URL=http://sub2api:8080
QUOTA_DASHBOARD_TOKEN=your-random-secret
QUOTA_DASHBOARD_PORT=18081
QUOTA_DASHBOARD_ADMIN_API_KEY=your-admin-api-key
```

如果你暂时没有 Admin API Key，也可以回退为：

```env
QUOTA_DASHBOARD_ADMIN_EMAIL=admin@example.com
QUOTA_DASHBOARD_ADMIN_PASSWORD=your-admin-password
```

### 3. 检查环境

```bash
./check.sh
```

### 4. 部署

```bash
./deploy.sh
```

## 访问

直接访问：

```text
http://你的主机:18081/?secret=你的QUOTA_DASHBOARD_TOKEN
```

如果设置了 `QUOTA_DASHBOARD_PUBLIC_URL`，服务启动时会自动写入 `sub2api` 左侧菜单。

推荐的同源嵌入方式：

1. 把主站 `/` 反向代理到 `sub2api`
2. 把 `/quota-dashboard/` 反向代理到 sidecar
3. 设置：

```env
QUOTA_DASHBOARD_PUBLIC_URL=http://你的主机:18080/quota-dashboard/?ui_mode=embedded
```

这样菜单页会直接复用主站登录态，不再需要在 URL 里暴露 `secret`。

## 常见问题

- 菜单提示“该自定义页面的 URL 未正确配置”：通常是 `QUOTA_DASHBOARD_PUBLIC_URL` 没有设置成浏览器可访问的完整地址，或者 `/quota-dashboard/` 的反向代理路径还没打通。
- 端口说明：`18081` 是 sidecar 直连示例端口，`18080` 是主站或反向代理的示例端口。两者用途不同，不需要保持一致。

## 社区链接

<p align="left">
  <a href="https://linux.do" alt="LINUX DO">
    <img src="https://shorturl.at/ggSqS" />
  </a>
</p>
