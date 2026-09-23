# VCF 9.1 VKS air-gap toolkit

這個目錄補上本 repo 原本「連網環境啟用 VKS」之外的離線供應鏈流程。VCF 9.1 使用
**VCF Software Depot 內建 OCI registry**；不要套用 pre-9.1 教學中外接 Harbor + Tanzu CLI 的做法。

官方主流程：<https://github.com/vmware/vsphere-supervisor/blob/main/airgapped/air-gapped-vcf91.md>

先看「到底要抓哪些離線檔案」：[`OFFICIAL-DOWNLOAD-CHECKLIST.md`](OFFICIAL-DOWNLOAD-CHECKLIST.md)。

## 安全界線

- `airgap_tool.py` 是唯讀規劃／檢查工具，不會修改 vCenter、Supervisor 或 Depot。
- 設定檔禁止 `password`、`token`、`secret`、`username` 等 credential 欄位。
- Registry login 請在執行環境用 `docker login` / credential helper 完成，不要將認證放入 Git。
- `config.example.json` 的版本是官方 VCF 9.1 guide 範例，實作前須以 Broadcom Support Portal
  中實際 entitlement 與互通矩陣為準。

## 1. 準備設定

```bash
cd airgap
cp config.example.json config.json
# 修改 Depot、vCenter、Supervisor FQDN，以及真正要搬的 bundle source
python3 airgap_tool.py --config config.json validate
```

`config.json` 已由根目錄 `.gitignore` 排除，避免誤提交 lab-specific 資訊。

## 2. Bastion：產生下載命令

先從官方 guide 取得 `oci_image_depot_migrator.py`，並安裝 Python 3 與 `imgpkg`：

```bash
python3 airgap_tool.py --config config.json plan download > download-plan.sh
sh download-plan.sh
```

另需從 Broadcom Support Portal 帶入：

1. VCF Consumption CLI 9.1.0 與 Linux plugin bundle。
2. VKS Service 的 `legacy` 與 `depot` YAML。
3. 所需 Supervisor Services 的 `legacy` 與 `depot` YAML。
4. VKR OVA（VCF 9.1 初始版本通常為 Kubernetes 1.34.2；仍須確認相容性）。

`legacy` YAML 只用來找 `spec.template.spec.fetch[].imgpkgBundle.image`；真正向 VCF 9.1
Supervisor 註冊時使用 `depot` YAML。

## 3. 離線搬運

把下列內容從 Bastion 搬到 air-gap Admin Host：

- OCI bundle tar files
- `oci_image_depot_migrator.py`
- VCF CLI / plugin bundle
- Supervisor Service YAML files
- VKR OVA files
- Depot CA certificate（若使用私有 CA）

建議 Admin Host 至少 2 vCPU、4 GB RAM、150–200 GB 可用空間。

## 4. Admin Host：preflight 與上傳

```bash
python3 airgap_tool.py --config config.json check
python3 airgap_tool.py --config config.json plan upload > upload-plan.sh
sh upload-plan.sh
```

`check` 驗證：

- `python3`、`imgpkg` 是否存在。
- Admin Host 能否解析並連到 Depot、vCenter、Supervisor TCP/443。
- `https://<depot>/v2/` 是否回覆 OCI registry 合理狀態（HTTP 200 或未認證的 401）。
- TLS 若失敗會直接列為 FAIL；請安裝正確 CA，不提供 insecure bypass。

## 5. 平台啟用順序

1. 依本 repo `path-a-dtgw/` 或 `path-b-edge/` 啟用 Supervisor networking。
2. 建立 **Local Content Library**，依官方 air-gap 程序匯入 VKR；不要 clone 既有 library items。
3. 建立 vSphere Namespace，設定 storage policy、VM classes、權限及 registry CA trust。
4. 將 VKS Service 與 Supervisor Service OCI bundles 上傳 Software Depot。
5. 使用對應的 `depot` YAML 註冊／升級 VKS Service。
6. 確認 `KubernetesRelease` 與 `OSImage` 都存在且 compatible，再套用 `common/vks-cluster.yaml`。
7. 視需要由 Depot 安裝 VKS Standard Packages。

## 6. 驗證

```bash
python3 -m unittest -v test_airgap_tool.py

vcf version
vcf plugin list
kubectl get kubernetesrelease -A
kubectl get osimage -A
kubectl get cluster,machine,kubeadmcontrolplane -A
```

若 workload image pull 仍指向 `projects.packages.broadcom.com`，表示 OCI relocation 或 depot
mapping 尚未完成。正常 air-gap 資料路徑應只連 Software Depot FQDN。
