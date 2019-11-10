FROM golang:1.13.2-alpine3.10 AS build

WORKDIR /go/docker-zabbix-services

COPY go.mod .
COPY go.sum .
COPY main.go .
COPY types.go .

RUN go build -o /go/bin/docker-zabbix-services

FROM alpine:3.10

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
