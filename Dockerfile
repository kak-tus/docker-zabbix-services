FROM alpine:3.5

RUN \
  apk add --no-cache perl perl-json zabbix-utils perl-libwww

ENV CONSUL_HTTP_ADDR=consul.service.consul:8500
ENV CONSUL_TOKEN=

ENV SRV_DISCOVERY_KEY=services_discovery
ENV SRV_ITEM_KEY=service_item
ENV SRV_HOSTNAME=
ENV SRV_ZABBIX_SERVER=

COPY services.pl /etc/periodic/15min/services

CMD [ "crond", "-f" ]
