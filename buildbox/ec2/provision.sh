#!/usr/bin/env bash
# Backticks in --query strings are JMESPath literals, not shell.
# shellcheck disable=SC2016
# Provision a NixOS EC2 box whose config lives in this repo: the build box by
# default, or the JuiceFS metadata host (meta/ec2/provision.sh sets the
# variables below). Idempotent for the security group and IAM role; launches a
# new instance each run, so check `status` first.
#
#   buildbox/ec2/provision.sh launch [REV]   # REV defaults to origin's HEAD of this branch
#   buildbox/ec2/provision.sh ticket         # print the dumbpipe ticket (via SSM)
#   buildbox/ec2/provision.sh ipv6           # IPv6 for the VPC and the running instance
#   buildbox/ec2/provision.sh start|stop|status|terminate
#
# REV must be pushed: the box fetches its config from
# github:drewr/dotfiles/REV?dir=$CONFIG#$ATTR.
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-datum-sandbox-admin}
export AWS_REGION=${AWS_REGION:-us-east-2}
NAME=${NAME:-datum-buildbox}
TYPE=${TYPE:-t3a.medium}
DISK_GB=${DISK_GB:-16}
CONFIG=${CONFIG:-buildbox/ec2}
ATTR=${ATTR:-buildbox}
TICKET_FILE=${TICKET_FILE:-/var/lib/dumbpipe/ticket}
IPV6=${IPV6:-0}   # 1: give the instance public IPv6 (sets up the VPC once)
NIXOS_AMI_OWNER=427812963091   # official NixOS AMIs

instance_id() {
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$NAME" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

ensure_sg() {
  local sg vpc
  sg=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$NAME" \
         --query 'SecurityGroups[0].GroupId' --output text)
  if [ "$sg" = None ]; then
    vpc=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
            --query 'Vpcs[0].VpcId' --output text)
    # No ingress rules: everything reaches the box over iroh or SSM.
    sg=$(aws ec2 create-security-group --group-name "$NAME" --vpc-id "$vpc" \
           --description "$NAME, no inbound" --query GroupId --output text)
  fi
  echo "$sg"
}

ensure_profile() {
  if ! aws iam get-instance-profile --instance-profile-name "$NAME" >/dev/null 2>&1; then
    aws iam create-role --role-name "$NAME" --assume-role-policy-document \
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
    aws iam attach-role-policy --role-name "$NAME" \
      --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    aws iam create-instance-profile --instance-profile-name "$NAME" >/dev/null
    aws iam add-role-to-instance-profile --instance-profile-name "$NAME" --role-name "$NAME"
    sleep 10   # instance profiles take a moment to become usable
  fi
}

# Public IPv6 for the default VPC, once: an Amazon-provided block, a /64 per
# default subnet (so any AZ works), and a ::/0 route to the internet gateway.
# Sandboxes on Datum are IPv6-only, so this is what lets iroh go direct instead
# of through the relay. Idempotent.
ensure_ipv6() {
  local vpc block rt igw i=0 subnet
  vpc=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
          --query 'Vpcs[0].VpcId' --output text)
  block=$(aws ec2 describe-vpcs --vpc-ids "$vpc" \
            --query 'Vpcs[0].Ipv6CidrBlockAssociationSet[?Ipv6CidrBlockState.State==`associated`]|[0].Ipv6CidrBlock' --output text)
  if [ "$block" = None ]; then
    aws ec2 associate-vpc-cidr-block --vpc-id "$vpc" --amazon-provided-ipv6-cidr-block >/dev/null
    for _ in $(seq 30); do
      block=$(aws ec2 describe-vpcs --vpc-ids "$vpc" \
                --query 'Vpcs[0].Ipv6CidrBlockAssociationSet[?Ipv6CidrBlockState.State==`associated`]|[0].Ipv6CidrBlock' --output text)
      [ "$block" != None ] && break
      sleep 2
    done
  fi
  echo "vpc $vpc ipv6 $block" >&2
  for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" Name=default-for-az,Values=true \
                    --query 'sort_by(Subnets,&AvailabilityZone)[].SubnetId' --output text); do
    if [ "$(aws ec2 describe-subnets --subnet-ids "$subnet" \
            --query 'length(Subnets[0].Ipv6CidrBlockAssociationSet[?Ipv6CidrBlockState.State==`associated`])' --output text)" = 0 ]; then
      # /56 block: subnet i gets the i-th /64 (prefix + two hex digits).
      aws ec2 associate-subnet-cidr-block --subnet-id "$subnet" \
        --ipv6-cidr-block "$(python3 -I -c 'import ipaddress,sys; n=ipaddress.ip_network(sys.argv[1]); print(list(n.subnets(new_prefix=64))[int(sys.argv[2])])' "$block" $i)" >/dev/null
    fi
    aws ec2 modify-subnet-attribute --subnet-id "$subnet" --assign-ipv6-address-on-creation
    i=$((i + 1))
  done
  rt=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" Name=association.main,Values=true \
         --query 'RouteTables[0].RouteTableId' --output text)
  igw=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" \
          --query 'InternetGateways[0].InternetGatewayId' --output text)
  aws ec2 create-route --route-table-id "$rt" --destination-ipv6-cidr-block ::/0 \
    --gateway-id "$igw" >/dev/null 2>&1 || true
}

