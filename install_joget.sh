set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

DOWNLOAD_URL="https://drive.usercontent.google.com/download?id=1sXTRXAXz-i4_szr3fXiJwjAEp0sNfoFr&export=download&confirm=t&uuid=881e9b97-7277-4c3e-8ba6-6df3886f9106"
INSTALL_DIR="/opt/joget"
CJ_VER="8.4.0"

DB_HOST=""
DB_NAME=""
DB_USER=""
DB_PASS="${DB_PASS:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-host) DB_HOST="$2"; shift 2;;
    --db-name) DB_NAME="$2"; shift 2;;
    --db-user) DB_USER="$2"; shift 2;;
    --db-pass) DB_PASS="$2"; shift 2;;
    --download-url) DOWNLOAD_URL="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 --db-host <endpoint> --db-name <name> --db-user <user> [--db-pass <pass>] [--download-url <url>]"; exit 0;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$DB_HOST" || -z "$DB_NAME" || -z "$DB_USER" ]]; then
  echo "ERROR: --db-host, --db-name, and --db-user are required."
  exit 1
fi

if [[ -z "$DB_PASS" ]]; then
  read -r -s -p "Enter DB password for user '$DB_USER': " DB_PASS
  echo
fi

echo "==> Installing prerequisites (Java 11, tools, MySQL client) ..."
yum update -y
amazon-linux-extras install -y java-openjdk11 || yum install -y java-11-amazon-corretto-headless
yum install -y curl tar gzip unzip mariadb

echo "==> Creating install dir at $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "==> Checking connectivity to MySQL (${DB_HOST}) ..."
for i in {1..60}; do
  if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "select 1" >/dev/null 2>&1; then
    echo "    MySQL is reachable."; break
  fi
  echo "    Waiting for DB ... ($i/60)"; sleep 10
done

echo "==> Ensuring database '$DB_NAME' exists ..."
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

echo "==> Downloading Joget bundle ..."
curl -L -o joget.tar.gz "$DOWNLOAD_URL"

echo "==> Validating archive is a gzip'ed tar ..."
if ! tar -tzf joget.tar.gz >/dev/null 2>&1; then
  echo "ERROR: joget.tar.gz is not a valid tar.gz (got HTML or corrupted file)."
  exit 1
fi

echo "==> Extracting Joget ..."
tar -xzf joget.tar.gz

if ls "$INSTALL_DIR" | grep -q "apache-tomcat-"; then
  TDIR=$(ls -d "$INSTALL_DIR"/apache-tomcat-* | head -n1)
  ln -sfn "$TDIR" "$INSTALL_DIR/apache-tomcat"
fi

echo "==> Installing MySQL Connector/J ($CJ_VER) ..."
curl -L -o /tmp/mysqlcj.tgz "https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-${CJ_VER}.tar.gz"
mkdir -p /tmp/cj && tar -xzf /tmp/mysqlcj.tgz -C /tmp/cj
CJAR=$(find /tmp/cj -name "mysql-connector-j-*.jar" | head -n1)
if [[ -z "$CJAR" || ! -f "$CJAR" ]]; then
  echo "ERROR: Could not locate mysql-connector-j JAR in the downloaded package."
  exit 1
fi
cp "$CJAR" "$INSTALL_DIR/apache-tomcat/lib/mysql-connector-j.jar"

echo "==> Writing datasource to $INSTALL_DIR/wflow.properties ..."
cat > "$INSTALL_DIR/wflow.properties" <<EOP
workflowDriver=com.mysql.cj.jdbc.Driver
workflowUrl=jdbc:mysql://$DB_HOST:3306/$DB_NAME?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
workflowUser=$DB_USER
workflowPassword=$DB_PASS
currentProfile=default
setup=true
EOP

echo "==> Installing systemd service: /etc/systemd/system/joget.service ..."
cat > /etc/systemd/system/joget.service <<EOS
[Unit]
Description=Joget (Tomcat) service
After=network.target

[Service]
Type=forking
Environment=JAVA_HOME=/usr/lib/jvm/jre-11
Environment=CATALINA_BASE=$INSTALL_DIR/apache-tomcat
Environment=CATALINA_HOME=$INSTALL_DIR/apache-tomcat
Environment=CATALINA_PID=$INSTALL_DIR/apache-tomcat/temp/tomcat.pid
ExecStart=$INSTALL_DIR/apache-tomcat/bin/startup.sh
ExecStop=$INSTALL_DIR/apache-tomcat/bin/shutdown.sh
User=root
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOS

echo "==> Enabling and starting Joget ..."
systemctl daemon-reload
systemctl enable joget
systemctl start joget

echo "==> Verifying service and port 8080 ..."
sleep 2
systemctl --no-pager --full status joget || true
ss -lntp | grep ':8080' || true

echo "==> Testing http://127.0.0.1:8080/jw ..."
curl -I --max-time 5 http://127.0.0.1:8080/jw || true

echo "==> Done. If your ALB Target Group is set to port 8080 with health check /jw/ (matcher 200–399), targets should go healthy shortly."
