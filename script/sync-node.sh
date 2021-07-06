#!/usr/bin/env bash

# usage:
# curl -sL https://raw.githubusercontent.com/snapr-org/great-green-arkleseizure/main/script/sync-node.sh | sudo bash -s ${args}

temp_dir=$(mktemp -d)

instance_region=$(curl -sL http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
instance_id=$(curl -sL http://169.254.169.254/latest/meta-data/instance-id)
instance_name=$(aws ec2 describe-tags --region ${instance_region} --filters "Name=resource-id,Values=${instance_id}" "Name=key,Values=Name" --query "Tags[*].Value" --output text)
instance_domain=$(aws ec2 describe-tags --region ${instance_region} --filters "Name=resource-id,Values=${instance_id}" "Name=key,Values=Domain" --query "Tags[*].Value" --output text)
instance_cname=$(aws ec2 describe-tags --region ${instance_region} --filters "Name=resource-id,Values=${instance_id}" "Name=key,Values=cname" --query "Tags[*].Value" --output text)
instance_source=$(aws ec2 describe-tags --region ${instance_region} --filters "Name=resource-id,Values=${instance_id}" "Name=key,Values=Source" --query "Tags[*].Value" --output text)
config_url=${instance_source/github.com/raw.githubusercontent.com}/main/config/hosts.json

curl -sL ${config_url} | jq --arg hostname ${instance_name} --arg domain ${instance_domain} --arg cname ${instance_cname} --arg region ${instance_region} '.[] | select( .hostname == $hostname and .domain == $domain and .cname == $cname and .region == $region )' > ${temp_dir}/host-config.json

detected_snapr_version=$(snapr --version | head -n 1 | cut -d' ' -f2)
expected_snapr_version=$(jq -r '.snapr.version' ${temp_dir}/host-config.json)

if [ "${detected_snapr_version}" = "${expected_snapr_version}" ]; then
  echo "snapr: detected version (${detected_snapr_version}) matches expected version (${expected_snapr_version})"
else
  echo "snapr: detected version (${detected_snapr_version}) does not match expected version (${expected_snapr_version})"
fi
