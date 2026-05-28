# Gitea Service

Server 101 runs Gitea natively as a systemd service, not as a container.

Web UI:

```text
http://<SERVER_IP>:3000/
```

Default admin account:

```text
autoadmin / <CHANGE_ME_PASSWORD>
```

Layout:

```text
/usr/local/bin/gitea
/etc/gitea/app.ini
/var/lib/gitea
/var/lib/gitea/data/gitea.db
```

The service runs as the `git` system user and uses SQLite to avoid a separate
database service at the offline site.
