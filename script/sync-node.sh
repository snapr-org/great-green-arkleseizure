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
  expected_snapr_tag=v${expected_snapr_version/-x86_64-linux-gnu/}
  expected_snapr_url=https://github.com/snapr-org/snapr/releases/download/${expected_snapr_tag}/snapr_v${expected_snapr_version}
  expected_snapr_path=/usr/local/bin/snapr_v${expected_snapr_version}
  if curl -sL ${expected_snapr_url} -o ${expected_snapr_path} && find ${expected_snapr_path} -size -10M -delete && [ -s ${expected_snapr_path} ] && chmod +x ${expected_snapr_path}; then
    echo "snapr: ${expected_snapr_path} downloaded from ${expected_snapr_url}"
    if rm /usr/local/bin/snapr; then
      echo "snapr: symlink to version ${detected_snapr_version}, removed"
      if ln -s ${expected_snapr_path} /usr/local/bin/snapr; then
        echo "snapr: symlink to version ${expected_snapr_version}, created"
        if systemctl stop snapr; then
          echo "snapr: service stop requested"
          while systemctl is-active --quiet snapr; do
            echo "snapr: awaiting service stop"
          done
          echo "snapr: service stop detected"
          #expected_snapr_genesis=$(jq -r '.snapr.genesis' ${temp_dir}/host-config.json)
          #if [ "${expected_snapr_genesis}" = "true" ] && /usr/local/bin/snapr purge-chain --base-path /var/lib/snapr --chain mainnet -y; then
          #  echo "snapr: ${expected_snapr_version} genesis chain purged"
          #else
          #  echo "snapr: pausing for 2 minutes..."
          #  sleep 120
          #fi
          echo "snapr: pausing for 2 minutes..."
          sleep 120
          if systemctl start snapr; then
            echo "snapr: service start requested"
            while ! systemctl is-active --quiet snapr; do
              echo "snapr: awaiting service start"
            done
            echo "snapr: service start detected"
          fi
        else
          echo "snapr: service stop request failed"
        fi
      else
        echo "snapr: symlink to version ${expected_snapr_version}, creation failed"
      fi
    else
      echo "snapr: symlink to version ${detected_snapr_version}, remove failed"
    fi
  else
    echo "snapr: ${expected_snapr_path} download failed from ${expected_snapr_url}"
  fi
fi
