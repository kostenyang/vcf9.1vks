# 05 — 實測執行紀錄（2026-06-08）

實際對 lab live API 跑過的結果（不是只有研究，是真的送/驗過）。

---

## DryRun（兩路線 payload 驗證，零風險）

### Path A — `Step1-Setup-DTGW.ps1 -DryRun`
- live 撈到 compute manager id = `f26a252e-1896-4788-94e4-e506c853104c`（kosten-vcf91-vc）
- live 撈到 overlay TZ = `nsx-overlay-transportzone`（`/infra/sites/default/enforcement-points/default/transport-zones/1b3a2f36-...`）
- 印出 external/private IP block、VNA cluster、VNA node、VPC profile 的 payload。
- VNA node 的 `cluster_or_resource_pool_id` / `datastore_id` / `network_id` 仍是 placeholder（要實際部 VM 才需填，見下方）。

### Path B — `Step1-Deploy-Edge.ps1 -DryRun`
- SDDC Manager token OK
- live 撈到 domain `vcf-m02` id=`047443ee-ae84-4b37-a2e3-8ca1a8f64144`
- live 撈到 cluster `vcf-m02-cl01` id=`65d2cc83-f61a-4042-a55c-d3528ad0e125`
- 印出 `POST /v1/edge-clusters` 完整 spec（2 台 MEDIUM edge、T0 ACTIVE_STANDBY、TEP VLAN 117、uplink VLAN 114）。

---

## 實際建立（低風險、可刪 — 已 PATCH 成功）

| 資源 | 值 | 狀態 |
|------|----|------|
| External IP Block | `vcf-m02-vks-ext-ipblock` = `192.168.114.128/26` (EXTERNAL) | ✅ 已建 |
| Private TGW Block | `vcf-m02-vks-priv-tgw` = `172.30.0.0/16` (PRIVATE) | ✅ 已建 |
| DTGW VPC Connectivity Profile | `vcf-m02-vks-vpc-profile`（ext + priv block，無 edge）| ✅ 已建 |

→ 這些讓 vCenter Supervisor wizard 的 Networking 步驟選得到 `vcf-m02-vks-vpc-profile`。

---

## 🐞 實測抓到的真 bug：external IP block /26 邊界

第一次用 `192.168.114.108/26` 被 NSX 退：

```
httpStatus: BAD_REQUEST  error_code: 520001
"Invalid CIDR 192.168.114.108/26 ... Network address should match corresponding prefix length."
```

**原因**：`/26` 的網段位址必須對齊 /26 邊界（`.0` / `.64` / `.128` / `.192`），`.108` 不是邊界。
**修正**：改 `192.168.114.128/26`（.128–.191，lab 內未用），通過。
→ 已回寫 `common/lab.ps1` 與所有文件。

> 教訓：external IP block 的 CIDR 一定要對齊 prefix 邊界；private TGW block `172.30.0.0/16` 本來就對齊所以沒事。

---

## Content Library（已建好，實測踩到 thumbprint 坑）

- 目標：subscribed library 訂 `https://wp-content.vmware.com/supervisor/v1/latest/lib.json`（Supervisor image 來源）。
- **第一次 API 失敗**：`RESOURCE_INACCESSIBLE / Connection to VCSP server failed` —— 誤判成 egress 不通。
- **真因**：REST API 建 subscribed library **沒帶 `ssl_thumbprint`**，vCenter 無法驗證對方憑證。
  UI 流程會跳「Security Alert」憑證信任視窗（按 Yes 即過）證明 **egress 其實是通的**。
- **修正**：腳本自動抓 SSL thumbprint（實測 `B6:49:37:52:8A:...`）塞進 spec → 成功。
- 結果：`tkg-content-library`（SUBSCRIBED）sync 後 **7 個 item**
  （`supervisor-9.0.0`/`9.0.2` OVF、`spherelet-v1.28`～`v1.32`）。
- 兩種方法都驗過：UI（5 步 wizard，按 YES 信任憑證）、Script（`Step1b-Create-ContentLibrary.ps1`，自動 thumbprint）。

詳見 [../common/content-library.md](../common/content-library.md)。

## VNA cluster 部署（DTGW 路線）— 實測 + 一個關鍵坑

