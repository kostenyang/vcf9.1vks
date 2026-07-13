# VCF 9.1 VKS air-gap：官方下載清單

來源：[VMware vSphere Supervisor — VKS Deployment Guide for VCF 9.1.0 air-gapped environments](https://github.com/vmware/vsphere-supervisor/blob/main/airgapped/air-gapped-vcf91.md)

這份清單只回答「外網 Bastion 要先抓哪些東西」。版本號是官方文件目前的 VCF 9.1
範例；真正下載前仍須用 Broadcom Support Portal entitlement與互通矩陣確認。

## 必抓：建立基本 VKS cluster

### 1. VMware Kubernetes Release（VKr）OVA

- 來源：`https://wp-content.broadcom.com/v2/latest/`
- VCF 9.1隨附版本：Kubernetes `1.34.2`
- 官方建議：下載三個或以上近期、相容的 VKr版本。
- 每個版本須帶齊官方 Content Library匯入程序要求的 OVA/metadata檔案；不可只複製另一個
  Content Library item，否則可能保留錯誤 metadata。

VKr是 VKS control-plane/worker VM映像。沒有它，即使 Supervisor與 VKS Service都正常，也
無法建立 guest cluster。

### 2. VCF Consumption CLI 9.1.0

Broadcom Support Portal → My Downloads → 搜尋 `VCF consumption CLI`：

- `VCF-Consumption-CLI-Linux_AMD64-9.1.0.tar.gz`
- 對應 Admin Host作業系統/架構的 CLI tar（若不是 Linux AMD64）。

### 3. VCF CLI Plugin Bundle 9.1.0

- `VCF-Consumption-CLI-PluginBundle-Linux_AMD64-9.1.0.<build>.tar.gz`
- 至少需要 `cluster`、`addon`、`imgpkg` 等與 VKS流程有關的 plugin；離線端可直接
  `vcf plugin install all --local-source <dir>`。

VCF 9.1使用 VCF CLI；舊 `kubectl-vsphere` plugin已 deprecated。

### 4. VKS Service（Core Supervisor Service）

Broadcom Support Portal → My Downloads → `vSphere Supervisor Services`：

- VKS Service package YAML：同一版本的 `legacy` 與 `depot` variants。
- `legacy` YAML只用來取得：
  `spec.template.spec.fetch[].imgpkgBundle.image`
- `depot` YAML用來在 VCF 9.1 Software Depot流程註冊/安裝服務。
- 對 legacy YAML中的 OCI image執行官方 migrator `download`，產生 bundle tar。

官方 guide的版本資訊有時間差：BOM列 `3.6.1`，後文要求下載當時最新 `3.6.3`。實作時
不要混用；以 Portal中同一組 YAML、OCI tag與 vSphere/VKS互通結果為準。

### 5. 官方 migration scripts與基礎工具

要搬 OCI bundles，Bastion與 Admin Host需準備：

- [`oci_image_depot_migrator.py`](https://github.com/vmware/vsphere-supervisor/blob/main/airgapped/scripts/oci_image_depot_migrator.py)
- `toggle_software_depot_oci_image_upload.sh`
- Python 3
- `imgpkg`
- `wget`, `curl`, `ssh`, `sshpass`, `docker`, `jq`, `yq`, `openssl`

Admin Host另需預留約 150–200 GB可用空間。

## 要裝 add-ons 才抓：VKS Standard Packages

這是 cert-manager、Contour、Prometheus、Grafana等標準套件的集合；建立一個沒有這些
add-ons的基本 VKS cluster時，它不是 VKr的替代品。

官方範例 bundle：

```text
projects.packages.broadcom.com/vsphere/supervisor/vks-standard-packages/
3.6.0-20260211/vks-standard-packages:3.6.0-20260211
```

下載：

```bash
./oci_image_depot_migrator.py download \
  -s projects.packages.broadcom.com/vsphere/supervisor/vks-standard-packages/3.6.0-20260211/vks-standard-packages:3.6.0-20260211
```

輸出範例：`vks-standard-packages-3.6.0-20260211.tar`。

## 依需求才抓：其他 Supervisor Services

每個要安裝的服務都需下載該版本的：

1. `legacy` YAML
2. `depot` YAML
3. legacy YAML所指向的 OCI bundle tar

官方文件列出的範例版本：

| Service | Type | 官方文件範例版本 | 是否基本 VKS必需 |
|---|---|---:|---|
| VKS Service | Core | 3.6.3 | 是 |
| ArgoCD | Standard | 1.1.0 | 否 |
| CA Cluster Issuer | Standard | 0.0.2 | 否 |
| Consumption Interface | Standard | 9.1.0 | VCFA/CCI情境 |
| Contour | Standard | 1.33.1 | 否 |
| ExternalDNS | Standard | 0.18.0 | 否 |
| Harbor | Standard | 2.14.2 | 視 VCFA情境 |
| Metrics Aggregator | Standard | 0.1.0 | 否 |
| Supervisor Management Proxy | Standard | 0.4.1 | 特定 Depot/Harbor流程 |

### Harbor判斷

- 有 VCF Automation：依官方 `Using Harbor as a VCF service`流程，不要先假設必須手工部署
  Harbor Supervisor Service。
- 沒有 VCF Automation（或 VVF）：另抓 Harbor的 legacy/depot YAML與 OCI bundle：

```text
projects.packages.broadcom.com/vsphere/supervisor/harbor-service/2.14.2/
harbor:v2.14.2_vmware.2-vks.1
```

## 搬入 air-gap的最終 inventory

- [ ] 三個或以上相容 VKr版本的 OVA/metadata檔案
- [ ] VCF Consumption CLI 9.1.0 tar
- [ ] VCF CLI Plugin Bundle 9.1.0 tar
- [ ] VKS Service legacy YAML
- [ ] VKS Service depot YAML
- [ ] VKS Service OCI bundle tar
- [ ] `oci_image_depot_migrator.py`
- [ ] `toggle_software_depot_oci_image_upload.sh`
- [ ] `imgpkg`及其他必要工具的離線安裝檔
- [ ] VKS Standard Packages tar（要裝 standard add-ons時）
- [ ] 每個額外 Supervisor Service的 legacy YAML、depot YAML、OCI tar
- [ ] vCenter trusted root CA與 Software Depot CA

## 官方安裝順序

1. 在 air-gap vCenter啟用 Supervisor。
2. 建 Local Content Library並匯入 VKr。
3. 建 vSphere Namespace。
4. 在 Admin Host安裝 VCF CLI/plugins、kubectl與 CA trust。
5. 用官方 toggle script暫時設定 `offlineWriteEnabled=true`。
6. 用 migrator把 VKS Service、選用 Supervisor Services與 Standard Packages上傳 Software Depot。
7. 立即用 toggle script設定 `offlineWriteEnabled=false`；官方指出 upload模式沒有 auth gate。
8. 安裝/升級 VKS Service，確認 `KubernetesRelease`與 `OSImage` compatible。
9. 部署 VKS cluster。
10. 最後才安裝需要的 VKS Standard Packages。

VCFA環境中的 Harbor/CCI應依 VCF service流程接入；不要修改或重啟 VCFA/VSP內部 Kubernetes
元件來「測試」user VKS air-gap套件。
