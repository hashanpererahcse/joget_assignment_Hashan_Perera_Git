user_data = <<-EOF
#!/usr/bin/env bash
set -euxo pipefail

# ---- simple colors off for cloud-init logs ----
INSTALL_DIR="/opt/joget"
JOGET_USER="joget"
JOGET_URL="${var.joget_url}"
CONFIG_FILE="/etc/joget.conf"

# Generate a strong password
generate_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9@#%^&*_+-=' </dev/urandom | head -c 24
}

prepare_system() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # openjdk, mysql, curl, tar
  apt-get install -y -qq openjdk-11-jre-headless mysql-server curl tar
}

configure_mysql() {
  # Some Ubuntu images auto-initialize on install; handle both paths
  systemctl enable mysql
  systemctl start mysql || true
  sleep 5

  # If not initialized, do an insecure init (no password) then start
  if [ ! -d "/var/lib/mysql/mysql" ] || ! mysqladmin ping --silent; then
    mysqld --initialize-insecure --user=mysql || true
    chown -R mysql:mysql /var/lib/mysql || true
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld && chmod 755 /var/run/mysqld
    systemctl restart mysql
    sleep 5
  fi

  # Set root password (works on both auth setups)
  mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;" \
    || mysql -uroot -e "UPDATE mysql.user SET plugin='mysql_native_password', authentication_string=PASSWORD('${MYSQL_ROOT_PASSWORD}') WHERE User='root' AND Host='localhost'; FLUSH PRIVILEGES;"

  # Create app DB
  mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS jogetdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

install_joget() {
  # Create service user and dirs
  if ! id "${JOGET_USER}" &>/dev/null; then
    useradd -r -m -d "${INSTALL_DIR}" "${JOGET_USER}"
  fi
  mkdir -p "${INSTALL_DIR}"
  chown "${JOGET_USER}:${JOGET_USER}" "${INSTALL_DIR}"

  # Fetch and unpack Joget bundle (includes its own Tomcat)
  su -s /bin/bash - "${JOGET_USER}" <<'EOSU'
set -euxo pipefail
cd "${INSTALL_DIR}"
[ -f joget.tar.gz ] || curl -L "${JOGET_URL}" -o joget.tar.gz
tar xzf joget.tar.gz
cd joget-linux-*
chmod +x *.sh
EOSU

  JOGET_HOME="$(ls -d "${INSTALL_DIR}"/joget-linux-*)"

  # systemd service for bundled Tomcat
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

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable joget
}

secure_joget_admin() {
  systemctl start joget
  # give Tomcat a moment to come up
  for i in {1..30}; do
    if curl -fsS "http://localhost:8080/jw" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  # Change default admin password (best-effort)
  curl -s -X POST "http://localhost:8080/jw/web/json/admin/setup/changeAdminPassword" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "currentPassword=password&newPassword=${JOGET_ADMIN_PASSWORD}" || true
}

write_access_info() {
  local ip
  ip="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || hostname -I | awk '{print $1}')"

  cat >/etc/motd <<INFO

================ Joget Installed ================
URL: http://${ip}:8080/jw
Admin username: admin
Admin password: ${JOGET_ADMIN_PASSWORD}

MySQL root password: ${MYSQL_ROOT_PASSWORD}
================================================
INFO
}

main() {
  # config file for idempotency
  if [ -f "${CONFIG_FILE}" ]; then
    . "${CONFIG_FILE}"
  else
    MYSQL_ROOT_PASSWORD="$(generate_password)"
    JOGET_ADMIN_PASSWORD="$(generate_password)"
    cat >"${CONFIG_FILE}" <<CONFIG
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"
JOGET_ADMIN_PASSWORD="${JOGET_ADMIN_PASSWORD}"
INSTALL_DIR="${INSTALL_DIR}"
CONFIG
    chmod 600 "${CONFIG_FILE}"
  fi

  prepare_system
  configure_mysql
  install_joget
  secure_joget_admin
  rm -f "${INSTALL_DIR}/joget.tar.gz" || true
  write_access_info
}

main "$@"
EOF
