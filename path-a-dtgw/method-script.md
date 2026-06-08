# Path A — Script 方法（PowerCLI + REST 混合）

PowerCLI 對 NSX VPC / VNA **沒有原生 cmdlet**，所以 DTGW 路線的 NSX 設定仍走 REST
（即 [`Step1-Setup-DTGW.ps1`](Step1-Setup-DTGW.ps1)）。PowerCLI 在這條路的角色是：
**取得 NSX REST 需要的 moref（cluster / datastore / portgroup）**，以及啟用 Supervisor 時的物件驗證。

---

## 用 PowerCLI 取 moref（回填 Step1 的 placeholder）

```powershell
Import-Module VMware.VimAutomation.Core
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session
Connect-VIServer 192.168.114.11 -User administrator@vsphere.local -Password 'VMware1!VMware1!'

# cluster moref（填 vm_deployment_config.cluster_or_resource_pool_id）
(Get-Cluster 'vcf-m02-cl01').ExtensionData.MoRef.Value          # e.g. domain-cXX

# datastore moref（填 datastore_id）
(Get-Datastore | ? Name -match 'vsan' | select -First 1).ExtensionData.MoRef.Value   # e.g. datastore-XX

# mgmt portgroup id（填 management_interface.network_id）
Get-VDPortgroup | ? { $_.VlanConfiguration.VlanId -eq 114 } | select Name,Id
```

把這三個值填回 `Step1-Setup-DTGW.ps1` 的：
- `cluster_or_resource_pool_id = '<CLUSTER_OR_RP_MOREF>'`
- `datastore_id = '<DATASTORE_MOREF>'`
- `network_id = '<MGMT_PORTGROUP_ID>'`

然後正式跑（去掉 -DryRun）。

---

## 啟用 Supervisor（PowerCLI 角度）

`Enable-WMCluster` 目前不支援 NSX VPC（沒有 `-NsxVpcConnectivityProfile` 之類參數），
所以啟用 Supervisor 仍用 REST：[`../common/Step2-Enable-Supervisor.ps1`](../common/Step2-Enable-Supervisor.ps1)。

PowerCLI 可先驗證環境物件存在：
```powershell
Get-Cluster 'vcf-m02-cl01'
Get-SpbmStoragePolicy | ? Name -match 'Single Node'
Get-ContentLibrary | ? Name -match 'tkg|tanzu|kubernetes'
```

---

## 為什麼不是純 PowerCLI

| 步驟 | PowerCLI 支援？ |
|------|----------------|
| External/Private IP block | ❌（NSX REST）|
| VNA cluster | ❌（NSX REST）|
| VPC Connectivity Profile | ❌（NSX REST）|
| Enable Supervisor (VPC mode) | ❌（vCenter REST；Enable-WMCluster 只支援 classic NSX/vDS）|
| 取 moref / 物件驗證 | ✅ |
| 建 VKS cluster | 用 kubectl（非 PowerCLI）|

→ DTGW 路線的「script 方法」= PowerCLI 取值 + REST 自動化。完整自動化見 `Step1-Setup-DTGW.ps1` + `../common/Step2`。
