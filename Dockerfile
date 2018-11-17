FROM golang:1.11.2-alpine3.8 AS build

WORKDIR /go/src/github.com/kak-tus/docker-zabbix-services

COPY main.go ./
COPY types.go ./
COPY vendor ./vendor/

RUN go install

FROM alpine:3.8

ENV \
  CONSUL_HTTP_ADDR= \
  CONSUL_TOKEN= \
  \
  SRV_DISCOVERY_KEY=services_discovery \
  SRV_ITEM_KEY=service_item \
  SRV_HOSTNAME= \
  SRV_ZABBIX_SERVER= \
  SRV_CHECK_PERIOD=15

COPY --from=build /go/bin/docker-zabbix-services /usr/local/bin/docker-zabbix-services
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

CMD ["/usr/local/bin/entrypoint.sh"]
