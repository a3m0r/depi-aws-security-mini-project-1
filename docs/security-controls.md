# Security controls

| # | Control | AWS service | Threat it stops | Proof (screenshot) |
|---|---|---|---|---|
| 1 | Budget with automatic deny action | Budgets + IAM | Stolen key starts expensive resources | screenshots/02-budget/ |
| 2 | Password policy, group-based permissions | IAM | Weak passwords, permission sprawl | screenshots/03-iam/ |
| 3 | Instance role instead of access keys | IAM | Long-lived keys in code or user_data | screenshots/03-iam/ |
| 4 | Private subnets, no internet route | VPC | Direct internet access to servers | screenshots/04-vpc/ |
| 5 | Group-to-group Security Groups, no port 22 | Security Groups | Lateral movement, exposed SSH | screenshots/05-security-groups/ |
| 6 | Custom NACL (deny 22, stateless) | Network ACL | A mistake in a Security Group | screenshots/06-nacl/ |
| 7 | Gateway + interface endpoints | VPC endpoints | Service traffic crossing the internet | screenshots/07-endpoints/ |
| 8 | Session Manager, no key pair, IMDSv2 | SSM / EC2 | SSH brute force, metadata credential theft | screenshots/08-ec2-ssm/ |
| 9 | Encrypted EBS and EFS | EBS / EFS | Reading data from a stolen disk | screenshots/09-storage-efs/ |
| 10 | Block Public Access, TLS-only policy, versioning | S3 | Public buckets, plain-HTTP access, overwrites | screenshots/10-s3/ |
| 11 | Private, encrypted database; password in Secrets Manager | RDS + Secrets Manager | Public database, hard-coded password | screenshots/11-rds/ |
| 12 | Only the ALB is public, health checks | ALB | Exposing servers, sending traffic to broken servers | screenshots/12-alb/ |
| 13 | HTTPS front door + secret origin header | CloudFront + ALB | Bypassing CloudFront | screenshots/13-cloudfront/ |
| 14 | Multi-Region trail with log validation | CloudTrail | Unknown or edited history | screenshots/14-cloudtrail/ |
| 15 | Flow Logs (ALL traffic) | VPC Flow Logs | Blind spots in network traffic | screenshots/15-flowlogs/ |
| 16 | Alarms + failed-login metric | CloudWatch + SNS | Silent failures, brute force | screenshots/16-cloudwatch/ |
| 17 | Auto-remediation of open 22/3389 | Lambda + EventBridge | Dangerous rule left open | screenshots/17-lambda/ |
| 18 | Private peering, non-transitive | VPC peering | Sending monitoring traffic over the internet | screenshots/18-peering/ |
| 19 | Daily backups + governance Vault Lock | AWS Backup | Deleted backups, ransomware | screenshots/19-backup/ |

## Security Group chain

```
Internet --80--> [alb-sg] --80--> [app-sg] --3306--> [db-sg]
                                     |
                                     +-------2049--> [efs-sg]
```

## Bucket policy (deny insecure transport) — used on both buckets

```json
{
  "Sid": "DenyInsecureTransport",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::<bucket>", "arn:aws:s3:::<bucket>/*"],
  "Condition": { "Bool": { "aws:SecureTransport": "false" } }
}
```
