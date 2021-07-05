#!/bin/bash

server_admin_email=$1
server_hostname=$2
server_domain=$3
server_cname=$4

# check all cert files exist and are not empty
if [ ! -f /etc/letsencrypt/live/${server_cname}/cert.pem ] || \
  [ ! -s /etc/letsencrypt/live/${server_cname}/cert.pem ] || \
  [ ! -f /etc/letsencrypt/live/${server_cname}/chain.pem ] || \
  [ ! -s /etc/letsencrypt/live/${server_cname}/chain.pem ] || \
  [ ! -f /etc/letsencrypt/live/${server_cname}/fullchain.pem ] || \
  [ ! -s /etc/letsencrypt/live/${server_cname}/fullchain.pem ] || \
  [ ! -f /etc/letsencrypt/live/${server_cname}/privkey.pem ] || \
  [ ! -s /etc/letsencrypt/live/${server_cname}/privkey.pem ]; then

  echo "detected missing or incomplete letsencrypt ssl cert"

  # check if cert, chain and private key exist in aws cert and secret stores
  if aws iam get-server-certificate --server-certificate-name ${server_hostname}.${server_domain} > ./server-certificate.json; then
    echo "fetched ${server_hostname}.${server_domain} aws server-certificate"

    # copy cert, chain and private key from aws cert and secret stores to local filesystem
    mkdir -p /etc/letsencrypt/live/${server_cname}
    if [ "${server_hostname}.${server_domain}" != "${server_cname}" ]; then
      ln -s /etc/letsencrypt/live/${server_cname} /etc/letsencrypt/live/${server_hostname}.${server_domain}
    fi
    jq -r '.ServerCertificate.CertificateBody' ./server-certificate.json > /etc/letsencrypt/live/${server_cname}/cert.pem
    jq -r '.ServerCertificate.CertificateChain' ./server-certificate.json > /etc/letsencrypt/live/${server_cname}/chain.pem
    cat /etc/letsencrypt/live/${server_cname}/{cert,chain}.pem > /etc/letsencrypt/live/${server_cname}/fullchain.pem
    aws secretsmanager get-secret-value --region us-west-2 --secret-id ssl-${server_hostname}.${server_domain} | jq -r '.SecretString' > /etc/letsencrypt/live/${server_cname}/privkey.pem
  else
    echo "missing ${server_hostname}.${server_domain} aws server-certificate"

    # append any specified alternative hostnames
    if [[ "${@:5}" = "" ]]; then
      unset alt_domain_args
    else
      unset alt_hosts
      unset alt_domain_args
      declare -a alt_hosts=(${@:4})
      declare -a alt_domain_args=()
      for alt_host in ${alt_hosts[@]}; do
        alt_domain_args+=("-d ${alt_host}")
      done
    fi

    # generate new letsencrypt cert with cerbot
    if [ "${server_hostname}.${server_domain}" = "${server_cname}" ]; then
      certbot run -n --nginx --agree-tos --no-redirect \
        -m ${server_admin_email} \
        -d ${server_cname} ${alt_domain_args[@]}
    else
      certbot run -n --nginx --agree-tos --no-redirect \
        -m ${server_admin_email} \
        -d ${server_cname} \
        -d ${server_hostname}.${server_domain} ${alt_domain_args[@]}
    fi

    # copy cert and chain from local filesystem to aws cert store
    aws iam upload-server-certificate \
      --server-certificate-name ${server_hostname}.${server_domain} \
      --certificate-body file:///etc/letsencrypt/live/${server_cname}/cert.pem \
      --certificate-chain file:///etc/letsencrypt/live/${server_cname}/chain.pem \
      --private-key file:///etc/letsencrypt/live/${server_cname}/privkey.pem

    # copy private key from local filesystem to aws secret store
    aws secretsmanager create-secret \
      --region us-west-2 \
      --name ssl-${server_hostname}.${server_domain} \
      --description "letsencrypt ssl private key for ${server_hostname}.${server_domain}" \
      --secret-string file:///etc/letsencrypt/live/${server_cname}/privkey.pem
  fi
  rm ./server-certificate.json
else
  echo "detected existing letsencrypt ssl cert"

  # check that cert is valid for all alternative names
  recertify_required=false
  unset subject_alternative_names
  unset alt_domain_args
  declare -a subject_alternative_names=(${server_hostname}.${server_domain} ${@:3})
  declare -a alt_domain_args=()
  for subject_alternative_name in ${subject_alternative_names[@]}; do
    if [[ ! " ${alt_domain_args[@]} " =~ " -d ${subject_alternative_name} " ]]; then
      alt_domain_args+=("-d ${subject_alternative_name}")
    fi
    if [[ $(echo | openssl s_client -showcerts -servername ${subject_alternative_name} -connect ${subject_alternative_name}:443 2>/dev/null | openssl x509 -inform pem -noout -text) == *DNS:${subject_alternative_name}* ]]; then
      echo "detected existing certificate validity for subject alternative name: ${subject_alternative_name}"
    else
      echo "detected missing certificate validity for subject alternative name: ${subject_alternative_name}"
      recertify_required=true
    fi
  done
  echo "recertify required: ${recertify_required}"
  if [ "${recertify_required}" = true ] ; then
    echo "alt domain args: ${alt_domain_args[@]}"
    certbot run -n --nginx --agree-tos --expand --no-redirect \
      -m ${server_admin_email} \
      ${alt_domain_args[@]}

    # copy cert and chain from local filesystem to aws cert store
    if aws iam delete-server-certificate --server-certificate-name ${server_hostname}.${server_domain}; then
      echo "existing aws iam server certificate: ${server_hostname}.${server_domain}, deleted"
      if aws iam upload-server-certificate \
        --server-certificate-name ${server_hostname}.${server_domain} \
        --certificate-body file:///etc/letsencrypt/live/${server_cname}/cert.pem \
        --certificate-chain file:///etc/letsencrypt/live/${server_cname}/chain.pem \
        --private-key file:///etc/letsencrypt/live/${server_cname}/privkey.pem; then
        echo "new aws iam server certificate: ${server_hostname}.${server_domain}, uploaded"
      else
        echo "failed to upload new aws iam server certificate: ${server_hostname}.${server_domain}"
      fi
    else
      echo "failed to delete existing aws iam server certificate: ${server_hostname}.${server_domain}"
    fi

    # copy private key from local filesystem to aws secret store
    if aws secretsmanager describe-secret --region us-west-2 --secret-id ssl-${server_hostname}.${server_domain} 2> /dev/null; then
      if aws secretsmanager put-secret-value \
        --region us-west-2 \
        --secret-id ssl-${server_hostname}.${server_domain} \
        --secret-string file:///etc/letsencrypt/live/${server_cname}/privkey.pem; then
        echo "updated secret: ssl-${server_hostname}.${server_domain}"
      else
        echo "failed to update secret: ssl-${server_hostname}.${server_domain}"
      fi
    else
      if aws secretsmanager create-secret \
        --region us-west-2 \
        --name ssl-${server_hostname}.${server_domain} \
        --description "letsencrypt ssl private key for ${server_hostname}.${server_domain}" \
        --secret-string file:///etc/letsencrypt/live/${server_cname}/privkey.pem; then
        echo "created secret: ssl-${server_cname}"
      else
        echo "failed to create secret: ssl-${server_cname}"
      fi
    fi
  fi
fi
