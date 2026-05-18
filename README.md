# sub2api-quota-dashboard-sidecar

为 `sub2api` 提供一个独立的账号额度统计页，使用 Docker sidecar 部署，不修改主服务代码。

提供账号总览、账号矩阵、周额度/5h 额度、恢复分组、历史快照，以及手动和定时刷新能力。

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
- `QUOTA_DASHBOARD_ADMIN_EMAIL`
- `QUOTA_DASHBOARD_ADMIN_PASSWORD`
- `QUOTA_DASHBOARD_TOKEN`
- `QUOTA_DASHBOARD_PORT`

示例：

```env
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=sub2api
POSTGRES_PASSWORD=your-postgres-password
POSTGRES_DB=sub2api
QUOTA_DASHBOARD_SUB2API_BASE_URL=http://sub2api:8080
QUOTA_DASHBOARD_ADMIN_EMAIL=admin@example.com
QUOTA_DASHBOARD_ADMIN_PASSWORD=your-admin-password
QUOTA_DASHBOARD_TOKEN=your-random-secret
QUOTA_DASHBOARD_PORT=18081
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
http://你的主机:你的端口/?secret=你的QUOTA_DASHBOARD_TOKEN
```

如果设置了 `QUOTA_DASHBOARD_PUBLIC_URL`，服务启动时会自动写入 `sub2api` 左侧菜单。

## 社区链接

<p align="left">
  <a href="https://linux.do" alt="LINUX DO">
    <img src="https://shorturl.at/ggSqS" />
  </a>
</p>
