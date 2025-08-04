set -e

echo "[INFO] Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "[INFO] Installing Apache and MySQL..."
sudo apt install -y apache2 mysql-server

echo "[INFO] Configuring UFW firewall rules..."
sudo ufw allow 22      # SSH
sudo ufw allow 80      # HTTP
sudo ufw allow 443     # HTTPS
sudo ufw allow 3306    # MySQL
sudo ufw --force enable

echo "[INFO] Starting and enabling services..."
sudo systemctl enable apache2
sudo systemctl enable mysql
sudo systemctl start apache2
sudo systemctl start mysql

echo "[SUCCESS] On-premise simulation complete. Apache and MySQL are running."
