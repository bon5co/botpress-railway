# botpress-railway

Thin wrapper over the official [Botpress v12 server image](https://hub.docker.com/r/botpress/server) for
[Railway](https://railway.com), used by the Botpress Railway template.

What it adds on top of `botpress/server`:

- an administrator created at first boot from `BOTPRESS_ADMIN_EMAIL` / `BOTPRESS_ADMIN_PASSWORD` (stock Botpress
  hands the instance to whoever registers first)
- the Railway-injected `PORT`, with the bundled duckling pinned to 8000 so it cannot take that port
- the public URL from `RAILWAY_PUBLIC_DOMAIN`, the Postgres URL built from the Postgres service
- bots and configuration stored in Postgres (`BPFS_STORAGE=database`)
- a fixed application secret (`BOTPRESS_APP_SECRET`) so tokens survive redeploys
- a chown of `/botpress/data` for the root-owned Railway volume

Images: `ghcr.io/bon5co/botpress-railway:12.31.10` and `:latest`. Botpress v12 is AGPL-3.0.
