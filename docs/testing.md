# Security tests (Task 20)

Run them after `terraform apply`. Replace `<...>` with values from `terraform output`.
For every test add: what you did, what you expected, what happened, and the screenshot.

| # | Test | How | Expected | What happened | Screenshot |
|---|---|---|---|---|---|
| 1 | ALB directly | `curl -i http://<alb_dns_name>` | `403 Forbidden` | TODO | TODO |
| 2 | CloudFront | open `<cloudfront_url>` | page over HTTPS | TODO | TODO |
| 3 | Port 22 | laptop: `nmap -Pn -p 22 <ALB public IP>` or `nc -zv -w 5 <ALB public IP> 22`; then search Flow Logs | timeout + REJECT line | TODO | TODO |
| 4 | RDS from laptop | `nc -zv -w 5 <rds_endpoint> 3306` | timeout | TODO | TODO |
| 5 | RDS from server | Session Manager on server-a: `nc -zv <rds_endpoint> 3306` | succeeded | TODO | TODO |
| 6 | Public S3 object | Console -> app bucket -> welcome.txt -> make public | refused by Block Public Access | TODO | TODO |
| 7 | Open SSH rule | `aws ec2 authorize-security-group-ingress --group-id <app_security_group_id> --protocol tcp --port 22 --cidr 0.0.0.0/0`, wait 1 minute, `aws ec2 describe-security-groups --group-ids <id>` | rule removed, email received | TODO | TODO |
| 8 | Stop nginx | Session Manager: `sudo systemctl stop nginx` | target unhealthy, site still works, alarm email | TODO | TODO |
| 9 | Tools VPC | Session Manager on tools server: `curl http://<app private ip>` | page returned | TODO | TODO |
| 10 | Locked vault | see commands below | access denied | TODO | TODO |

## Helpful commands

Test 3 — find the REJECT record in CloudWatch Logs (Logs Insights, log group `/depi-sec/vpc/flowlogs`):

```
fields @timestamp, @message
| filter @message like /REJECT/ and @message like / 22 /
| sort @timestamp desc
| limit 20
```

Or use the filter pattern from the project sheet in the log group search box:

```
[version, account, eni, source, destination, srcport, destport="22", protocol, packets, bytes, start, end, action="REJECT", status]
```

Test 10 — on-demand backup, then try to delete it:

```bash
aws backup start-backup-job \
  --backup-vault-name depi-sec-vault \
  --resource-arn <efs_arn> \
  --iam-role-arn <backup_role_arn> \
  --lifecycle DeleteAfterDays=30

aws backup list-backup-jobs --by-backup-vault-name depi-sec-vault        # wait for State = COMPLETED
aws backup list-recovery-points-by-backup-vault --backup-vault-name depi-sec-vault

aws backup delete-recovery-point \
  --backup-vault-name depi-sec-vault \
  --recovery-point-arn <recovery point arn>                              # must be denied
```

Also check: `aws backup describe-backup-vault --backup-vault-name depi-sec-vault` shows `Locked: true` and **no** `LockDate`
(no lock date = governance mode).
