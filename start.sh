#!/usr/bin/env sh

( crontab -l ; echo "*/$SRV_CHECK_PERIOD * * * * /usr/local/bin/services.pl" ) | crontab -

crond -f &
child=$!

trap "kill $child" SIGTERM SIGINT
wait "$child"
