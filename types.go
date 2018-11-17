package main

var statusMap = map[string]string{
	"passing":  "0",
	"warning":  "1",
	"critical": "2",
}

type serviceCount struct {
	count        int
	setupedCount int
}

type dcType struct {
	DC string `json:"{#DC}"`
}

type dcDataType struct {
	Data []dcType `json:"data"`
}

type nodeType struct {
	DC   string `json:"{#DC}"`
	Node string `json:"{#NODE}"`
}

type nodeDataType struct {
	Data []nodeType `json:"data"`
}

type serviceType struct {
	DC          string `json:"{#DC}"`
	Node        string `json:"{#NODE}"`
	ServiceID   string `json:"{#SERVICE_ID}"`
	ServiceName string `json:"{#SERVICE_NAME}"`
}

type serviceDataType struct {
	Data []serviceType `json:"data"`
}

type serviceFlowType struct {
	ServiceID   string `json:"{#SERVICE_ID}"`
	ServiceName string `json:"{#SERVICE_NAME}"`
}

type serviceFlowDataType struct {
	Data []serviceFlowType `json:"data"`
}

type checkType struct {
	DC          string `json:"{#DC}"`
	Node        string `json:"{#NODE}"`
	ServiceID   string `json:"{#SERVICE_ID}"`
	ServiceName string `json:"{#SERVICE_NAME}"`
	CheckID     string `json:"{#CHECK_ID}"`
	CheckName   string `json:"{#CHECK_NAME}"`
}

type checkDataType struct {
	Data []checkType `json:"data"`
}
