#!/usr/bin/env bash
# Provision the EC2 build box. Idempotent for the security group and IAM role;
# launches a new instance each run, so check `status` first.
#
#   buildbox/ec2/provision.sh launch [REV]   # REV defaults to origin's HEAD of this branch
#   buildbox/ec2/provision.sh ticket         # print the dumbpipe ticket (via SSM)
#   buildbox/ec2/provision.sh start|stop|status|terminate
#
# REV must be pushed: the box fetches its config from github:drewr/dotfiles/REV.
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-datum-sandbox-admin}
export AWS_REGION=${AWS_REGION:-us-east-2}
NAME=datum-buildbox
TYPE=${TYPE:-t3a.medium}
DISK_GB=${DISK_GB:-16}
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
           --description "Datum build box, no inbound" --query GroupId --output text)
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
  read -r ami name rootdev < <(latest_ami)
  echo "ami=$ami ($name) rev=$rev sg=$sg"
  userdata=$(mktemp)
  trap 'rm -f "$userdata"' RETURN
  cat > "$userdata" <<EOF
#!/bin/sh
# Apply the build box config pinned to $rev. Re-runs on every boot as a no-op.
nixos-rebuild switch --option experimental-features 'nix-command flakes' \\
  --flake 'github:drewr/dotfiles/$rev?dir=buildbox/ec2#buildbox'
EOF
  aws ec2 run-instances --image-id "$ami" --instance-type "$TYPE" \
    --security-group-ids "$sg" --iam-instance-profile "Name=$NAME" \
    --block-device-mappings "DeviceName=$rootdev,Ebs={VolumeSize=$DISK_GB,VolumeType=gp3,DeleteOnTermination=true}" \
    --metadata-options HttpTokens=required \
    --user-data "file://$userdata" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=rev,Value=$rev}]" \
    --query 'Instances[0].InstanceId' --output text
}

ticket() {
  local id cmd
  id=$(instance_id)
  cmd=$(aws ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
          --parameters 'commands=["cat /var/lib/dumbpipe/ticket"]' \
          --query Command.CommandId --output text)
  aws ssm wait command-executed --command-id "$cmd" --instance-id "$id"
  aws ssm get-command-invocation --command-id "$cmd" --instance-id "$id" \
    --query StandardOutputContent --output text
}

# Backticks in the status query are JMESPath literals, not shell.
# shellcheck disable=SC2016
case ${1:-status} in
  launch)    shift; launch "$@" ;;
  ticket)    ticket ;;
  start)     aws ec2 start-instances --instance-ids "$(instance_id)" >/dev/null ;;
  stop)      aws ec2 stop-instances --instance-ids "$(instance_id)" >/dev/null ;;
  terminate) aws ec2 terminate-instances --instance-ids "$(instance_id)" >/dev/null ;;
  status)    aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" \
               --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,Tags[?Key==`rev`]|[0].Value]' \
               --output table ;;
  *) echo "usage: $0 launch [REV]|ticket|start|stop|status|terminate" >&2; exit 2 ;;
esac
