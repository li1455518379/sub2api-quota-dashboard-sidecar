# sub2api-quota-dashboard-sidecar

Standalone quota dashboard sidecar for `sub2api`.

It adds an account quota dashboard without modifying the main `sub2api` service.

It provides account overview, account matrix, weekly/5h quota stats, recovery grouping, history snapshots, and both manual and scheduled refresh.

## Usage

### 1. Copy the env file

```bash
cp .env.example .env
```

### 2. Edit `.env`

Set at least:

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

Example:

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

### 3. Check the environment

```bash
./check.sh
```

### 4. Deploy

```bash
./deploy.sh
```

## Access

Open:

```text
http://your-host:your-port/?secret=your-QUOTA_DASHBOARD_TOKEN
```

If `QUOTA_DASHBOARD_PUBLIC_URL` is set, the service will also sync a custom sidebar menu entry into `sub2api`.

## Community Link

<p align="left">
  <a href="https://linux.do" alt="LINUX DO">
    <img src="https://shorturl.at/ggSqS" />
  </a>
</p>
