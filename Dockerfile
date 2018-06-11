FROM golang:1.10-alpine AS build

WORKDIR /go/src/github.com/kak-tus/docker-zabbix-services
COPY main.go ./
COPY vendor ./vendor/
RUN apk add --no-cache git && go get

FROM alpine:3.7

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
