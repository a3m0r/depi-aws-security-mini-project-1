"""
Auto-remediation: close SSH (22) / RDP (3389) if somebody opens it to the whole internet.

Trigger : EventBridge rule on the CloudTrail event AuthorizeSecurityGroupIngress.
Action  : find the security group, revoke the dangerous rule, send an SNS email.
"""
import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
DANGEROUS_PORTS = [int(p) for p in os.environ.get("DANGEROUS_PORTS", "22,3389").split(",")]
OPEN_IPV4 = "0.0.0.0/0"
OPEN_IPV6 = "::/0"


def exposes_dangerous_port(permission):
    """True if this rule covers port 22 or 3389 (or all traffic)."""
    protocol = permission.get("IpProtocol")
    if protocol == "-1":  # "all traffic" rule
        return True
    if protocol != "tcp":
        return False
    from_port = permission.get("FromPort", 0)
    to_port = permission.get("ToPort", 65535)
    return any(from_port <= port <= to_port for port in DANGEROUS_PORTS)


def build_revoke_list(security_group):
    """Return the rules to remove: dangerous port AND open to the whole internet."""
    to_revoke = []
    for permission in security_group.get("IpPermissions", []):
        if not exposes_dangerous_port(permission):
            continue

        open_v4 = [r for r in permission.get("IpRanges", []) if r.get("CidrIp") == OPEN_IPV4]
        open_v6 = [r for r in permission.get("Ipv6Ranges", []) if r.get("CidrIpv6") == OPEN_IPV6]
        if not open_v4 and not open_v6:
            continue

        rule = {"IpProtocol": permission["IpProtocol"]}
        if permission["IpProtocol"] != "-1":
            rule["FromPort"] = permission["FromPort"]
            rule["ToPort"] = permission["ToPort"]
        if open_v4:
            rule["IpRanges"] = [{"CidrIp": OPEN_IPV4}]
        if open_v6:
            rule["Ipv6Ranges"] = [{"CidrIpv6": OPEN_IPV6}]
        to_revoke.append(rule)
    return to_revoke


def lambda_handler(event, context):
    logger.info("Event received: %s", json.dumps(event))

    detail = event.get("detail", {})
    if detail.get("errorCode"):
        logger.info("The API call failed (%s) - nothing to fix.", detail["errorCode"])
        return {"status": "ignored", "reason": "failed api call"}

    group_id = (detail.get("requestParameters") or {}).get("groupId")
    if not group_id:
        logger.info("No groupId in the event - nothing to do.")
        return {"status": "ignored", "reason": "no group id"}

    try:
        group = ec2.describe_security_groups(GroupIds=[group_id])["SecurityGroups"][0]
    except ClientError as error:
        logger.error("Cannot read %s: %s", group_id, error)
        return {"status": "error", "group": group_id}

    to_revoke = build_revoke_list(group)
    if not to_revoke:
        logger.info("%s has no open 22/3389 rule. All good.", group_id)
        return {"status": "clean", "group": group_id}

    ec2.revoke_security_group_ingress(GroupId=group_id, IpPermissions=to_revoke)
    logger.info("REVOKED %s on %s", json.dumps(to_revoke), group_id)

    who = (detail.get("userIdentity") or {}).get("arn", "unknown")
    source_ip = detail.get("sourceIPAddress", "unknown")
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="Security auto-remediation: open SSH/RDP rule removed",
        Message=(
            f"Security group : {group_id} ({group.get('GroupName')})\n"
            f"Removed rules  : {json.dumps(to_revoke)}\n"
            f"Added by       : {who}\n"
            f"Source IP      : {source_ip}\n"
            f"Event time     : {detail.get('eventTime', 'unknown')}\n"
        ),
    )
    return {"status": "remediated", "group": group_id, "revoked": to_revoke}
