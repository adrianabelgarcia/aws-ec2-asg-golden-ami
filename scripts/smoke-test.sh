#!/usr/bin/env bash
# Smoke test against the public endpoint of an environment.
#
# Usage: smoke-test.sh <service-domain> <alb-dns-name> [expected-version]
#
# Resolves the ALB to an IP and connects with the service domain as SNI, so the certificate is
# verified exactly as clients see it, without depending on DNS propagation of the domain.
set -euo pipefail

usage() { echo "usage: $0 <service-domain> <alb-dns-name> [expected-version]" >&2; exit 2; }

DOMAIN="${1:-}"
ALB_DNS="${2:-}"
EXPECTED_VERSION="${3:-}"
[[ -n "${DOMAIN}" && -n "${ALB_DNS}" ]] || usage

alb_ip="$(getent ahostsv4 "${ALB_DNS}" | awk 'NR == 1 { print $1 }')"
[[ -n "${alb_ip}" ]] || { echo "::error::could not resolve ${ALB_DNS}"; exit 1; }

fetch() {
  curl --fail --silent --show-error --max-time 10 \
    --retry 10 --retry-delay 6 --retry-all-errors \
    --resolve "${DOMAIN}:443:${alb_ip}" \
    "https://${DOMAIN}$1"
}

health="$(fetch /health)"
echo "health: ${health}"
if [[ "${health}" != *'"status":"ok"'* ]]; then
  echo "::error::health endpoint did not report ok"
  exit 1
fi

version="$(fetch /version)"
echo "version: ${version}"
if [[ -n "${EXPECTED_VERSION}" && "${version}" != *"${EXPECTED_VERSION}"* ]]; then
  echo "::error::expected version ${EXPECTED_VERSION} but the service reports a different build"
  exit 1
fi

# The HTTP to HTTPS redirect is part of the public contract.
redirect_code="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
  --resolve "${DOMAIN}:80:${alb_ip}" "http://${DOMAIN}/health")"
if [[ "${redirect_code}" != "301" ]]; then
  echo "::error::expected HTTP 301 from port 80 but got ${redirect_code}"
  exit 1
fi

echo "smoke test passed for ${DOMAIN}"
