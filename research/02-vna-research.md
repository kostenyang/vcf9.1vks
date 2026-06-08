# 02 — VNA Cluster 部署研究（DTGW 路線）

VNA (Virtual Network Appliance) cluster 是 VCF 9.1 新東西，給 DTGW 補上 stateful 服務
（SNAT/DNAT、N:1 outbound NAT、1:1 External IP NAT、DHCP、**L4 Load Balancer**），
讓 Supervisor/VKS 能在沒有 NSX Edge 的情況下拿到 LB。

VNA 本質是「精簡版 NSX Edge appliance」，但不用自己的 TEP/overlay —— 它騎在 host TEP 上。

---

## API 端點（從 lab live 確認）

```
GET  /policy/api/v1/infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters
PUT  /policy/api/v1/infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters/{cluster-id}
PATCH (同路徑)
```

VNA 節點是 cluster 的 child：
```
.../virtual-network-appliance-clusters/{cluster-id}/virtual-network-appliances/{node-id}
```

per-VPC 重新配置 / 指定 VNA 節點（已知唯一公開的 VNA 操作 API）：
```
POST /policy/api/v1/infra/gateways/action/reallocate
{ "gateway_path": "/orgs/default/projects/default/vpcs/<vpc>" }
```

per-VPC 開 Load Balancer（UI 沒這個 toggle，只能 API）：
```
PUT /policy/api/v1/orgs/default/projects/<project>/vpcs/<vpc>/vpc-lbs/<lb>
{ "resource_type": "LBService", "enabled": true, "size": "SMALL" }
```

---

## 真實 Schema（從 lab NSX 9.1 OpenAPI 撈，見 [04-nsx-schemas.md](04-nsx-schemas.md)）

### VirtualNetworkApplianceCluster
```
display_name            string
appliance_form_factor   enum: SMALL | MEDIUM | LARGE | XLARGE
appliance_type          enum: VirtualNetworkAppliance
service_type            enum: VPC_SERVICES | ROUTE_CONTROLLER
advanced_configuration  { overlay_transport_zone_path, high_availability_profile }
members                 [ { edge_transport_node_path, appliance_path, appliance_unique_id } ]
```

### VirtualNetworkAppliance（節點，cluster 的 child）
```
hostname               string  REQ
vm_deployment_config   REQ  -> VirtualNetworkApplianceDeploymentConfig
management_interface   REQ  -> VirtualNetworkApplianceManagementInterface
credentials                 -> VirtualNetworkApplianceCredential
failure_domain_path    string
```

### VirtualNetworkApplianceDeploymentConfig
```
compute_manager_id          string  REQ   ← vCenter (compute manager) id
cluster_or_resource_pool_id string  REQ   ← 部署目標 cluster/RP
datastore_id                string  REQ
reservation_info            { memory_reservation, cpu_reservation }
```

### VirtualNetworkApplianceManagementInterface
```
network_id           string  REQ          ← mgmt port group / segment id
ip_assignment_specs  [PolicyIpAssignmentSpec]  REQ   ← static IP / DHCP
```

### VirtualNetworkApplianceCredential
```
cli_username / cli_password / root_password / audit_username / audit_password
```

> ⚠️ 官方未公開 VNA create 的完整 JSON 範例；以上欄位是 lab 自身 OpenAPI spec 的真實定義。
> 實際送出前建議先 UI 部一台、`GET` 回來對照。

---

## 部署順序（DTGW + VNA）

1. **External IP Block**（infra-level，給 VPC 配 public/LB/SNAT IP）
   ```
   PATCH /policy/api/v1/infra/ip-blocks/{id}
   { "resource_type":"IpAddressBlock", "cidr":"192.168.114.108/26", "visibility":"EXTERNAL" }
   ```

2. **VNA cluster + node**（PUT cluster，再 PUT node 為 child）
   - form factor：lab 用 SMALL/MEDIUM
   - service_type：`VPC_SERVICES`
   - node 的 deployment config 指向 vCenter compute manager + cluster + datastore + mgmt PG

3. **把 VNA 接上 VPC Connectivity Profile**（透過 Distributed VLAN Connection）
   - external connection（VLAN + gateway CIDR）
   - 綁 external IP block + VNA cluster
   - 開 **default outbound NAT**（這步開啟 DTGW 的 SNAT）

4. **啟用 Supervisor**（networking 選 "VCF Networking with VPC"，指向 default project + 該 profile）

5. **per-VPC 開 LB**（Supervisor 建好 namespace VPC 後，`vpc-lbs` PUT enabled=true）

---

## UI 路徑

- VNA cluster：NSX Manager `System → Fabric → VNA Cluster`，或 vCenter `Configure → Networking → VNA Clusters`
  - 4 步：建 cluster（名稱+form factor）→ ADD 第一台（FQDN/compute manager/cluster/datastore/PG/mgmt IP）→ CLONE 第二台（只填 FQDN+IP）→ 部署
- DTGW external connection：vCenter `Network → Network Connectivity → Distributed Connectivity`
  - 填 VLAN、gateway CIDR、external IP block、private TGW block → 選 Distributed VLAN Connection → 綁 VNA cluster + 開 default outbound NAT

---

## 限制 / 注意

- VNA cluster ≥2 節點才有 HA（active/standby；**不支援 active/active**）。
- 每個用到 stateful 服務的 VPC 會在 VNA 上自動建一個 service instance。
- 若 VNA 是 VCF Installer Day-1 部的，mgmt 網路被鎖死不能選 PG；要彈性 Day-2 部署，VCF 安裝時要先啟用 "Centralized Gateway"。
- VNA 不用自己的 TEP，騎 host TEP；四個 fastpath 介面接 auto-created 的 overlay GENEVE-trunk segment。

---

## 來源

- VCF 9.1 blog（services 清單）: https://blogs.vmware.com/cloud-foundation/2026/05/05/simplify-workload-connectivity-and-enhance-network-scale-and-performance-with-vcf-9-1/
- sdn-warrior VNA + VPCs: https://sdn-warrior.org/posts/vcf9.1-vna-vpc/
- sdn-warrior VNA part 2（架構、reallocate API）: https://sdn-warrior.org/posts/vcf9.1-vna-part2/
- Broadcom TechDocs VNA Cluster Models: https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/design/vmware-cloud-foundation-concepts/nsx-virtual-network-appliance-cluster-models.html
- BlanketVM VPC + DTGW: https://blanketvm.com/2025/08/11/vcf-9-deployment-part10-vpc-distributed-transit-gateway/
- vStellar VKS with NSX VPCs（vpc-lbs PUT）: https://vstellar.com/2025/08/vcf-9-part-10-deploy-vks-with-nsx-vpcs/
- **權威 schema**：lab 自身 `GET /policy/api/v1/spec/openapi/nsx_policy_api.json`