latest_ami() {
  aws ec2 describe-images --owners "$NIXOS_AMI_OWNER" \
    --filters Name=architecture,Values=x86_64 Name=name,Values='nixos/*' \
    --query 'sort_by(Images,&CreationDate)[-1].[ImageId,Name,RootDeviceName]' --output text
}

launch() {
  local rev=${1:-$(git rev-parse origin/datum-unikraft-sessions)}
  if [ -n "$(instance_id)" ]; then echo "already exists: $(instance_id)" >&2; exit 1; fi
  local sg ami name rootdev userdata
  sg=$(ensure_sg)
  ensure_profile
  local v6=()
  if [ "$IPV6" = 1 ]; then ensure_ipv6; v6=(--ipv6-address-count 1); fi
  read -r ami name rootdev < <(latest_ami)
  echo "ami=$ami ($name) rev=$rev sg=$sg"
  userdata=$(mktemp)
  trap 'rm -f "$userdata"' RETURN
  cat > "$userdata" <<EOF
#!/bin/sh
# Apply the $ATTR config pinned to $rev. Re-runs on every boot as a no-op.
nixos-rebuild switch --option experimental-features 'nix-command flakes' \\
  --flake 'github:drewr/dotfiles/$rev?dir=$CONFIG#$ATTR'
EOF
  aws ec2 run-instances --image-id "$ami" --instance-type "$TYPE" \
    --security-group-ids "$sg" --iam-instance-profile "Name=$NAME" \
    --block-device-mappings "DeviceName=$rootdev,Ebs={VolumeSize=$DISK_GB,VolumeType=gp3,DeleteOnTermination=true}" \
    --metadata-options HttpTokens=required "${v6[@]}" \
    --user-data "file://$userdata" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=rev,Value=$rev}]" \
    --query 'Instances[0].InstanceId' --output text
}

ticket() {
  local id cmd
  id=$(instance_id)
  cmd=$(aws ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
          --parameters "commands=[\"cat $TICKET_FILE\"]" \
          --query Command.CommandId --output text)
  aws ssm wait command-executed --command-id "$cmd" --instance-id "$id"
  aws ssm get-command-invocation --command-id "$cmd" --instance-id "$id" \
    --query StandardOutputContent --output text
}

case ${1:-status} in
  launch)    shift; launch "$@" ;;
  ipv6)      ensure_ipv6
             # For an instance launched before IPV6=1: give it an address now.
             aws ec2 assign-ipv6-addresses --ipv6-address-count 1 --network-interface-id "$(aws ec2 describe-instances \
               --instance-ids "$(instance_id)" --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' --output text)" \
               --query 'AssignedIpv6Addresses[0]' --output text ;;
  ticket)    ticket ;;
  start)     aws ec2 start-instances --instance-ids "$(instance_id)" >/dev/null ;;
  stop)      aws ec2 stop-instances --instance-ids "$(instance_id)" >/dev/null ;;
  terminate) aws ec2 terminate-instances --instance-ids "$(instance_id)" >/dev/null ;;
  status)    aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" \
               --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,Tags[?Key==`rev`]|[0].Value]' \
               --output table ;;
  *) echo "usage: $0 launch [REV]|ipv6|ticket|start|stop|status|terminate" >&2; exit 2 ;;
esac
