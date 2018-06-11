package main

import (
	"fmt"
	"os"
	"strconv"

	"github.com/adubkov/go-zabbix"
	"github.com/hashicorp/consul/api"
)

type serviceCount struct {
	count        int
	setupedCount int
}

var client *api.Client
var catalog *api.Catalog
var metrics []*zabbix.Metric
var host string
var discoveryKey string
var itemKey string
var servicesCount map[string]*serviceCount

var statusMap = map[string]string{
	"passing":  "0",
	"warning":  "1",
	"critical": "2",
}

var checksCache map[string]api.HealthChecks
var checkProcessed = map[string]bool{}

func main() {
	servicesCount = make(map[string]*serviceCount)
	checksCache = make(map[string]api.HealthChecks)

	var err error

	client, err = api.NewClient(api.DefaultConfig())
	if err != nil {
		panic(err)
	}

	catalog = client.Catalog()

	host = os.Getenv("SRV_HOSTNAME")
	discoveryKey = os.Getenv("SRV_DISCOVERY_KEY")
	itemKey = os.Getenv("SRV_ITEM_KEY")

	datacenters()

	if len(metrics) == 0 {
		return
	}

	packet := zabbix.NewPacket(metrics)
	sender := zabbix.NewSender(os.Getenv("SRV_ZABBIX_SERVER"), 10051)
	res, err := sender.Send(packet)
	if err != nil {
		panic(err)
	}

	println(string(res))
}

func datacenters() {
	dcs, err := catalog.Datacenters()
	if err != nil {
		panic(err)
	}

	for _, dc := range dcs {
		key := fmt.Sprintf("%s_dc_status[%s]", itemKey, dc)
		metrics = append(metrics, zabbix.NewMetric(host, key, "1"))

		nodes(dc)
	}

	flowServices()
}

func nodes(dc string) {
	nds, _, err := catalog.Nodes(&api.QueryOptions{
		Datacenter: dc,
	})
	if err != nil {
		println(err.Error())
		return
	}

	for _, nd := range nds {
		key := fmt.Sprintf("%s_node_status[%s,%s]", itemKey, nd.Datacenter, nd.Node)
		metrics = append(metrics, zabbix.NewMetric(host, key, "1"))

		services(nd)
	}
}

func services(nd *api.Node) {
	cn, _, err := catalog.Node(nd.Node, &api.QueryOptions{
		Datacenter: nd.Datacenter,
	})
	if err != nil {
		println(err.Error())
		return
	}

	for _, srv := range cn.Services {
		count := detectCount(srv.Tags)

		if count > 0 {
			_, ok := servicesCount[srv.Service]
			if !ok {
				servicesCount[srv.Service] = &serviceCount{
					setupedCount: count,
					count:        0,
				}
			}

			servicesCount[srv.Service].count++
		} else {
			key := fmt.Sprintf("%s_service_status[%s,%s,%s]", itemKey, nd.Datacenter, nd.Node, srv.ID)
			metrics = append(metrics, zabbix.NewMetric(host, key, "1"))
		}

		checks(nd, srv)
	}
}

func checks(nd *api.Node, srv *api.AgentService) {
	key := nd.Datacenter + "," + srv.Service
	_, ok := checksCache[key]

	if !ok {
		checks, _, err := client.Health().Checks(srv.Service, &api.QueryOptions{
			Datacenter: nd.Datacenter,
		})
		if err != nil {
			println(err.Error())
			return
		}

		checksCache[key] = checks
	}

	for _, c := range checksCache[key] {
		if c.Node != nd.Node {
			continue
		}

		key := nd.Datacenter + "," + nd.Node + "," + srv.ID + "," + c.CheckID

		_, ok := checkProcessed[key]
		if ok {
			continue
		}

		checkProcessed[key] = true

		key = fmt.Sprintf("%s_check_status[%s]", itemKey, key)
		metrics = append(metrics, zabbix.NewMetric(host, key, statusMap[c.Status]))
	}
}

func detectCount(tags []string) int {
	for _, tag := range tags {
		if len(tag) > 6 && tag[0:6] == "count-" {
			count, err := strconv.Atoi(tag[6:])
			if err != nil {
				continue
			}
			return count
		}
	}

	return 0
}

func flowServices() {
	for s, v := range servicesCount {
		key := fmt.Sprintf("%s_service_flow_count[%s]", itemKey, s)
		metrics = append(metrics, zabbix.NewMetric(host, key, strconv.Itoa(v.count)))

		key = fmt.Sprintf("%s_service_flow_setuped_count[%s]", itemKey, s)
		metrics = append(metrics, zabbix.NewMetric(host, key, strconv.Itoa(v.setupedCount)))
	}
}
