# Docker Images For Offline Site 2

Place exported Docker image tarballs here when a service must be available at
the offline installation site.

On an internet-connected Server 101/build machine:

```bash
docker pull IMAGE:TAG
docker save -o artifacts/docker-images/name-tag.tar IMAGE:TAG
```

At the offline site after install:

```bash
docker load -i /path/to/name-tag.tar
```

Docker Engine is included in the ISO package profile, but container images are
not automatically present unless they are exported and carried along too.

Current Server 101 image bundle:

- `uberchuckie-observium-12.0.0.tar.gz`
- `mariadb-11.4.tar.gz`
- `oxidized-latest.tar.gz` once Oxidized is pulled and exported
