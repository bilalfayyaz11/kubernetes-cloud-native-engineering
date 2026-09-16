#!/usr/bin/env bash

set -u

WARNING_DAYS=30
WARNING_SECONDS=$((WARNING_DAYS * 86400))

echo "=================================================="
echo " Kubernetes Certificate Expiration Monitor"
echo "=================================================="
echo

check_cert() {
    local cert="$1"

    [ -f "$cert" ] || return 0

    local expiry
    local subject
    local remaining

    expiry="$(sudo openssl x509 \
      -in "$cert" \
      -noout \
      -enddate \
      | cut -d= -f2)"

    subject="$(sudo openssl x509 \
      -in "$cert" \
      -noout \
      -subject \
      | sed 's/^subject=//')"

    remaining="$(
      sudo openssl x509 \
        -in "$cert" \
        -noout \
        -checkend "$WARNING_SECONDS" \
        >/dev/null 2>&1
      echo $?
    )"

    echo "Certificate : $cert"
    echo "Subject     : $subject"
    echo "Expires     : $expiry"

    if [ "$remaining" -eq 0 ]; then
        echo "Status      : OK - valid for more than ${WARNING_DAYS} days"
    else
        echo "Status      : WARNING - expires within ${WARNING_DAYS} days"
    fi

    echo "--------------------------------------------------"
}

for cert in /etc/kubernetes/pki/*.crt; do
    check_cert "$cert"
done

for cert in /etc/kubernetes/pki/etcd/*.crt; do
    check_cert "$cert"
done

echo
echo "=================================================="
echo " Certificate Monitor Complete"
echo "=================================================="
