# Hybrid Cloud Infrastructure - Cloud Engineer Assignment

This project demonstrates a hybrid infrastructure setup simulating an on-premises Linux server and a cloud-based (AWS) architecture for deploying a Java web application with a MySQL backend. Infrastructure is defined using Terraform and automated scripts.

---

## 📘 Project Overview

- **On-Prem Simulation**: Ubuntu server hosting Apache + MySQL, simulated via bash script.
- **AWS Cloud Architecture**:
  - VPC with public/private subnets across 2 AZs
  - EC2 instances for Apache (web) and Joget (Java app)
  - Application Load Balancer for traffic distribution
  - RDS MySQL database (private subnet)
- **Security**: Proper use of Security Groups and IAM roles
- **Automation**: User Data scripts, IaC with Terraform
- **Monitoring & DR**: CloudWatch and RDS snapshot strategy

---

## 🗺️ Architecture Diagram

On-Prem (Simulated)

└── Ubuntu Server

├── Apache HTTP

├── MySQL

└── VPN Tunnel (conceptual)

│

▼

+---------------------- AWS Cloud -----------------------+

| VPC: 10.0.0.0/16                                       |

|                                                        |

| Public Subnet A         Public Subnet B                |

| ┌──────────────┐       ┌──────────────┐                |

| │ EC2: Joget A │       │ EC2: Joget B │  ← ALB         |

| └──────────────┘       └──────────────┘                |

|         │                     │                        |

|         └──────── ALB ────────┘                        |

|                                                        |

| Private Subnet A          Private Subnet B             |

| ┌──────────────┐                                    |

| │ RDS: MySQL   │                                    |

| └──────────────┘                                    |

+--------------------------------------------------------+

VPN Connectivity

[On-Prem Network] --- [Customer Gateway] === VPN === [Virtual Private Gateway] --- [AWS VPC]
       192.168.1.0/24                          🔐                        🔐             10.0.0.0/16

ipsec.conf

### 🔧 Configuration Steps

#### 1. **On-Prem Side (Simulated)**

Use a tool like **strongSwan** or **OpenVPN** on your on-prem Linux server.

Example configuration (`ipsec.conf` for strongSwan):

conn aws-vpn
    left=192.168.1.10             # On-prem IP
    leftid=your.onprem.public.ip
    leftsubnet=192.168.1.0/24
    right=aws.vpn.endpoint.ip     # From AWS
    rightsubnet=10.0.0.0/16
    auto=start
    ike=aes256-sha1-modp1024
    esp=aes256-sha1
    keyexchange=ikev1

#### 2. **AWS Side**

Use AWS Site-to-Site VPN with these steps:

* Create a  **Customer Gateway (CGW)** :
  * Type: Static or dynamic (BGP)
  * IP: Your on-prem public IP (or simulated)
* Create a  **Virtual Private Gateway (VGW)** :
  * Attach it to your VPC
* Create a  **VPN Connection** :
  * Link VGW to CGW
  * AWS will auto-generate:
    * Pre-shared keys
    * IPsec tunnel configuration
* Update  **VPC route tables** :
  * Route 192.168.1.0/24 traffic through the VGW

---

### 🔐 Security Considerations

* **Encryption** : All traffic is IPsec encrypted
* **Firewall** : Open UDP 500, UDP 4500 for VPN traffic
* **Routing** : Use static or dynamic (BGP) routing
* **Monitoring** : Use CloudWatch or on-prem logs for tunnel status

---

### 🧪 Testing the Tunnel

Once configured:

* Ping AWS EC2 instances from the on-prem server
* Simulate MySQL connection from on-prem to AWS RDS (if allowed)
* Monitor latency and packet drops

---

## 🚀 Deployment Instructions

### Prerequisites

- AWS CLI configured
- Terraform v1.3+

### Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
---
terraform destroy



## 💻 On-Prem Simulation

* OS: Ubuntu 22.04 (or similar)
* Static IP: `192.168.10.10/24`
* UFW open ports: 22, 80, 443, 3306

### Configuration Script: `scripts/on_prem_setup.sh`

#!/bin/bash
apt update && apt install -y apache2 mysql-server
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 3306
ufw --force enable


## Security Configuration

* ALB allows HTTP (port 80) from anywhere
* Web/App EC2s allow traffic only from ALB
* RDS only accessible from App SG over port 3306
* No public access to private subnets or RDS
* Optional bastion host could be added for secure admin access


## 🔐 Security Configuration

* ALB allows HTTP (port 80) from anywhere
* Web/App EC2s allow traffic only from ALB
* RDS only accessible from App SG over port 3306
* No public access to private subnets or RDS
* Optional bastion host could be added for secure admin access

---

## 🌐 Hybrid Connectivity Plan

* **Simulated VPN Tunnel** : OpenVPN on-prem, AWS Virtual Private Gateway
* **Routing** : Static routes on both ends
* **Encryption** : Use of TLS for all external comms

---

## ♻️ Backup & Disaster Recovery

* **RDS** : Automated backups enabled, daily snapshots
* **On-Prem** : Backup scripts using `aws s3 cp` to send `/var/lib/mysql` dumps to S3
* **DR Plan** : Manual restore to different region using snapshot copy

---

## 📊 Monitoring & Alerts

* **CloudWatch Metrics** :
* EC2 CPU Utilization > 80%
* RDS Free Storage < 10%
* ALB 5xx errors > 5
* **CloudWatch Alarms + SNS** for alerting

---

## ⚙️ Change & Configuration Management

* Infrastructure managed with **Terraform**
* Secrets stored securely via **AWS Secrets Manager** (future work)
* Use of version control (Git) to track changes
* Drift detection using `terraform plan`

---

## ⚖️ Assumptions

* Joget is run in lightweight mode, not clustered
* Cost optimization takes priority over high availability
* VPN is simulated, not physically connected

---

## 🧠 Challenges & Trade-offs

* NAT Gateway adds cost but is essential for private subnet access
* ALB simplifies scaling but adds latency vs direct EC2
* RDS is easier to manage than MySQL on EC2 but less customizable

---

## 🔮 Future Improvements

* Add CI/CD pipeline with GitHub Actions
* Implement Secrets Manager for DB credentials
* Set up S3 lifecycle rules for backup pruning
* Enable SSM for bastion-less EC2 access
* Deploy real Site-to-Site VPN (if on-prem gear available
```