- **UI 部署**：NSX Manager `System → Fabric → VNA Clusters → ADD CLUSTER` → node（compute manager/cluster/datastore/mgmt 下拉自動帶 moref）→ SAVE。
- **🐞 form factor 坑（你提醒抓到的）**：先選了 **Small** → 官方明文
  「The Medium form factor is the smallest size if you plan on enabling vSphere Supervisor」
  → **Small 不支援 Supervisor**，砍掉重部 **Medium**。
- **刪除留 orphaned VM**：in-progress 時刪 VNA cluster，NSX 移除 cluster 物件但**留下半部署的 VM**（PoweredOff），要手動 `Remove-VM` 清掉才能同名重建。
- **真實 node schema（部署後 GET 回來，補完 API 方法）**：
  ```
  vm_deployment_config: { compute_manager_id, cluster_or_resource_pool_id=domain-c9,
    datastore_id=datastore-15, reservation_info:{memory 100%, cpu HIGH_PRIORITY} }
  management_interface:
    network_id = dvportgroup-21          ← DVPG moref（不是 NSX segment）
    ip_assignment_specs = [{ ip_assignment_type: StaticIpv4,
      management_port_subnets:[{ip_addresses:[192.168.114.106], prefix_length:24}],
      default_gateway:[192.168.114.254] }]
  ```
  （原本反推用 StaticIpPoolSpec 是錯的；已回寫 `Step1-Setup-DTGW.ps1`。）
- **API 方法驗證**：用修正後的 `Step1-Setup-DTGW.ps1` 重建 Medium 成功 → API 方法端到端可用。
- 現狀：`vcf-m02-vna-01`（MEDIUM, VPC_SERVICES）部署中。

## Supervisor 啟用（DTGW + VNA，UI wizard，實測成功）

完整 DTGW 對外鏈（缺一不可，照順序）：
1. **VNA cluster**（Medium）部好。
2. **VPC profile.service_gateway**：`enable=true` + `edge_cluster_paths=[VNA path]` + `nat_config.enable_default_snat=true`。
3. **DistributedVlanConnection**（VLAN 114 + 上游 gateway `.254/24` + external IP block）。
4. **TransitGatewayAttachment**（default TGW → DVC）。←  少了這個，wizard 報「Transit Gateway Attachment does not exist」。

### 踩到的坑
- **vCenter compatibility 有快取**：補上 attachment 後，wizard 的 VPC profile 仍顯示「(incompatible)」，
  要等 vCenter wcp 服務 re-poll NSX（數分鐘）+ 重開 wizard 才會變相容。NSX 端 `state=REALIZED` 不代表 vCenter 立刻認。
- **CIDR overlap**：wizard 的 **Private (VPC) CIDRs** 預設會等於 Private TGW block（都 172.30.0.0/16）→ FINISH 被擋
  「Private CIDR overlaps with Private TGW IP Block」。要手動改成不重疊（本 lab 用 `172.28.0.0/16`）。
  三段最終：VPC private `172.28.0.0/16`、Service CIDR `172.29.0.0/16`、Private TGW `172.30.0.0/16`。
- wizard 的錯誤橫幅是**持久通知**（要按 X 關），改好後不會自動消失，別被它誤導。

### Supervisor wizard（VPC mode，7 步，實機驗證）
1. vCenter + Network → VCF Networking with VPC
2. Supervisor location → Cluster Deployment，name `vcf-m02-supervisor`，選 vcf-m02-cl01
3. Storage → 3 個都 `Management Storage Policy - Single Node`
4. Management Network → Static、PG `vcf-m02-cl01-vds01-pg-mgmt`、IP `192.168.114.101-105`、mask `/24`、gw `.254`、DNS/NTP `.200`、search `rtolab.local`
5. Workload Network → NSX Project `default` + VPC Profile `vcf-m02-vks-vpc-profile`、Private(VPC) CIDR `172.28.0.0/16`、Service CIDR `172.29.0.0/16`
6. Advanced → Control Plane Size Small
7. Review → FINISH → config_status **CONFIGURING → RUNNING**（30-60 分鐘）

> Tip：UI dropdown 用瀏覽器自動化時，Clarity combobox 用 form_input(ref) 設值最穩；
> Network/VPC-profile 這種要真的從清單點選或 form_input 才會註冊驗證。

## Namespace + VKS cluster（DTGW 路線，實測成功 2026-06-08）

