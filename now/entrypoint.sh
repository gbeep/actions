#!/bin/bash

set -e

alias=$1
name=$2
prod=$3
force=$4
vars=$5
use_runtime_config=$6

function expand_vars {
  local line lineEscaped
  while IFS= read -r line || [[ -n $line ]]; do  # the `||` clause ensures that the last line is read even if it doesn't end with \n
    # Escape ALL chars. that could trigger an expansion..
    IFS= read -r -d '' lineEscaped < <(printf %s "$line" | tr '`([$' '\1\2\3\4')
    # ... then selectively reenable ${ references
    lineEscaped=${lineEscaped//$'\4'{/\${}
    # Finally, escape embedded double quotes to preserve them.
    lineEscaped=${lineEscaped//\"/\\\"}
    eval "printf '%s\n' \"$lineEscaped\"" | tr '\1\2\3\4' '`([$'
  done
}

# Configures Google Cloud SDK
function setup {
  echo $GCLOUD_SERVICE_KEY | gcloud auth activate-service-account --key-file=-
  gcloud config set project ${GCLOUD_PROJECT_ID}
  gcloud config set compute/region ${GCLOUD_REGION}

  echo $GCLOUD_SERVICE_KEY | cat > /tmp/account.json
  export GOOGLE_APPLICATION_CREDENTIALS=/tmp/account.json
}

# Export runtime config variables into current bash session
function inject_runtime_config {
  export $(
    gcloud beta runtime-config configs variables list \
      --quiet \
      --values \
      --config-name ${STAGE}-${REGION} \
      --format='json' \
      | jq -r '.[] | [(.name | split("/") | join("_") | split("-") | join("_") | ascii_upcase), .value] | join("=")' \
      | xargs
  )
}

# Writes environment file expanding variables not yet expanded such as Berglas vars
function write_env_file {
  cat /dev/null > .env.production
  IFS=$'\n'
  for item in $1
  do
    if [[ "$item" == *berglas* ]] ;
    then
      var=$(echo "$item" | sed 's/^\([A-Z0-9_]*\)=\(.*\)/\2/' | xargs)
      var_expanded=$(berglas access $var)
      echo "$item" | sed "s~${var}~$var_expanded~g" >> .env.production
    else
      echo "$item" >> .env.production
    fi
  done
}

function deploy {
  mv vercel.json vercel-${name}.json
  if [[ ! -z "${vars}" ]]; then
    env=$(env -i bash -l -c 'export $(cat .env.production | xargs) && jq -n env')
    env=$(echo $env | jq 'del(.PATH) | del(.PWD) | del(.SHLVL) | del(._)')

    jq --argjson env "$env" --arg alias "$alias" --arg name "$name" '.name = $name | .alias = $alias | .build.env = $env' vercel-$name.json > vercel.json
    rm vercel-${name}.json .env.production
  else
    jq --arg alias "$alias" --arg name "$name" '.name = $name | .alias = $alias' vercel-$name.json > vercel.json
  fi

  case $force in
    (true)    force='--force';;
    (false)   force='';;
  esac

  case $prod in
    (true)    url=$(now --confirm -t $ZEIT_TOKEN --prod $force);;
    (false)   url=$(now --confirm -t $ZEIT_TOKEN $force);;
  esac

  echo ::set-output name=url::$url
}

setup
if [[ ! -z "${vars}" ]]; then
  case $use_runtime_config in
    (true) inject_runtime_config;;
  esac
fi
if [[ ! -z "${vars}" ]]; then
  parsed=$(expand_vars <<< "${vars}")
  write_env_file "$parsed"
fi
deploy
