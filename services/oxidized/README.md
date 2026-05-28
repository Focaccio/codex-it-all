# Oxidized Service

Oxidized backs up network device configurations over SSH/Telnet and stores
history in a local Git repository.

Web/API:

```text
http://<SERVER_IP>:8888/
```

Device inventory:

```text
/opt/server101/services/oxidized/config/router.db
```

CSV format:

```text
hostname-or-ip:model:username:password:input:ssh-kex:ssh-host-key:ssh-encryption:ssh-hmac
```

Common model values include `ios`, `nxos`, `eos`, `junos`, `procurve`,
`fortios`, `panos`, `routeros`, and `edgeos`.
The `input` field can be `ssh`, `telnet`, or `ssh,telnet`.
The optional SSH algorithm fields are useful for older devices that require
legacy SSH settings such as `diffie-hellman-group1-sha1`, `ssh-rsa`, or
`aes128-cbc`.