Supervisor RUNNING（API endpoint `192.168.114.132`）後，實際建出 namespace 與 VKS guest cluster。

### Namespace `vks-automation`
- 建法：UI `Workload Management → Supervisor → Namespaces → New Namespace`（或 `Step3-New-Namespace.ps1`）。
- 配 storage policy `Management Storage Policy - Single Node` + access（administrator@vsphere.local EDIT）。
- ✅ **NSX VPC 自動建**：namespace RUNNING 後，NSX 在 default project 下自動生出該 namespace 的 VPC（用我們的 `vcf-m02-vks-vpc-profile`）→ 證明 DTGW 連線端到端通。
- VM classes（`best-effort-small` 2vCPU/4GB、`best-effort-medium` 2/8）+ storage classes（`management-storage-policy-*`）自動帶進 namespace。

### 🐞 真 bug：VKS cluster 要「兩個」content library，少一個就建不起來
第一次 `kubectl apply` cluster 被 admission webhook 退：
```
admission webhook "default.tkr-resolver.run.tanzu.vmware.com" denied the request:
Could not resolve KR/OSImage. Missing compatible KR/OSImage … osImageSelector: os-name=photon
```
**原因**：Supervisor 只掛了 **Supervisor image library**（`/supervisor/v1/latest/lib.json`，給 CP/spherelet），
**缺 TKG node-image library**（guest cluster 節點的 Photon/Ubuntu OVA 來源）。
**修正**：另建一個 subscribed library 指 `https://wp-content.vmware.com/v2/latest/lib.json`，
在 `Configure → Kubernetes Service → ADD` 指派給 Supervisor。sync 完（本 lab 123 items）後：
```
kubectl get kubernetesrelease -n vks-automation   # 出現 COMPATIBLE=True 的版本
kubectl get osimage          -n vks-automation   # 對應的 photon/ubuntu OVA（vmi-…）
```
> 兩個 library 並存時，cluster spec 的 `version:` 一定要對齊「COMPATIBLE=True 且有對應 photon osimage」的版本。
> 本 lab 實測：compatible KR = `v1.33.1` / `v1.34.2`；v1.34.2 有 photon osimage → 用 v1.34.2。

### cluster spec 對齊（實測可建的組合）
| 欄位 | 值 | 備註 |
|------|----|------|
| classRef | `builtin-generic-v3.6.0`（ns `vmware-system-vks-public`）| VKS 3.x ClusterClass |
| version | `v1.34.2` | 要對齊 compatible KR + 有 photon osimage |
| vmClass | `best-effort-small` | 用 namespace 內實際有的 class（不是猜的 guaranteed-small）|
| storageClass | `management-storage-policy-single-node` | |
| CP / worker | 1 / 1 | nested 資源有限，先各 1 台 |

→ `kubectl apply -f common/vks-cluster.yaml` 通過，cluster `vks-auto-01` 進 Provisioning：
`cluster` PHASE=Provisioned、2 個 machine（CP + node-pool worker）開始部 VM。

### 🐞 真 bug：pod CIDR `192.168.0.0/16` 撞 lab 管理網段 → CP 永遠 not Ready（remediation loop）
第一次用預設 pod CIDR `192.168.0.0/16`：CP VM 部好、PoweredOn、拿到 VPC IP `172.28.0.2`、
`InfrastructureReady=True`，但 **kubeadm init 一直不完成**（KCP `Initialized=False / Control plane not yet initialized`）。
~90 分鐘後 MachineHealthCheck 判 `MachineMarkedUnhealthy` → 砍掉 CP machine（vCenter 看到 "Power Off / Delete virtual machine"）→ 重建 → 又卡 → **無限 remediation loop**。

**根因**：guest cluster pod CIDR **`192.168.0.0/16` 涵蓋了 lab 管理網段 `192.168.114.0/24`**——
而 `192.168.114.x` 上有 **Supervisor API `.132`、DNS/NTP `.200`、gateway `.254`**。
node 起 Antrea/CNI 後把 `192.168.0.0/16` 灌進 pod overlay 路由，去 `192.168.114.x`（DNS/registry/Supervisor）
的流量被導進 overlay → 解不到 DNS、拉不到 image、連不到 Supervisor → node 永遠 not Ready。

