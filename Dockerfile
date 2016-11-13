FROM alpine:3.4

MAINTAINER Andrey Kuzmin "kak-tus@mail.ru"

ENV CONSUL_HTTP_ADDR=consul.service.consul:8500
ENV SRV_DISCOVERY_KEY=services_discovery
ENV SRV_ITEM_KEY=service_item
ENV SRV_HOSTNAME=
ENV SRV_ZABBIX_SERVER=

COPY services.pl /etc/periodic/15min/services

RUN apk add --update-cache perl perl-json zabbix-utils \
  && rm -rf /var/cache/apk/*

CMD crond -f
