# API 方法 — 起 VKS（raw REST / curl）

語言無關的「純 API」流程：vCenter REST（`/api`）、NSX Policy（`/policy/api/v1`）、
Supervisor kube API（建 Cluster CR）。對應 PowerShell（`common/`）與 Python（`python/`）。

> Lab 值：vCenter `192.168.114.11`、NSX `192.168.114.13`、Supervisor API `192.168.114.132`，
> 帳密 `administrator@vsphere.local` / `admin` ＋ `VMware1!VMware1!`（lab）。

## 0. 認證 token
```bash
# vCenter session id
SID=$(curl -sk -u 'administrator@vsphere.local:VMware1!VMware1!' -X POST \
  https://192.168.114.11/api/session | tr -d '"')
VC=(-sk -H "vmware-api-session-id: $SID" -H "Content-Type: application/json")

# NSX 用 basic auth
NSX=(-sk -u 'admin:VMware1!VMware1!' -H "Content-Type: application/json")
```

## 1. NSX：IP blocks + VPC connectivity profile（DTGW）
```bash
# external block（EXTERNAL，/26 對齊邊界）
curl "${NSX[@]}" -X PATCH https://192.168.114.13/policy/api/v1/infra/ip-blocks/vcf-m02-vks-ext-ipblock \
  -d '{"resource_type":"IpAddressBlock","cidr":"192.168.114.128/26","visibility":"EXTERNAL"}'
# private TGW block（PRIVATE，/16）
curl "${NSX[@]}" -X PATCH https://192.168.114.13/policy/api/v1/infra/ip-blocks/vcf-m02-vks-priv-tgw \
  -d '{"resource_type":"IpAddressBlock","cidr":"172.30.0.0/16","visibility":"PRIVATE"}'
# VPC connectivity profile（DTGW：VNA path 放 service_gateway.edge_cluster_paths + nat enable_default_snat）
curl "${NSX[@]}" -X PATCH \
  https://192.168.114.13/policy/api/v1/orgs/default/projects/default/vpc-connectivity-profiles/vcf-m02-vks-vpc-profile \
  -d '{"resource_type":"VpcConnectivityProfile",
       "transit_gateway_path":"/orgs/default/projects/default/transit-gateways/default",
       "external_ip_blocks":["/infra/ip-blocks/vcf-m02-vks-ext-ipblock"],
       "private_tgw_ip_blocks":["/infra/ip-blocks/vcf-m02-vks-priv-tgw"]}'
```
> VNA cluster + 節點（要 compute moref）+ DistributedVlanConnection + TransitGatewayAttachment：見 `research/04-nsx-schemas.md`。

## 2. 啟用 Supervisor（VPC mode）
```bash
# 查既有（注意：GET /supervisors 回 404，要用 /summaries）
curl "${VC[@]}" https://192.168.114.11/api/vcenter/namespace-management/supervisors/summaries
# 啟用（完整 body 見 python/step2 或 common/Step2；POST 後輪詢 summaries.config_status → RUNNING）
curl "${VC[@]}" -X POST https://192.168.114.11/api/vcenter/namespace-management/supervisors -d @supervisor-spec.json
```

## 3. 建 namespace
```bash
curl "${VC[@]}" -X POST https://192.168.114.11/api/vcenter/namespaces/instances -d '{
  "namespace":"vks-automation",
  "supervisor":"<supervisor-id from summaries>",
  "storage_specs":[{"policy":"<single-node-policy-id>","limit":204800}],
  "access_list":[{"subject_name":"administrator","subject_type":"USER","domain":"vsphere.local","role":"EDIT"}]
}'
```

## 4. 建 VKS guest cluster（Cluster CR → Supervisor kube API）
先用 vSphere plugin 登入取 token（純 REST 登入流程複雜，建議用 `kubectl-vsphere login`）：
```bash
kubectl-vsphere login --server=192.168.114.132 -u administrator@vsphere.local \
  --insecure-skip-tls-verify
kubectl config use-context vks-automation
```
再 apply Cluster CR（YAML = `common/vks-cluster.yaml`；或直接打 kube API）：
```bash
TOKEN=$(kubectl config view --raw -o jsonpath='{.users[?(@.name=="wcp:192.168.114.132:administrator@vsphere.local")].user.token}')
curl -sk -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/yaml" \
  -X POST "https://192.168.114.132:6443/apis/cluster.x-k8s.io/v1beta2/namespaces/vks-automation/clusters" \
  --data-binary @common/vks-cluster.yaml
```

## 兩個必備修正（否則建不起來 / 起不來）
- **兩個 content library**：Supervisor image（`/supervisor/v1/latest/lib.json`）＋ TKG node-image（`/v2/latest/lib.json`）。少 node-image → `tkr-resolver` 退「Could not resolve KR/OSImage」。
- **pod CIDR** 用 `100.96.0.0/11`（**別用預設 `192.168.0.0/16`**，會撞管理網段 192.168.114.0/24）。
- **MHC** 從 `spec.topology.controlPlane.healthCheck.checks.nodeStartupTimeoutSeconds` 拉長（nested 慢，預設 3600s 會提早砍 CP）。

詳見 `research/05-test-execution.md`（全部實測踩坑紀錄）。
