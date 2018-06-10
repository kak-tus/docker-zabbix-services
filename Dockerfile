FROM alpine:3.7

RUN \
  apk add --no-cache \
    perl \
    perl-json \
    perl-libwww \
    zabbix-utils

ENV \
  CONSUL_HTTP_ADDR= \
  CONSUL_TOKEN= \
  \
  SRV_DISCOVERY_KEY=services_discovery \
  SRV_ITEM_KEY=service_item \
  SRV_HOSTNAME= \
  SRV_ZABBIX_SERVER= \
  SRV_CHECK_PERIOD=15

COPY services.pl /usr/local/bin/services.pl
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

CMD ["/usr/local/bin/entrypoint.sh"]
