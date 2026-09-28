# Architecture

## Diagram

```
 Internet users
      |
      v
 [ CloudFront ]  -- header X-Origin-Verify: <secret>
      |
      v
 [ ALB ]  public-a 10.0.1.0/24  |  public-b 10.0.2.0/24
      |
      +--------------------+
      v                    v
 [ server-a ]         [ server-b ]        private-a 10.0.11.0/24 | private-b 10.0.12.0/24
      |                    |
      +------+-------------+
             v             v
         [ RDS ]        [ EFS ]

 tools-vpc 10.1.0.0/16 (tools-a 10.1.1.0/24) <== VPC peering ==> app-vpc
```

## Subnet table

| Subnet | CIDR | AZ | Type | Holds |
|---|---|---|---|---|
| depi-sec-public-a | 10.0.1.0/24 | us-east-1a | Public | ALB |
| depi-sec-public-b | 10.0.2.0/24 | us-east-1b | Public | ALB |
| depi-sec-private-a | 10.0.11.0/24 | us-east-1a | Private | server-a, RDS, EFS target, endpoints |
| depi-sec-private-b | 10.0.12.0/24 | us-east-1b | Private | server-b, RDS subnet group, EFS target, endpoints |
| depi-sec-tools-a | 10.1.1.0/24 | us-east-1a | Private (tools VPC) | monitoring server |

## Route tables

| Route table | Destination | Target | Why |
|---|---|---|---|
| public | 10.0.0.0/16 | local | traffic inside the VPC |
| public | 0.0.0.0/0 | Internet Gateway | this route is what makes a subnet public |
| private | 10.0.0.0/16 | local | traffic inside the VPC |
| private | pl-xxxx (S3) | S3 gateway endpoint | private access to S3 |
| private | 10.1.0.0/16 | peering connection | reach the tools VPC |
| tools | 10.1.0.0/16 | local | traffic inside the tools VPC |
| tools | 10.0.0.0/16 | peering connection | reach the app VPC |

## Traffic path

User → CloudFront (HTTPS) → ALB (checks secret header) → EC2 (port 80) → RDS (3306) / EFS (2049).
The user never talks to a server. Each hop has its own control.

## Why each resource sits where it sits

- **ALB in public subnets**: the only component that must be reachable from the internet.
- **EC2, RDS, EFS in private subnets**: no route to the internet, no public IP.
- **Two Availability Zones**: the platform survives one data-centre problem.
- **Interface endpoints (ssm, ssmmessages, ec2messages)**: Session Manager works with no NAT Gateway.
- **S3 gateway endpoint**: free, and lets the servers download packages from the Amazon Linux repositories.
- **tools-vpc**: the security team reaches the app privately; this is the reason for peering.

## Design notes — where this code differs from the project sheet (and why)

1. **Backup vault lock has no `changeable_for_days`.** In AWS Backup, that argument switches the lock to
   *compliance* mode (permanent after the grace time). The sheet asks for governance mode, so it is left out.
2. **NACL rule 120 allows ephemeral ports from 0.0.0.0/0** (sheet: 10.0.0.0/16). Package downloads come from S3 public
   addresses; a NACL is stateless, so the reply would be dropped otherwise. Extra rules allow the tools VPC (peering).
3. **MySQL 8.4 instead of 8.0.** RDS for MySQL 8.0 left standard support on 2026-07-31; instances still on 8.0 are billed for Extended Support.
4. **tools-vpc has its own three interface endpoints and an S3 gateway endpoint**, otherwise Session Manager cannot reach that server.
5. **Flow-log REJECT for port 22**: a packet from the internet to a *private* IP never enters the VPC, so nothing is logged.
   Probe port 22 on the ALB's public address instead (Security Group rejects it, Flow Logs record it).
6. **`force_destroy = true`** on the buckets and the backup vault so a lab can be destroyed cleanly.
7. **`lock_alb_to_cloudfront` variable** lets you test the ALB directly (Task 12) before locking it (Task 13).
8. **`nmap-ncat`** is installed by user_data because Amazon Linux 2023 does not include `nc`.
