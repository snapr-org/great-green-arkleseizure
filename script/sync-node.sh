#!/usr/bin/env bash

# usage:
# curl -sL https://raw.githubusercontent.com/snapr-org/great-green-arkleseizure/main/script/sync-node.sh | sudo bash -s ${args}

temp_dir=$(mktemp -d)

instance_region=$(curl --sL http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
instance_name=$(aws ec2 describe-instances --region ${instance_region} --instance-id ${instance_id} --query "Reservations[*].Instances[*].Tags[?Key=='Name'].Value" --output text)
instance_domain=$(aws ec2 describe-instances --region ${instance_region} --instance-id ${instance_id} --query "Reservations[*].Instances[*].Tags[?Key=='Domain'].Value" --output text)
instance_cname=$(aws ec2 describe-instances --region ${instance_region} --instance-id ${instance_id} --query "Reservations[*].Instances[*].Tags[?Key=='cname'].Value" --output text)
instance_source=$(aws ec2 describe-instances --region ${instance_region} --instance-id ${instance_id} --query "Reservations[*].Instances[*].Tags[?Key=='Source'].Value" --output text)
config_url=${instance_source/github.com/raw.githubusercontent.com}/main/config/hosts.json

curl -sL ${config_url} | jq --arg hostname ${instance_name} --arg domain ${instance_domain} --arg cname ${instance_cname} --arg region ${instance_region} '.[] | select( .hostname == $hostname and .domain == $domain and .cname == $cname and .region == $region )' > ${temp_dir}/host-config.json

jq '.' ${temp_dir}/host-config.json