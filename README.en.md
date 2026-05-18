# sub2api-quota-dashboard-sidecar

Standalone quota dashboard sidecar for `sub2api`.

It adds an account quota dashboard without modifying the main `sub2api` service.

It provides account overview, account matrix, weekly/5h quota stats, recovery grouping, history snapshots, and both manual and scheduled refresh.

This version also adds:

- Proper dark-mode background sync
- Same-origin reverse-proxy embedding without exposing `secret`
- `x-api-key` / `x-admin-api` / Bearer token access
- Background refresh that prefers an Admin API Key over admin password login

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
- `QUOTA_DASHBOARD_TOKEN`
- `QUOTA_DASHBOARD_PORT`

Choose one refresh credential mode:

- Recommended: `QUOTA_DASHBOARD_ADMIN_API_KEY`
- Fallback: `QUOTA_DASHBOARD_ADMIN_EMAIL` + `QUOTA_DASHBOARD_ADMIN_PASSWORD`

Example:

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

If you do not have an Admin API Key yet, you can fall back to:

```env
QUOTA_DASHBOARD_ADMIN_EMAIL=admin@example.com
QUOTA_DASHBOARD_ADMIN_PASSWORD=your-admin-password
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

Direct access:

```text
http://your-host:18081/?secret=your-QUOTA_DASHBOARD_TOKEN
```

If `QUOTA_DASHBOARD_PUBLIC_URL` is set, the service will also sync a custom sidebar menu entry into `sub2api`.

Recommended same-origin embedding:

1. Reverse-proxy `/` to `sub2api`
2. Reverse-proxy `/quota-dashboard/` to this sidecar
3. Set:

```env
QUOTA_DASHBOARD_PUBLIC_URL=http://your-host:18080/quota-dashboard/?ui_mode=embedded
```

That lets the custom page reuse the main site login state without exposing `secret` in the URL.

## Troubleshooting

- If the menu says the custom page URL is not configured correctly, `QUOTA_DASHBOARD_PUBLIC_URL` is usually not a browser-reachable URL yet, or the `/quota-dashboard/` reverse-proxy path is missing.
- Port note: `18081` is the direct sidecar example port, while `18080` is the example main-site or reverse-proxy port. They serve different roles.

## Community Link

<p align="left">
  <a href="https://linux.do" alt="LINUX DO">
    <img src="https://shorturl.at/ggSqS" />
  </a>
</p>
