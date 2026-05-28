#!/bin/bash
set -e

CERT_DIR="/opt/observium/certificates"
CERT_FILE="$CERT_DIR/fullchain.pem"
KEY_FILE="$CERT_DIR/privkey.pem"

if [ ! -d "$CERT_DIR" ]; then
  echo "Directory $CERT_DIR does not exist. Creating it..."
  mkdir -p "$CERT_DIR"
fi

if [ "$(ls -A "$CERT_DIR")" ]; then
  echo "Directory $CERT_DIR is not empty. No certificate will be generated."
else
  echo "Directory $CERT_DIR is empty. Generating self-signed certificate..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/C=US/ST=CA/L=Server101/O=Server101/OU=IT/CN=s101.top.demosdnx.net"
fi

atd

if [ -f /config/config.php ]; then
  echo "Using existing PHP database config file."
else
  echo "Loading PHP config from default."
  mkdir -p /config/databases
  cp /opt/observium/config.php.default /config/config.php
  chown nobody:users /config/config.php
  sed -i -e "s/PASSWORD/${OBSERVIUM_DB_PASSWORD:?OBSERVIUM_DB_PASSWORD is required}/g" /config/config.php
  sed -i -e 's/USERNAME/observium/g' /config/config.php
fi

sed -i -e "s/\$config\['db_host'\].*/\$config['db_host']      = 'observium-db';/" /config/config.php

grep -qF 'enable_syslog' /config/config.php || echo "\$config['enable_syslog'] = 1;" >> /config/config.php

grep -qF 'Dynamic base_url detection' /config/config.php || cat <<'CONFIGEOF' >> /config/config.php

// --- Dynamic base_url detection ---
if (isset($_SERVER['HTTP_HOST'])) {
    if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https') {
        $_SERVER['HTTPS'] = 'on';
    }
    $protocol = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] == 'on') ? 'https' : 'http';
    $host = $_SERVER['HTTP_HOST'];
    $prefix = isset($_SERVER['HTTP_X_FORWARDED_PREFIX']) ? rtrim($_SERVER['HTTP_X_FORWARDED_PREFIX'], '/') : '';
    $script_path = rtrim(dirname($_SERVER['SCRIPT_NAME']), '/\\');
    $config['base_url'] = $protocol . "://" . $host . $prefix . $script_path . "/";
}
// ----------------------------------
CONFIGEOF

ln -sfn /config/config.php /opt/observium/config.php
chown nobody:users -R /config /opt/observium/logs /opt/observium/rrd /opt/observium/certificates
chown -h nobody:users /opt/observium/config.php
chmod 755 -R /config /opt/observium/logs /opt/observium/rrd /opt/observium/certificates
chmod 755 /config/config.php

if [ -f /etc/container_environment/TZ ] ; then
  sed -i "s#\;date\.timezone\ \=#date\.timezone\ \=\ $TZ#g" /etc/php/8.3/cli/php.ini
  sed -i "s#\;date\.timezone\ \=#date\.timezone\ \=\ $TZ#g" /etc/php/8.3/apache2/php.ini
else
  echo "Timezone not specified by environment variable"
  echo UTC > /etc/container_environment/TZ
  sed -i "s#\;date\.timezone\ \=#date\.timezone\ \=\ UTC#g" /etc/php/8.3/cli/php.ini
  sed -i "s#\;date\.timezone\ \=#date\.timezone\ \=\ UTC#g" /etc/php/8.3/apache2/php.ini
fi

rm -f /etc/localtime
ln -s /usr/share/zoneinfo/$(cat /etc/container_environment/TZ) /etc/localtime
