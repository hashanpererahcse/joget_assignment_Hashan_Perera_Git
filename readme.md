# Hybrid Cloud Infrastructure – Cloud Engineer Assignment

This project is a hybrid cloud proof-of-concept that simulates an on-premise environment and partially migrates a legacy Java web application (hosted with Apache and MySQL) to AWS.

##### **LIVE URL :** http://joget-assignment-alb-1506092433.ap-south-1.elb.amazonaws.com/jw/web/login

## [Project Overview]()

- **On-Prem Simulation**: Ubuntu server hosting Apache + MySQL, configured via Bash script.
- **AWS Cloud Architecture**:
  - VPC with public/private subnets across 2 AZs
  - EC2 instances for Apache (web) and Joget (Java app)
  - Application Load Balancer (ALB) for traffic distribution
  - RDS MySQL database in private subnet
- **Security**: Segmented network with Security Groups and IAM roles
- **Automation**: Terraform IaC, optional Ansible for app setup
- **Monitoring & DR**: CloudWatch monitoring and RDS snapshot-based DR

## [Architecture Diagram]()

![1754210474797](image/readme/1754210474797.png)

---

## [- On-Prem Simulation -]()

* **OS** : Ubuntu 22.04 (simulated via local VM)
* **Services** : Apache2, MySQL, Java App
* **Network** : Static IP (`192.168.1.10` and DHCP for now), UFW firewall enabled
* **VPN Concept** : AWS Site-to-Site VPN (simulated)

### `onprem.sh (dir: onprem > onprem.sh)`

Automates the setup of Joget Workflow on Ubuntu with MySQL

- Updates system packages (apt update)
- Installs java, MySQL Server, cURL & tar for download and extraction
- Configures UFW firewall rules
- Creating a dedicated jogetdb database
- Starts and enables services

##### - *[Steps for the implementation:]()*

- make script executable
  - **chmod +x onprem.sh**
- then run with
  - **sudo bash onprem.sh**

##### - Nginx Setup:

- **nginx _setup.txt** includes the nginx configurations

---

## [- AWS Cloud Infrastructure -]()

What this deploys

* 1x VPC with 2 public + 2 private subnets (across 2 AZs)
* Internet Gateway, single NAT Gateway (to keep costs down)
* Application Load Balancer (public) on port 80
* Auto Scaling Group (desired=2) for web servers (private subnets)
  * User data installs Apache (httpd) and shows a simple index page
* Bastion host (public subnet) for SSH access to the private instances
* Tight security groups (ALB → Web on 80, Bastion → Web on 22; SSH to Bastion only from your IP)

## [- Deployment -]()

```
terraform init
terraform validate
terraform plan
terraform apply
```

* When **apply** terraform promot to enter admin IP SSH run a powershell:

  * (Invoke-WebRequest -Uri "https://api.ipify.org").Content + "/32" - will return IP
* Give a password for the DB
* key pair (need to create a new keypair from aws > keypair> create key pair > and download the .pem file)) : provide the keypair name when promt
* SSH to the bastion:
* ```
  ssh -i <path-to-private-key.pem> ec2-user@<bastion_public_ip>

  ex : ssh -i C:\Users\xxx\.ssh\joget\joget-key-pem.pem -o "IdentitiesOnly yes" -J ec2-user@3.110.31.167 ec2-user@10.0.11.105
  ```

  From the bastion you can reach the private web instances on port 22/80.

**Ansible setup :**

sudo yum update -y
sudo amazon-linux-extras install -y ansible2 || (sudo yum install -y python3-pip && pip3 install ansible)

mkdir -p ~/.ssh && chmod 700 ~/.ssh
copy your PEM here (SFTP or scp) as ~/.ssh/joget-key.pem

chmod 600 ~/.ssh/joget-key.pem
mkdir -p ~/ansible && cd ~/ansible

**Make ini file**

cat > inventory.ini <<'INI'
[web]
10.0.11.42 # change to actual IP's
10.0.10.42 # change to actual IP's