**修正**：pod CIDR 改 **`100.96.0.0/11`**（不撞管理網段 192.168.114、不撞 VPC 172.28/29/30、不撞 service 10.96/12）。
CIDR 是 immutable → **刪掉 cluster 重建**。重建後 CP VM 因 image cache 已暖、數分鐘就 PoweredOn。
→ 已回寫 `common/vks-cluster.yaml`（含註解警告）。

> 教訓：VKS guest cluster 的 **pod / service CIDR 一定要避開 node 實際要連的網段**
> （管理網 192.168.114.0/24 + VPC 172.28/29/30）。預設 Calico pod CIDR `192.168.0.0/16` 在
> 用 192.168.x 管理網的 lab 幾乎必撞，是經典坑。

### 🐞 第二個坑：nested 太慢，MHC `nodeStartupTimeout=3600s` 在 CP init 完成前把它砍掉
改完 pod CIDR 重建後，CP VM 起來、拿到 IP `172.28.0.34`、**egress 完全正常**
（NSX SNAT 統計實測：node 送了 99,960 封包 / 144MB 出去拉 image；從 host ping SNAT IP `.134` 也通），
但 image 拉完後 **etcd/apiserver 在 nested best-effort CPU 上 bootstrap 太慢**，apiserver(6443) 一直沒起來。
預設 control-plane MHC `nodeStartupTimeoutSeconds=3600`（60min）會在它 converge 前判不健康 → 又砍 → loop。

- 本 lab **沒有任何 guaranteed vmclass**（只有 `best-effort-small/medium`）→ 沒法給 guest CP 保留 CPU。
- 直接 patch MHC 物件被擋：`User ... cannot patch resource "machinehealthchecks"`（VKS RBAC）。
- 設 Machine annotation `skip-remediation` 也被擋：「can only modify the 'remediate-machine' annotation」。

**修正**：從 **cluster topology 覆寫** MHC（不用直接 patch MHC 物件）：
```yaml
spec:
  topology:
    controlPlane:
      replicas: 1
      healthCheck:
        checks:
          nodeStartupTimeoutSeconds: 14400   # 4h，給慢的 nested CP 足夠時間
```
> 欄位名是 `healthCheck`（不是 machineHealthCheck），CAPI `v1beta2`。
> 套用後 `kubectl get mhc` 的 control-plane MHC = `14400s`，worker 仍預設 3600s。

### ✅ 最終結果：VKS cluster 起來了（2026-06-08）
pod CIDR `100.96.0.0/11` + MHC 4h 重建後，**~36 分鐘 CP converge**：
```
NAME                        STATUS   ROLES           VERSION
vks-auto-01-7f6ms-fmgz9     Ready    control-plane   v1.34.2+vmware.2   (172.28.0.2, Photon OS, containerd 2.1.5-fips)
vks-auto-01-node-pool-1-... Ready    <none>          v1.34.2+vmware.2   (172.28.0.3)
```
- KCP `Initialized=true / Available=true`；cluster `CP AVAILABLE=1 / W AVAILABLE=1`。
- guest cluster 20 個 system pod 全 Running。
- kubeconfig：`kubectl-vsphere login --server=192.168.114.132 --tanzu-kubernetes-cluster-name=vks-auto-01 --tanzu-kubernetes-cluster-namespace=vks-automation`
  → `kubectl config view --flatten --minify --context=vks-auto-01 > vks-auto-01.kubeconfig`。

> 之前 90min「失敗」其實是 **慢到被 MHC 提早砍**，不是配置死結。兩個修正（CIDR + MHC）一起才過。

> kubectl + kubectl-vsphere plugin 來源：`https://<sup-vip>/wcp/plugin/windows-amd64/vsphere-plugin.zip`。
> 登入：`kubectl vsphere login --server=192.168.114.132 -u administrator@vsphere.local --insecure-skip-tls-verify`。

---

## 尚未執行（重部署，等決定）

| 動作 | 原因 |
|------|------|
| Edge cluster 實際部署（Path B）| 部 2 台 edge VM、30–60 分鐘、吃 nested 資源；且與 Path A 共用 default project TGW（互斥）|

> 兩條重部署互斥（同一個 default project 只有一個 TGW）。要兩條都實測，建議：
> 先完整跑 A → 截圖/驗證 → 清掉 → 再跑 B；或 Path B 另開 NSX Project。
