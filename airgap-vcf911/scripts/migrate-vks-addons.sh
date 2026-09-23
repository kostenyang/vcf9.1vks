#!/bin/bash
# 把 VKS Standard Packages 的 OCI bundle 搬進 VCF Software Depot 的 OCI registry
# 依賴:imgpkg、python3、官方 oci_image_depot_migrator.py
#   https://github.com/vmware/vsphere-supervisor/blob/main/airgapped/scripts/oci_image_depot_migrator.py
# 版本從 guest cluster 內建那個失敗的 PackageRepository 取得:
#   kubectl get pkgr -n vmware-system-tkg -o jsonpath='{.items[0].spec.fetch.imgpkgBundle.image}'
set -u
VER=${1:?例如 3.7.0-20260618}
DEPOT=${2:?例如 vcf-m02-fleet01.home.lab}
SRC="projects.packages.broadcom.com/vsphere/supervisor/vks-standard-packages/${VER}/vks-addons:${VER}"

echo "== 目標 repo"
python oci_image_depot_migrator.py map-target-repo -s "$SRC" -t "$DEPOT"

echo "== 搬移(有網的 Bastion 可以一次 copy;跨氣隙請改用 download / upload 兩段)"
python oci_image_depot_migrator.py copy -s "$SRC" -t "$DEPOT" --work-dir .

echo "== 驗證"
curl -sk "https://${DEPOT}/v2/_catalog"
