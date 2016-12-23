#!/bin/bash

printf "This script returns the DNS name of the ELB hosting the app. \nInfrastructure is created when a Git Push or PR triggers Travis\n\n"

app_dns=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[?LoadBalancerName==`svaranasi-lb`].DNSName')
if ! [[ "$app_dns" == *"svaranasi"* ]]; then
    printf "\n\nCouldn't find ELB.\n Please create infrastructure by re-building last Travis build of a previous Git Push or PR."
else
    http_code=$(curl -so /dev/null -X GET -w "%{http_code}" http://${app_dns})
    if [[ $http_code == 200 ]]; then
        echo "The app is available on: http://$app_dns"
    fi
fi
