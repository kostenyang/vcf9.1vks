<#  Step4 — 建 VKS cluster + 下載 kubeconfig（兩路線共用）
    kubectl + ClusterClass YAML (builtin-generic-v3.6.0)。
    前置：namespace $NS_NAME RUNNING。 #>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lab.ps1"

# 實測值（2026-06-08）：Supervisor API endpoint 是 wizard 配的 CP VIP，不是 $CP_START_IP。
# 啟用後 GET /api/vcenter/namespace-management/supervisors/summaries 的 .api_server 確認；本 lab = 192.168.114.132。
$supVip = $SUP_API_VIP          # 見 lab.ps1；若空則 fallback $CP_START_IP
if (-not $supVip) { $supVip = $CP_START_IP }
# k8s 版本 / vmClass 由 vks-cluster.yaml 控制（此處僅註記實測可用組合）。
# 實測：builtin-generic-v3.6.0 + version v1.34.2 + vmClass best-effort-small（namespace 內有的 class）。
$kubeconfig = "$HOME\.kube\$VKS_CLUSTER.yaml"

# ⚠️ 前置（實測踩到）：Supervisor 要掛「兩個」content library 才建得起 VKS cluster：
#   1) Supervisor image library  — https://wp-content.vmware.com/supervisor/v1/latest/lib.json
#   2) TKG node-image library(v2) — https://wp-content.vmware.com/v2/latest/lib.json
#      ↑ 少了它 → kubectl apply 被 tkr-resolver webhook 退：
#        「Could not resolve KR/OSImage … osImageSelector: os-name=photon」
#      在 vCenter → Workload Management → Supervisor → Configure → Kubernetes Service 指派該 library。
#      sync 完 kubectl get kubernetesrelease/osimage 會出現 COMPATIBLE=True 的版本，cluster yaml 的 version 要對齊。

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "✗ kubectl 未安裝。下載 vsphere plugin：" -ForegroundColor Red
    Write-Host "  https://$supVip/wcp/plugin/windows-amd64/vsphere-plugin.zip" -ForegroundColor Yellow
    exit 1
}

Write-Host "=== 登入 Supervisor ($supVip) ===" -ForegroundColor Cyan
kubectl vsphere login --server=$supVip --vsphere-username=$VCUSER --vsphere-password=$VCPASS --insecure-skip-tls-verify 2>&1 | Write-Host
kubectl config use-context $NS_NAME

Write-Host "=== ClusterClass / VM classes ===" -ForegroundColor Cyan
kubectl get clusterclasses -n vmware-system-vks-public 2>&1 | Write-Host
kubectl get vmclasses 2>&1 | Write-Host

$yaml = "$PSScriptRoot\..\common\vks-cluster.yaml"
Write-Host "=== 套用 $yaml ===" -ForegroundColor Cyan
if ((kubectl get cluster $VKS_CLUSTER -n $NS_NAME --ignore-not-found 2>&1) -match $VKS_CLUSTER) {
    Write-Host "  cluster '$VKS_CLUSTER' 已存在，跳過建立。" -ForegroundColor Green
} else {
    kubectl apply -f $yaml 2>&1 | Write-Host
}

Write-Host "=== 等候 Ready（最多 30 分鐘）===" -ForegroundColor Cyan
$deadline=(Get-Date).AddMinutes(30)
do {
    Start-Sleep 60
    $phase = kubectl get cluster $VKS_CLUSTER -n $NS_NAME -o jsonpath='{.status.phase}' 2>&1
    $cpr   = kubectl get cluster $VKS_CLUSTER -n $NS_NAME -o jsonpath='{.status.controlPlaneReady}' 2>&1
    Write-Host "  [$(Get-Date -Format HH:mm:ss)] phase=$phase cpReady=$cpr"
    if ($phase -eq 'Provisioned' -and $cpr -eq 'true') { break }
    if ($phase -eq 'Failed') { kubectl get cluster $VKS_CLUSTER -n $NS_NAME -o yaml | Write-Host; break }
} while ((Get-Date) -lt $deadline)

if ($phase -eq 'Provisioned') {
    Write-Host "=== 下載 kubeconfig ===" -ForegroundColor Cyan
    kubectl vsphere login --server=$supVip --vsphere-username=$VCUSER --vsphere-password=$VCPASS `
        --tanzu-kubernetes-cluster-name=$VKS_CLUSTER --tanzu-kubernetes-cluster-namespace=$NS_NAME --insecure-skip-tls-verify 2>&1 | Write-Host
    New-Item -ItemType Directory -Force -Path "$HOME\.kube" | Out-Null
    kubectl config view --flatten --context=$VKS_CLUSTER | Out-File -Encoding UTF8 $kubeconfig
    Write-Host "✓ kubeconfig: $kubeconfig" -ForegroundColor Green
    Write-Host "`nautomation 用：`$env:KUBECONFIG='$kubeconfig'; kubectl get nodes"
    $env:KUBECONFIG = $kubeconfig
    kubectl get nodes 2>&1 | Write-Host
} else {
    Write-Host "⚠️ phase=$phase，未取 kubeconfig。kubectl get cluster $VKS_CLUSTER -n $NS_NAME -o yaml 查詳情" -ForegroundColor Yellow
}
