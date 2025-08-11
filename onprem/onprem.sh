#!/bin/bash
set -e

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "\n${CYAN}JOGET INSTALLER${NC}"
echo -e "Optimized for Ubuntu 22.04/24.04 LTS"
echo -e "${YELLOW}Internet connection required${NC}\n"

INSTALL_DIR="/opt/joget"
JOGET_USER="joget"
JOGET_URL="https://drive.usercontent.google.com/download?id=1sXTRXAXz-i4_szr3fXiJwjAEp0sNfoFr&export=download&confirm=t"
CONFIG_FILE="/etc/joget.conf"

generate_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9@#%^&*_+-=' </dev/urandom | head -c 24
}

prepare_system() {
  echo -e "${BLUE}Updating system packages...${NC}"
  sudo apt-get update -qq
  sudo apt-get install -y -qq openjdk-11-jre-headless mysql-server curl tar
}

configure_mysql() {
  echo -e "${BLUE}Configuring MySQL securely...${NC}"
  
  if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo -e "${YELLOW}Initializing MySQL database...${NC}"
    sudo mysqld --initialize-insecure --user=mysql
    sudo chown -R mysql:mysql /var/lib/mysql
  fi

  sudo mkdir -p /var/run/mysqld
  sudo chown mysql:mysql /var/run/mysqld
  sudo chmod 755 /var/run/mysqld

  sudo systemctl restart mysql
  sleep 5

  # Set root password
  echo -e "${YELLOW}Setting MySQL root password...${NC}"
  sudo mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD'; FLUSH PRIVILEGES;" 2>/dev/null || \
  sudo mysql -uroot -e "UPDATE mysql.user SET plugin='mysql_native_password', authentication_string=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE User='root'; FLUSH PRIVILEGES;"

  # Create Joget database
  sudo mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS jogetdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

# --- Joget Installation ---
install_joget() {
  echo -e "${BLUE}Installing Joget...${NC}"
  
  # Create dedicated user
  if ! id "$JOGET_USER" &>/dev/null; then
    sudo useradd -r -m -d "$INSTALL_DIR" "$JOGET_USER"
  fi

  sudo mkdir -p "$INSTALL_DIR"
  sudo chown "$JOGET_USER:$JOGET_USER" "$INSTALL_DIR"

  # Download and extract Joget
  sudo -u "$JOGET_USER" bash <<EOF
cd "$INSTALL_DIR"
[ -f joget.tar.gz ] || curl -L "$JOGET_URL" -o joget.tar.gz
tar xzf joget.tar.gz
cd joget-linux-*
chmod +x *.sh
EOF

  # Create systemd service
  JOGET_HOME="$(ls -d "$INSTALL_DIR"/joget-linux-*)"
  cat <<SERVICE | sudo tee /etc/systemd/system/joget.service >/dev/null
[Unit]
Description=Joget Workflow
After=network.target mysql.service

[Service]
Type=forking
User=$JOGET_USER
WorkingDirectory=$JOGET_HOME
Environment="MYSQL_PWD=$MYSQL_ROOT_PASSWORD"
ExecStart=$JOGET_HOME/tomcat.sh start
ExecStop=$JOGET_HOME/tomcat.sh stop
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
SERVICE

  sudo systemctl daemon-reload
  sudo systemctl enable joget
}

# --- Main Execution ---
main() {
  # Generate or load configuration
  if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Using existing configuration${NC}"
    source "$CONFIG_FILE"
  else
    echo -e "${BLUE}Generating secure configuration...${NC}"
    MYSQL_ROOT_PASSWORD=$(generate_password)
    JOGET_ADMIN_PASSWORD=$(generate_password)
    
    cat <<CONFIG | sudo tee "$CONFIG_FILE" >/dev/null
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
JOGET_ADMIN_PASSWORD="$JOGET_ADMIN_PASSWORD"
INSTALL_DIR="$INSTALL_DIR"
CONFIG
    
    sudo chmod 600 "$CONFIG_FILE"
  fi

  prepare_system
  configure_mysql
  install_joget

  # Start services
  sudo systemctl start joget
  sleep 10 # Wait for Joget to initialize

  # Change default admin password
  echo -e "${BLUE}Securing Joget admin account...${NC}"
  if ! curl -s -X POST "http://localhost:8080/jw/web/json/admin/setup/changeAdminPassword" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "currentPassword=password&newPassword=$JOGET_ADMIN_PASSWORD"; then
    echo -e "${YELLOW}Warning: Failed to change admin password automatically${NC}"
    echo -e "Please change it manually at: http://$(hostname -I | awk '{print $1}'):8080/jw"
  fi

  # Cleanup
  sudo rm -f "$INSTALL_DIR/joget.tar.gz"

  # Completion message
  echo -e "\n${GREEN}INSTALLATION COMPLETE${NC}"
  echo -e "\n${CYAN}ACCESS INFORMATION${NC}"
  echo -e "URL: http://$(hostname -I | awk '{print $1}'):8080/jw"
  echo -e "Admin username: admin"
  echo -e "Admin password: $JOGET_ADMIN_PASSWORD"
  echo -e "\nMySQL root password: $MYSQL_ROOT_PASSWORD"
  echo -e "\n${YELLOW}IMPORTANT: Save these credentials in a secure location${NC}"
}

main "$@"