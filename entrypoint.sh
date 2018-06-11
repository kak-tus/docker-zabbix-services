#!/usr/bin/env sh

( crontab -l ; echo "*/$SRV_CHECK_PERIOD * * * * /usr/local/bin/docker-zabbix-services" ) | crontab -

crond -f &
child=$!

trap "kill $child" SIGTERM SIGINT
wait "$child"
trap - SIGTERM SIGINT
wait "$child"
