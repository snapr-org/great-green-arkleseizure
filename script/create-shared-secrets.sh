#!/bin/bash

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
temp_dir=$(mktemp -d)
keys_dir=${HOME}/snapr/shared
profile=arkleseizure

mkdir -p ${keys_dir}

for x in $(jq -r '.[] | select(.role == "archive" or .role == "validator") | @base64' ${script_dir}/../config/hosts.json); do
  _jq() {
    echo ${x} | base64 --decode | jq -r ${1}
  }
  server_hostname=$(_jq '.hostname')
  server_domain=$(_jq '.domain')
  server_cname=$(_jq '.cname')
  region=$(_jq '.region')
  deployment=$(_jq '.deployment')
  echo "checking shared secrets for ${server_cname} in ${region}"
  mkdir -p ${keys_dir}/${server_cname}

  if aws secretsmanager get-secret-value --profile ${profile} --region ${region} --secret-id shared-${server_cname} > ${keys_dir}/${server_cname}/secret.json 2> /dev/null && [ -s ${keys_dir}/${server_cname}/secret.json ]; then
    echo "detected existing aws secret: shared-${server_cname}"
  else
    echo "detected missing aws secret: shared-${server_cname}"
    echo "---" > ${keys_dir}/${server_cname}/shared.yml
    echo "smtp:" >> ${keys_dir}/${server_cname}/shared.yml
    echo "  username: $(pass snapr-org/aws/ses/smtp/snapr/username)" >> ${keys_dir}/${server_cname}/shared.yml
    echo "  password: $(pass snapr-org/aws/ses/smtp/snapr/password)" >> ${keys_dir}/${server_cname}/shared.yml
    yq '.' ${keys_dir}/${server_cname}/shared.yml > ${keys_dir}/${server_cname}/shared.json

    if aws secretsmanager restore-secret --profile ${profile} --region ${region} --secret-id shared-${server_cname} > ${keys_dir}/${server_cname}/secret.json 2> /dev/null; then
      echo "cancelled scheduled deletion of secret: shared-${server_cname}"
      if aws secretsmanager put-secret-value \
        --profile ${profile} \
        --region ${region} \
        --secret-id shared-${server_cname} \
        --secret-string file://${keys_dir}/${server_cname}/shared.yml > ${keys_dir}/${server_cname}/secret.json; then
        echo "updated secret: shared-${server_cname}"
      else
        echo "failed to update secret: shared-${server_cname}"
      fi
    else
      if aws secretsmanager describe-secret --profile ${profile} --region ${region} --secret-id shared-${server_cname} > ${keys_dir}/${server_cname}/secret.json 2> /dev/null; then
        if aws secretsmanager put-secret-value \
          --profile ${profile} \
          --region ${region} \
          --secret-id shared-${server_cname} \
          --secret-string file://${keys_dir}/${server_cname}/shared.yml > ${keys_dir}/${server_cname}/secret.json; then
          echo "updated secret: shared-${server_cname}"
        else
          echo "failed to update secret: shared-${server_cname}"
        fi
      else
        if aws secretsmanager create-secret \
          --profile ${profile} \
          --region ${region} \
          --name shared-${server_cname} \
          --description "smtp credentials for ${server_cname}" \
          --secret-string file://${keys_dir}/${server_cname}/shared.yml > ${keys_dir}/${server_cname}/secret.json; then
          echo "created secret: shared-${server_cname}"
        else
          echo "failed to create secret: shared-${server_cname}"
        fi
      fi
    fi
  fi

  if aws secretsmanager get-secret-value --profile ${profile} --region ${region} --secret-id shared-${server_cname} > ${keys_dir}/${server_cname}/secret.json 2> /dev/null && [ -s ${keys_dir}/${server_cname}/secret.json ]; then
    tf_deploy_dir=${script_dir}/../terraform/deployment/${deployment}/${server_hostname}
    if terraform -chdir=${tf_deploy_dir} state show module.${server_hostname}.aws_secretsmanager_secret.shared 2> /dev/null; then
      echo "detected module.${server_hostname}.aws_secretsmanager_secret.shared in terraform state for ${deployment}/${server_cname}"
    else
      terraform -chdir=${tf_deploy_dir} import module.${server_hostname}.aws_secretsmanager_secret.shared shared-${server_cname}
      echo "imported module.${server_hostname}.aws_secretsmanager_secret.shared to terraform state for ${deployment}/${server_cname}"
    fi
  fi
done
