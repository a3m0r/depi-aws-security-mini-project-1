# Mini Project 1 — Secure AWS Web Platform (Terraform)

## 1. Project overview

A small company web platform on AWS, built only with Terraform code (no clicking "Create" in the Console).
Users reach the site through **CloudFront** (HTTPS) → **Application Load Balancer** → two **private EC2 servers**
in two Availability Zones. The servers, the **RDS MySQL** database and the **EFS** file system have no public
access. Access to servers is by **Session Manager** only (no SSH key, no port 22, no NAT Gateway).
Every API call is logged (**CloudTrail**), every packet is recorded (**VPC Flow Logs**), a **Lambda** function closes
dangerous Security Group rules by itself, and **AWS Backup** keeps daily backups in a **governance-locked vault**.

## 2. Architecture diagram

<!-- TODO: export a diagram image (draw.io / diagrams.net) to docs/architecture.png and enable the next line -->
<!-- ![Architecture](docs/architecture.png) -->

```
 Internet users
      |
      v
 [ CloudFront ]  <- HTTPS + caching, adds secret header X-Origin-Verify
      |
      v
 [ Application Load Balancer ]  <- public subnets, answers 403 without the header
      |
      +---------------+---------------+
      v                               v
 [ EC2 server-a ]               [ EC2 server-b ]     <- private subnets, AZ-a / AZ-b
      |                               |
      +---------+---------------------+
                |                     |
                v                     v
            [ RDS MySQL ]          [ EFS ]           <- private subnets

 tools-vpc (10.1.0.0/16) --VPC peering--> app-vpc     <- monitoring server, private access only
 All API calls -> CloudTrail | All packets -> VPC Flow Logs | All disks -> AWS Backup
```

More detail: [docs/architecture.md](docs/architecture.md)

## 3. Network design table

| Name | CIDR | AZ | Type |
|---|---|---|---|
| depi-sec-app-vpc | 10.0.0.0/16 | — | VPC |
| depi-sec-public-a | 10.0.1.0/24 | us-east-1a | Public |
| depi-sec-public-b | 10.0.2.0/24 | us-east-1b | Public |
| depi-sec-private-a | 10.0.11.0/24 | us-east-1a | Private |
| depi-sec-private-b | 10.0.12.0/24 | us-east-1b | Private |
| depi-sec-tools-vpc | 10.1.0.0/16 | — | VPC |
| depi-sec-tools-a | 10.1.1.0/24 | us-east-1a | Private (tools VPC) |

## 4. Security controls table

| Control | Service | What it stops |
|---|---|---|
| Budget with automatic deny action | AWS Budgets + IAM | Runaway spending after a stolen key |
| Least-privilege roles, no user keys | IAM | Long-lived credentials leaking |
| Private subnets, no internet route | VPC | Direct internet access to servers/DB |
| Security Group chain (group-to-group) | EC2 SG | Lateral access between tiers |
| Network ACL | VPC NACL | A wrong Security Group rule |
| Interface + gateway endpoints | VPC endpoints | Traffic to AWS services leaving the AWS network |
| Session Manager, no SSH | SSM | Exposed port 22, stolen key pairs |
| Encrypted EBS / EFS / RDS / S3 | KMS / SSE | Reading data from a stolen disk |
| Block Public Access + TLS-only policy | S3 | Public buckets, plain-HTTP access |
| Secret origin header | CloudFront + ALB | Bypassing CloudFront and calling the ALB directly |
| CloudTrail with log validation | CloudTrail | Unknown or edited history |
| Flow Logs | VPC | Blind spots in network traffic |
| Alarms + failed-login metric | CloudWatch + SNS | Silent failures and brute-force attempts |
| Auto-remediation | Lambda + EventBridge | Open SSH/RDP left open for hours |
| Vault Lock (governance) | AWS Backup | Deleting backups before ransomware |

Full table with screenshots: [docs/security-controls.md](docs/security-controls.md)

## 5. Prerequisites

- Terraform `>= 1.6` (`terraform -version`)
- AWS CLI v2 (`aws --version`) configured with credentials for a **non-root** admin user (`aws configure`)
- An AWS account with permission to create IAM, VPC, EC2, RDS, S3, CloudFront, Lambda, Backup, Budgets
- Region **us-east-1** for everything
- Git

## 6. How to deploy

```bash
git clone https://github.com/<your-user>/depi-aws-security-mini-project-1.git
cd depi-aws-security-mini-project-1/terraform

cp terraform.tfvars.example terraform.tfvars      # Windows CMD: copy terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: alert_email and owner

terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan                             # about 10-15 minutes (CloudFront and RDS are the slow ones)
terraform output
```

Variables: `alert_email` (required), `owner`, `project_name` (default `depi-sec`), `region` (default `us-east-1`),
`vpc_cidr`, `tools_vpc_cidr`, `lock_alb_to_cloudfront` (default `true`).

After apply, click the confirmation links AWS emails you (SNS subscription).

Task 12 test mode (open ALB, so you can see both servers in a browser):
`terraform apply -var="lock_alb_to_cloudfront=false"`, take the screenshots, then apply again without the flag.

## 7. How to verify

Run the 10 tests from [docs/testing.md](docs/testing.md).

| # | Test | Expected | Result |
|---|---|---|---|
| 1 | Open the ALB DNS name directly | 403 Forbidden | TODO |
| 2 | Open the CloudFront URL | Page over HTTPS | TODO |
| 3 | SSH attempt / port 22 probe | Timeout + REJECT in Flow Logs | TODO |
| 4 | RDS from my laptop | Timeout | TODO |
| 5 | RDS from an app server | Success | TODO |
| 6 | Make an S3 object public | Refused | TODO |
| 7 | Add SSH 0.0.0.0/0 to app SG | Removed by Lambda + email | TODO |
| 8 | Stop nginx on one server | Unhealthy target, site up, alarm email | TODO |
| 9 | Curl app server from tools VPC | Page returned | TODO |
| 10 | Delete a recovery point | Access denied | TODO |

## 8. Screenshots

<!-- TODO: after each task add:  ### Task NN — name
![caption](screenshots/NN-name/file.png)
     Every image needs a caption. Blur account ID, email and keys. -->

## 9. Cost notes

Not free while running: the Application Load Balancer, the VPC interface endpoints, and RDS/EC2 once outside the free tier.
The project runs six interface endpoints (three in each VPC), billed per endpoint per AZ per hour — check the current AWS pricing page.
The NAT Gateway is **not** used.

<!-- TODO after the real run: real total from Billing -> Cost Explorer: $____ -->

## 10. How to destroy

```bash
cd terraform
terraform plan -destroy        # read it before typing yes
terraform destroy
terraform show                 # should print nothing
```

- Buckets use `force_destroy = true`, so Terraform empties them (including old versions) by itself.
- The backup vault has `force_destroy = true`; the governance lock is removed first by Terraform.
- CloudFront takes several minutes to delete. If a bucket delete fails because a late log file arrived, run `terraform destroy` again.
- Then check the Console: no ALB, EC2, RDS, endpoints, CloudFront, secret.

## 11. What I learned

<!-- TODO: write in your own words, at least 10 lines. -->

## 12. Known limitations

<!-- TODO: write what you would improve with more time (your own words). -->
