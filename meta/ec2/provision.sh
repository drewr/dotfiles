#!/usr/bin/env bash
# Provision the JuiceFS metadata host in us-east-1 (the same metro as Datum
# us-east-1/IAD). Wraps buildbox/ec2/provision.sh with this box's settings.
#
#   meta/ec2/provision.sh launch REV | ticket | start | stop | status | terminate
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export NAME=agent-meta AWS_REGION=us-east-1 TYPE=${TYPE:-t3a.small} DISK_GB=${DISK_GB:-16} \
       CONFIG=meta/ec2 ATTR=agentmeta TICKET_FILE=/var/lib/agent-meta/ticket
exec "$HERE/../../buildbox/ec2/provision.sh" "$@"
