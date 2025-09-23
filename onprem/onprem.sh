#!/usr/bin/env bash
set -euxo pipefail

INSTALL_DIR="/opt/joget"
JOGET_USER="joget"
JOGET_URL="https://drive.usercontent.google.com/download?id=1sXTRXAXz-i4_szr3fXiJwjAEp0sNfoFr&export=download&confirm=t&uuid=881e9b97-7277-4c3e-8ba6-6df3886f9106"
CONFIG_FILE="/etc/joget.conf"
CREDS_FILE="/root/JOGET_CREDENTIALS.txt"

generate_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9@#%^&*_+=-' </dev/urandom | head -c 24 || true
}

prepare_system() {
  export DEBIAN_FRONTEND=noninteractive
  apt update -qq
  apt install -y -qq openjdk-11-jre-headless mysql-server curl tar
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow 8080/tcp || true
  fi
}

configure_mysql() {
  systemctl enable mysql
  systemctl start mysql || true
  sleep 5

  if [ ! -d "/var/lib/mysql/mysql" ] || ! mysqladmin ping --silent; then
    mysqld --initialize-insecure --user=mysql || true
    chown -R mysql:mysql /var/lib/mysql || true
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld && chmod 755 /var/run/mysqld
    systemctl restart mysql
    sleep 5
  fi

  mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;" \
    || mysql -uroot -e "UPDATE mysql.user SET plugin='mysql_native_password', authentication_string=PASSWORD('${MYSQL_ROOT_PASSWORD}') WHERE User='root' AND Host='localhost'; FLUSH PRIVILEGES;"

  mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS jogetdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

  # Create app user (least-privilege) and grant
  mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${MYSQL_APP_USER}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_APP_PASSWORD}';"
  mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON jogetdb.* TO '${MYSQL_APP_USER}'@'localhost'; FLUSH PRIVILEGES;"
}

install_joget() {
  # Create service user and dirs
  if ! id "${JOGET_USER}" &>/dev/null; then
    useradd -r -m -d "${INSTALL_DIR}" "${JOGET_USER}"
  fi
  mkdir -p "${INSTALL_DIR}"
  chown -R "${JOGET_USER}:${JOGET_USER}" "${INSTALL_DIR}"

  # Fetch and unpack Joget 
  su -s /bin/bash - "${JOGET_USER}" -c '
    set -euxo pipefail
    cd "'"${INSTALL_DIR}"'"
    [ -f joget.tar.gz ] || curl -L "'"${JOGET_URL}"'" -o joget.tar.gz
    tar xzf joget.tar.gz
    cd joget-linux-*
    chmod +x *.sh
  '

  JOGET_HOME="$(ls -d "${INSTALL_DIR}"/joget-linux-* | head -n 1)"

  # systemd service for Tomcat
  cat >/etc/systemd/system/joget.service <<SERVICE
[Unit]
Description=Joget Workflow
After=network.target mysql.service

[Service]
Type=forking
User=${JOGET_USER}
WorkingDirectory=${JOGET_HOME}
Environment="MYSQL_PWD=${MYSQL_ROOT_PASSWORD}"
ExecStart=${JOGET_HOME}/tomcat.sh start
ExecStop=${JOGET_HOME}/tomcat.sh stop
Restart=on-failure
RestartSec=30
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable joget
}

secure_joget_admin() {
  systemctl start joget
  # Wait for the web app to come up
  for i in {1..60}; do
    if curl -fsS "http://localhost:8080/jw" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  curl -s -X POST "http://localhost:8080/jw/web/json/admin/setup/changeAdminPassword" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "currentPassword=password&newPassword=${JOGET_ADMIN_PASSWORD}" || true
}

write_access_info() {
  local ip
  ip="$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
  if [ -z "${ip}" ]; then
    ip="$(hostname -I | awk '{print $1}')"
  fi

  # Minimal MOTD with no secrets
  cat >/etc/motd <<INFO

================ Joget Installed ================
URL: http://${ip}:8080/jw
Credentials saved to: ${CREDS_FILE}
================================================
INFO

  # Store credentials securely (root-only)
  umask 077
  cat >"${CREDS_FILE}" <<CREDS
# Joget installation credentials
URL: http://${ip}:8080/jw
Admin username: admin
Admin password: ${JOGET_ADMIN_PASSWORD}

MySQL root user: root
MySQL root password: ${MYSQL_ROOT_PASSWORD}

MySQL app user: ${MYSQL_APP_USER}
MySQL app password: ${MYSQL_APP_PASSWORD}
Database: jogetdb
CREDS
  chmod 600 "${CREDS_FILE}"
}

main() {
  if [ -f "${CONFIG_FILE}" ]; then
    . "${CONFIG_FILE}"
  else
    MYSQL_ROOT_PASSWORD="$(generate_password)"
    JOGET_ADMIN_PASSWORD="$(generate_password)"
    MYSQL_APP_USER="jogetapp"
    MYSQL_APP_PASSWORD="$(generate_password)"
    cat >"${CONFIG_FILE}" <<CONFIG
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"
JOGET_ADMIN_PASSWORD="${JOGET_ADMIN_PASSWORD}"
MYSQL_APP_USER="${MYSQL_APP_USER}"
MYSQL_APP_PASSWORD="${MYSQL_APP_PASSWORD}"
INSTALL_DIR="${INSTALL_DIR}"
CONFIG
    chmod 600 "${CONFIG_FILE}"
  fi

  prepare_system
  configure_mysql
  install_joget
  secure_joget_admin

  # Clean up the archive to save space (keep install intact)
  rm -f "${INSTALL_DIR}/joget.tar.gz" || true

  write_access_info
}

main "$@"