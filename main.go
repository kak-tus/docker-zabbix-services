package main

import (
	"fmt"
	"os"
	"strconv"

	"github.com/adubkov/go-zabbix"
	"github.com/hashicorp/consul/api"
	jsoniter "github.com/json-iterator/go"
)

var client *api.Client
var catalog *api.Catalog
var metrics []*zabbix.Metric
var host string
var discoveryKey string
var itemKey string
var servicesCount map[string]*serviceCount

var checksCache map[string]api.HealthChecks
var checkProcessed = map[string]bool{}

var dcData dcDataType
var nodeData nodeDataType
var serviceData serviceDataType
var serviceFlowData serviceFlowDataType
var checkData checkDataType

func main() {
	servicesCount = make(map[string]*serviceCount)
	checksCache = make(map[string]api.HealthChecks)

	dcData.Data = make([]dcType, 0)
	nodeData.Data = make([]nodeType, 0)
	serviceData.Data = make([]serviceType, 0)
	serviceFlowData.Data = make([]serviceFlowType, 0)
	checkData.Data = make([]checkType, 0)

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

		dcData.Data = append(dcData.Data, dcType{
			DC: dc,
		})

		nodes(dc)
	}

	discovery()
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

		nodeData.Data = append(nodeData.Data, nodeType{
			DC:   nd.Datacenter,
			Node: nd.Node,
		})

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

			serviceFlowData.Data = append(serviceFlowData.Data, serviceFlowType{
				ServiceID:   srv.ID,
				ServiceName: srv.Service,
			})
		} else {
			key := fmt.Sprintf("%s_service_status[%s,%s,%s]", itemKey, nd.Datacenter, nd.Node, srv.ID)
			metrics = append(metrics, zabbix.NewMetric(host, key, "1"))

			serviceData.Data = append(serviceData.Data, serviceType{
				DC:          nd.Datacenter,
				Node:        nd.Node,
				ServiceID:   srv.ID,
				ServiceName: srv.Service,
			})
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

		checkData.Data = append(checkData.Data, checkType{
			DC:          nd.Datacenter,
			Node:        nd.Node,
			ServiceID:   srv.ID,
			ServiceName: srv.Service,
			CheckID:     c.CheckID,
			CheckName:   c.Name,
		})
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

func discovery() {
	encoded, err := jsoniter.Marshal(dcData)
	if err != nil {
		panic(err)
	}

	key := fmt.Sprintf("%s_dcs", discoveryKey)
	metrics = append(metrics, zabbix.NewMetric(host, key, string(encoded)))

	encoded, err = jsoniter.Marshal(nodeData)
	if err != nil {
		panic(err)
	}

	key = fmt.Sprintf("%s_nodes", discoveryKey)
	metrics = append(metrics, zabbix.NewMetric(host, key, string(encoded)))

	encoded, err = jsoniter.Marshal(serviceFlowData)
	if err != nil {
		panic(err)
	}

	key = fmt.Sprintf("%s_services_flow", discoveryKey)
	metrics = append(metrics, zabbix.NewMetric(host, key, string(encoded)))

	encoded, err = jsoniter.Marshal(serviceData)
	if err != nil {
		panic(err)
	}

	key = fmt.Sprintf("%s_services", discoveryKey)
	metrics = append(metrics, zabbix.NewMetric(host, key, string(encoded)))

	encoded, err = jsoniter.Marshal(checkData)
	if err != nil {
		panic(err)
	}

	key = fmt.Sprintf("%s_checks", discoveryKey)
	metrics = append(metrics, zabbix.NewMetric(host, key, string(encoded)))
}
