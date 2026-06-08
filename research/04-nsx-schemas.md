# 04 — NSX 9.1 真實 Schema 參考

從 lab 自身 NSX 9.1.0.0 的 live OpenAPI spec 撈出來（權威來源）：

```
GET https://192.168.114.13/policy/api/v1/spec/openapi/nsx_policy_api.json
（2548 個 definitions；以下為 VKS/VPC 相關，已解開 allOf 繼承、略去 _base 欄位）
```

> 官方 developer portal 是 JS SPA 撈不到 schema；blog 也只給 UI 步驟。
> 這份是直接從你 lab 的 manager 撈的真實欄位定義。

---

## VNA（DTGW 路線）

### VirtualNetworkApplianceCluster
| 欄位 | 型別 | 備註 |
|------|------|------|
| display_name | string | |
| appliance_form_factor | enum | SMALL / MEDIUM / LARGE / XLARGE |
| appliance_type | enum | VirtualNetworkAppliance |
| service_type | enum | VPC_SERVICES / ROUTE_CONTROLLER |
| advanced_configuration | obj | { overlay_transport_zone_path, high_availability_profile } |
| members | array | [ VirtualNetworkApplianceClusterMember ] |

### VirtualNetworkApplianceClusterMember
| 欄位 | 型別 |
|------|------|
| edge_transport_node_path | string |
| appliance_path | string |
| appliance_unique_id | string |

### VirtualNetworkAppliance（節點）
| 欄位 | 型別 | 必填 |
|------|------|------|
| hostname | string | REQ |
| vm_deployment_config | VirtualNetworkApplianceDeploymentConfig | REQ |
| management_interface | VirtualNetworkApplianceManagementInterface | REQ |
| credentials | VirtualNetworkApplianceCredential | |
| failure_domain_path | string | |

### VirtualNetworkApplianceDeploymentConfig
| 欄位 | 型別 | 必填 |
|------|------|------|
| compute_manager_id | string | REQ |
| cluster_or_resource_pool_id | string | REQ |
| datastore_id | string | REQ |
| reservation_info | { memory_reservation, cpu_reservation } | |

### VirtualNetworkApplianceManagementInterface
| 欄位 | 型別 | 必填 |
|------|------|------|
| network_id | string | REQ |
| ip_assignment_specs | [ PolicyIpAssignmentSpec ] | REQ |

### VirtualNetworkApplianceCredential
`cli_username` / `cli_password` / `root_password` / `audit_username` / `audit_password`

### VirtualNetworkApplianceClusterAdvancedConfiguration
`overlay_transport_zone_path` / `high_availability_profile`

---

## Transit Gateway / VPC（兩路線共用）

### TransitGateway
| 欄位 | 型別 | 備註 |
|------|------|------|
| transit_subnets | [string] | 內部 transit CIDR（default = 100.64.0.0/21）|
| is_default | boolean | |
| span | BaseSpan | { type: ClusterBasedSpan \| ZoneBasedSpan } |
| external_ip_signaling_mode | enum | NONE / IPV4 |

### TransitGatewayAttachment
| 欄位 | 型別 | 必填 | 備註 |
|------|------|------|------|
| connection_path | string | REQ | 指向 Tier-0 external connection（centralized 的關鍵）|
| route_advertisement_rules | array | | |
| urpf_mode | enum | | NONE / STRICT |

### VpcConnectivityProfile
| 欄位 | 型別 | 必填 | 備註 |
|------|------|------|------|
| transit_gateway_path | string | REQ | |
| external_ip_blocks | [string] | | public / LB / SNAT IP 來源 |
| private_tgw_ip_blocks | [string] | | **VKS 要求 /16** |
| service_gateway | VpcServiceGatewayConfig | | centralized 才填 |
| is_default | boolean | | |

### VpcServiceGatewayConfig
| 欄位 | 型別 | 備註 |
|------|------|------|
| enable | boolean | centralized 設 true |
| edge_cluster_paths | [string] | **centralized 填 edge cluster；DTGW 留空（用 VNA）** |
| nat_config | VpcNatConfig | |
| qos_config | GatewayQosProfileConfig | |

### DistributedVlanConnection（DTGW external connection）
| 欄位 | 型別 | 必填 | 備註 |
|------|------|------|------|
| vlan_id | integer | REQ | |
| gateway_addresses | [string] | | external connection gateway CIDR |
| subnet_extension_connection | enum | | DISABLED / ENABLED_L2 / ENABLED_L2_AND_L3 |
| associated_ip_block_paths | [string] | | 綁 external IP block |
| restricted_availability | VlanAvailability | | |

### Span 型別（NSX 9.1 只有這些）
`BaseSpan` / `ClusterBasedSpan` / `ZoneBasedSpan` / `NetworkSpan` / `ChildNetworkSpan`
→ **沒有 EdgeBasedSpan**。DTGW vs Centralized 不是靠 span type 區分，而是靠
VPC profile 的 `service_gateway.edge_cluster_paths`（見 [01](01-dtgw-vs-edge.md)）。

---

## IP Block（兩路線共用）

### IpAddressBlock（infra-level external block）
```
PATCH /policy/api/v1/infra/ip-blocks/{id}
{
  "resource_type": "IpAddressBlock",
  "display_name": "...",
  "cidr": "192.168.114.108/26",
  "visibility": "EXTERNAL"        ← external block 用 EXTERNAL；private TGW block 用 PRIVATE
}
```

---

## 怎麼自己撈最新 schema

```bash
curl -sk -u 'admin:VMware1!VMware1!' \
  "https://192.168.114.13/policy/api/v1/spec/openapi/nsx_policy_api.json" -o nsx.json
# 解 allOf 繼承後印某個 definition 的欄位（Windows py）：
py -c "import json;d=json.load(open('nsx.json'))['definitions'];print(list(d['VpcServiceGatewayConfig']['properties']))"
```
