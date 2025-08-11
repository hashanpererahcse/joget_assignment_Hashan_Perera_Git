#!/bin/bash
set -e

JOGET_URL="https://drive.usercontent.google.com/download?id=1sXTRXAXz-i4_szr3fXiJwjAEp0sNfoFr&export=download&confirm=t"
INSTALL_DIR="/opt/joget"
MYSQL_ROOT_PASSWORD="JogetSecure123!"
JOGET_USER="joget"

sudo mkdir -p /var/run/mysqld
sudo chown mysql:mysql /var/run/mysqld
sudo chmod 755 /var/run/mysqld


sudo apt-get update
sudo apt-get install -y openjdk-11-jre-headless mysql-server curl tar

sudo systemctl stop mysql 2>/dev/null || true
sudo rm -f /var/lib/mysql/auto.cnf 2>/dev/null || true

# init if data directory is empty
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MySQL data directory..."
    sudo mysqld --initialize-insecure --user=mysql
fi

sudo mysqld_safe --skip-grant-tables --skip-networking &
MYSQL_PID=$!
sleep 5

#Reset root password
mysql -uroot <<MYSQL_RESET
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
MYSQL_RESET

sudo kill $MYSQL_PID
wait $MYSQL_PID
sudo systemctl start mysql

#Verify MySQL access
if ! mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" 2>/dev/null; then
    echo -e "\n\033[1;31mFATAL: MySQL setup failed after multiple attempts\033[0m"
    echo "Please check MySQL logs: sudo tail -n 50 /var/log/mysql/error.log"
    exit 1
fi


sudo mkdir -p "$INSTALL_DIR"
if ! id -u "$JOGET_USER" >/dev/null 2>&1; then
    sudo useradd -r -m -d "$INSTALL_DIR" "$JOGET_USER"
fi
sudo chown -R "$JOGET_USER:$JOGET_USER" "$INSTALL_DIR"

sudo -u "$JOGET_USER" bash <<EOF
cd "$INSTALL_DIR"
[ -f joget.tar.gz ] || curl -L "$JOGET_URL" -o joget.tar.gz
tar xvfz joget.tar.gz
cd joget-linux-*
chmod +x *.sh
EOF

#Create Systemd Service
JOGET_HOME=$(ls -d "$INSTALL_DIR"/joget-linux-*)
sudo tee /etc/systemd/system/joget.service > /dev/null <<EOF
[Unit]
Description=Joget Workflow
After=network.target mysql.service

[Service]
Type=forking
User=$JOGET_USER
WorkingDirectory=$JOGET_HOME
ExecStart=$JOGET_HOME/tomcat.sh start
ExecStop=$JOGET_HOME/tomcat.sh stop
Restart=on-failure
RestartSec=30
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable joget
sudo systemctl start joget

# Verify Installation
sleep 5
if ! systemctl is-active --quiet joget; then
    echo -e "\n\033[1;33mWARNING: Joget service didn't start automatically\033[0m"
    echo "Trying manual start..."
    sudo -u "$JOGET_USER" "$JOGET_HOME/tomcat.sh" run
else
    echo -e "\n\033[1;32mINSTALLATION SUCCESSFUL!\033[0m"
    echo "Access Joget at: http://$(hostname -I | awk '{print $1}'):8080/jw"
    echo "MySQL root password: ${MYSQL_ROOT_PASSWORD}"
    echo -e "\nView logs with:"
    echo "  sudo journalctl -u joget -f"
    echo "  or"
    echo "  sudo tail -f $JOGET_HOME/apache-tomcat-*/logs/catalina.out"
fi