[web:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=~/.ssh/joget-key.pem
ansible_python_interpreter=/usr/bin/python2
INI

**Testing**

ANSIBLE_HOST_KEY_CHECKING=False ansible -i inventory.ini web -m ping
ANSIBLE_HOST_KEY_CHECKING=False ansible -i inventory.ini web -b -a "curl -sI http://127.0.0.1/ | head -1; curl -sI http://127.0.0.1/jw/ | head -1"

**Run**

**replace the rds url and db_user and password as required**

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini joget.yml -e "rds_host=joget-assignment-mysql.cf0cus6e4wim.ap-south-1.rds.amazonaws.com db_name=jwdb db_user=jogetadmin db_pass='#Compaq123'"

### Teardown

```
terraform destroy
```

> make sure not to remove statefile from directory before running  : terraform destroy

**Terraform State Management :**

This PoC uses local backend for Terraform state. In production, this should be moved to a remote backend (eg S3 + DynamoDB) with locking and versioning to prevent drift and manage changes securely.

---

## [- VPN Connectivity -]()

![1754212634377](image/readme/1754212634377.png)

**Simulated VPN** : Site-to-Site VPN (Conceptual)

* **Steps** :
  * AWS Virtual Private Gateway attachment
  * Customer Gateway setup (with on-prem IP)
  * VPN Connection + Routing Tables update
  * On-prem firewall allows VPN tunnel traffic (UDP ports 500, 4500)

## [- VPN Configuration (Conceptual) -]()

To establish secure connectivity between the simulated on-premise environment and the AWS VPC, a **Site-to-Site VPN** setup is conceptually proposed. This allows private IP communication over an encrypted IPSec tunnel.

**Example (`ipsec.conf` for strongSwan):**

```conf
conn aws-vpn
    left=192.168.1.10
    leftid=203.0.113.5
    leftsubnet=192.168.1.0/24
    right=18.204.10.2
    rightsubnet=10.0.0.0/16
    auto=start
    ike=aes256-sha1-modp1024
    esp=aes256-sha1
    keyexchange=ikev1
```

##### AWS Side

* **Create a Virtual Private Gateway (VGW)**
  * Attach it to the VPC so it can accept VPN traffic.
* **Set up a Customer Gateway**
  * Use the on-premise public IP
* **Create a Site-to-Site VPN Connection**
  * Link the VGW and CGW, choose static or dynamic routing, and download the config.
* **Update VPC Route Tables**
  * Add a route to the on-premise network (e.g., `192.168.1.0/24`) via the VGW.
* **Security Groups & NACLs**
  * Open only the required ports (e.g., MySQL 3306, HTTP 80) for on-prem IP ranges.

## [Security Configuration]()

* ALB allows **HTTP (port 80)** from the internet
* EC2 application servers only accept traffic from the ALB
* RDS only accepts **MySQL (port 3306)** from EC2 app security group
* No public access to private subnets or the RDS instance
* Bastion host can be used for admin SSH access, restricted to your IP

## [Hybrid Connectivity Plan]()

- We're simulating a **Site-to-Site VPN** tunnel using **strongSwan** on the on-prem side and an AWS **Virtual Private Gateway** on the cloud side.

## [Backup and Disaster Recovery]()

**Amazon RDS:**

* Automated daily backups enabled
* Manual snapshots created and retained
* Can be restored to another region if needed

**On-Premise Server:**

* MySQL dumps stored locally in /backups
* Uploaded to S3 daily using:

  ```bash
  aws s3 cp /backups s3://joget-onprem-backups --recursive
  ```

## [Monitoring and Alerts]()

- **Metrics to watch**:
  - EC2 CPU Utilization
  - RDS Free Storage
  - ALB returning 5xx errors
- **Alarms & Alerts**:
  - CloudWatch Alarms

## [Change and Configuration Management]()

- Infrastructure is defined and version controlled using **Terraform**
- To detect drift: run `terraform plan` regularly
- Future plan: store secrets like DB credentials in **AWS Secrets Manager**
- All config and code tracked in GitHub

## [Assumptions]()

- VPN is simulated, not physically deployed

## [Challenges and Trade-offs]()

- Configuration user-data caused little difficult

## [Future Improvements]()

- Set up CI/CD with GitHub Actions
- Use AWS Secrets Manager for DB credentials
- Replace simulated VPN with real IPSec VPN if hardware available
