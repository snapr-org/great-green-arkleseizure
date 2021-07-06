#!/usr/bin/env bash

node_keys_mount_point=${1}
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if test -z "${1}" || [ ! -d ${node_keys_mount_point} ]; then
  echo "usage: ${script_dir}/backup-node-keys.sh /path/to/node/keys/mount/point"
  exit 1
fi

for x in $(jq -r '.[] | select(.role == "archive" or .role == "validator") | @base64' ${script_dir}/../config/hosts.json); do
  _jq() {
    echo ${x} | base64 --decode | jq -r ${1}
  }
  remote_hostname=$(_jq '.hostname')
  remote_domain=$(_jq '.domain')
  remote_cname=$(_jq '.cname')
  remote_username=$(_jq '.username')
  remote_region=$(_jq '.region')
  remote_deployment=$(_jq '.deployment')

  remote_file_path=/var/lib/snapr/chains/${remote_deployment//-/_}/network/secret_ed25519
  local_file_path=${node_keys_mount_point}/${remote_cname}${remote_file_path}
  mkdir -p $(dirname ${local_file_path})
  if rsync --rsync-path="sudo rsync" --ignore-missing-args -azP ${remote_username}@${remote_cname}:${remote_file_path} ${local_file_path}; then
    echo "fetched ${local_file_path} from ${remote_cname}:${remote_file_path}"
  else
    echo "failed to fetch ${local_file_path} from ${remote_cname}:${remote_file_path}"
  fi
done
