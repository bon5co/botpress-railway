# Botpress on Railway: thin wrapper over the official Botpress server image (the 12.x line).
# What it adds: a boot-time administrator from one generated password (stock Botpress hands the
# instance to whoever opens the URL first), the Railway-injected PORT, the public URL taken from the
# Railway domain, the Postgres URL assembled from the postgres service, bots and config stored in
# that database, a fixed application secret so sessions survive redeploys, and a data directory
# the botpress user can write on a root-owned volume.
# upstream: botpress/v12
FROM botpress/server:12.31.10@sha256:36831b32cb603a1b8fe8dad999f615595a4c159dc0a151e3a3d46197416178bd

USER root

ENV BP_PRODUCTION=true \
    BPFS_STORAGE=database \
    BOTPRESS_ADMIN_EMAIL=admin@example.com

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
