#!/bin/sh
set -eu

REALIP_CONFIG=/etc/apache2/conf-enabled/remoteip-proxies.conf

{
  echo '# Generated at container startup from TRUSTED_PROXIES.'
  OLD_IFS=$IFS
  IFS=','
  for proxy in ${TRUSTED_PROXIES:-}; do
    proxy=$(printf '%s' "$proxy" | tr -d '[:space:]')
    if [ -n "$proxy" ]; then
      printf 'RemoteIPTrustedProxy %s\n' "$proxy"
    fi
  done
  IFS=$OLD_IFS
} > "$REALIP_CONFIG"

exec docker-entrypoint.sh "$@"
