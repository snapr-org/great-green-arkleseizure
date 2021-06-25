#!/bin/bash

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
temp_dir=$(mktemp -d)
keys_dir=${HOME}/snapr-org/host-keys
key_types=( dsa ecdsa ed25519 rsa )
host_ca_key_path=${HOME}/.ssh/snapr_host_ca
host_ca_comment=ops@snapr.org
profile=arkleseizure

if [ ! -f ${host_ca_key_path} ]; then
  ssh-keygen \
    -o \
    -a 100 \
    -t ed25519 \
    -N '' \
    -C ${host_ca_comment} \
    -f ${host_ca_key_path}
fi

mkdir -p ${keys_dir}

for x in $(jq -r '.[] | @base64' ${script_dir}/../config/hosts.json); do
  _jq() {
    echo ${x} | base64 --decode | jq -r ${1}
  }
  server_hostname=$(_jq '.hostname')
  server_domain=$(_jq '.domain')
  region=$(_jq '.region')
  echo "checking host keys for ${server_hostname}.${server_domain} in ${region}"
  mkdir -p ${keys_dir}/${server_hostname}.${server_domain}

  if aws secretsmanager get-secret-value --profile ${profile} --region ${region} --secret-id ssh-host-${server_hostname}.${server_domain} > ${keys_dir}/${server_hostname}.${server_domain}/secret.json 2> /dev/null && [ -s ${keys_dir}/${server_hostname}.${server_domain}/secret.json ]; then
    echo "detected existing aws secret: ssh-host-${server_hostname}.${server_domain}"
  else
    echo "detected missing aws secret: ssh-host-${server_hostname}.${server_domain}"
    echo "---" > ${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml

    for key_type in "${key_types[@]}"; do

      if [ ! -f ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key.pub ] || [ ! -s ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key.pub ]; then
        case ${key_type} in
          dsa)
            ssh-keygen -o -b 1024 -t ${key_type} -f ${HOME}/.ssh/id_${key_type} -N '' -C "root@${server_hostname}.${server_domain}" -f ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key
            ;;
          ecdsa)
            ssh-keygen -o -b 521 -t ${key_type} -f ${HOME}/.ssh/id_${key_type} -N '' -C "root@${server_hostname}.${server_domain}" -f ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key
            ;;
          ed25519)
            ssh-keygen -o -a 100 -t ${key_type} -f ${HOME}/.ssh/id_${key_type} -N '' -C "root@${server_hostname}.${server_domain}" -f ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key
            ;;
          rsa)
            ssh-keygen -o -b 4096 -t ${key_type} -f ${HOME}/.ssh/id_${key_type} -N '' -C "root@${server_hostname}.${server_domain}" -f ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key
            ;;
        esac
        if [ -f ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key ] && [ -s ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key ]; then
          echo "created ${server_hostname}.${server_domain}/ssh_host_${key_type}_key"
        else
          echo "failed to create ${server_hostname}.${server_domain}/ssh_host_${key_type}_key"
        fi
      else
        echo "detected ${server_hostname}.${server_domain}/ssh_host_${key_type}_key"
      fi

      if [ -s ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key ] && [ -s ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key.pub ]; then
        echo "${key_type}:" >> ${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml
        echo "  private: |" >> ${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml
        while read line; do
          echo "    ${line}" >> ${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml
        done < ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key
        echo "  public: |" >> ${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml
        while read line; do
          echo "    ${line}" >> ${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml
        done < ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key.pub
        if [ "${key_type}" = "ed25519" ]; then
          if [ ! -f ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key-cert.pub ]; then
            if ssh-keygen -h \
              -s ${host_ca_key_path} \
              -I "${server_hostname}.${server_domain}" \
              -n ${server_hostname}.${server_domain} \
              -V +52w \
              -f ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key-cert.pub \
              ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key.pub; then
              echo "created and signed ${server_hostname}.${server_domain}/ssh_host_${key_type}_key-cert.pub"
            else
              echo "failed to create and sign ${server_hostname}.${server_domain}/ssh_host_${key_type}_key-cert.pub"
            fi
          else
            echo "detected ${server_hostname}.${server_domain}/ssh_host_${key_type}_key-cert.pub"
          fi
          echo "  certificate: |" >> ${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml
          while read line; do
            echo "    ${line}" >> ${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml
          done < ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key-cert.pub
        fi
      else
        # we don't have the keys, files are empty
        rm ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key
        rm ${keys_dir}/${server_hostname}.${server_domain}/ssh_host_${key_type}_key.pub
      fi
    done

    yq '.' ${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml > ${keys_dir}/${server_hostname}.${server_domain}/host-keys.json

    if aws secretsmanager restore-secret --profile ${profile} --region ${region} --secret-id ssh-host-${server_hostname}.${server_domain} > ${keys_dir}/${server_hostname}.${server_domain}/secret.json 2> /dev/null; then
      echo "cancelled scheduled deletion of secret: ssh-host-${server_hostname}.${server_domain}"
      if aws secretsmanager put-secret-value \
        --profile ${profile} \
        --region ${region} \
        --secret-id ssh-host-${server_hostname}.${server_domain} \
        --secret-string file://${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml > ${keys_dir}/${server_hostname}.${server_domain}/secret.json; then
        echo "updated secret: ssh-host-${server_hostname}.${server_domain}"
      else
        echo "failed to update secret: ssh-host-${server_hostname}.${server_domain}"
      fi
    else
      if aws secretsmanager describe-secret --profile ${profile} --region ${region} --secret-id ssh-host-${server_hostname}.${server_domain} > ${keys_dir}/${server_hostname}.${server_domain}/secret.json 2> /dev/null; then
        if aws secretsmanager put-secret-value \
          --profile ${profile} \
          --region ${region} \
          --secret-id ssh-host-${server_hostname}.${server_domain} \
          --secret-string file://${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml > ${keys_dir}/${server_hostname}.${server_domain}/secret.json; then
          echo "updated secret: ssh-host-${server_hostname}.${server_domain}"
        else
          echo "failed to update secret: ssh-host-${server_hostname}.${server_domain}"
        fi
      else
        if aws secretsmanager create-secret \
          --profile ${profile} \
          --region ${region} \
          --name ssh-host-${server_hostname}.${server_domain} \
          --description "ssh host keys for ${server_hostname}.${server_domain}" \
          --secret-string file://${keys_dir}/${server_hostname}.${server_domain}/host-keys.yml > ${keys_dir}/${server_hostname}.${server_domain}/secret.json; then
          echo "created secret: ssh-host-${server_hostname}.${server_domain}"
        else
          echo "failed to create secret: ssh-host-${server_hostname}.${server_domain}"
        fi
      fi
    fi
  fi
done
