<#  Path B Step1 — 部署 NSX Edge cluster + Tier-0（SDDC Manager API）
    VCF 9.x 用 SDDC Manager /v1/edge-clusters（先 validate 再送）。
    T0 設 ACTIVE_STANDBY（VKS 需要）。

    -DryRun  只印 payload 不送
    -Validate 只跑 validation 不正式部署 #>
param([switch]$DryRun, [switch]$Validate)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\lab.ps1"

# ── 取 token + domain/cluster id ─────────────────────────────────────────────
$token = Get-SddcToken
$h = @{ Authorization = "Bearer $token" }
Write-Host "SDDC Manager token OK"

$domains = Invoke-RestMethod -SkipCertificateCheck "https://$SDDC/v1/domains" -Headers $h
$dom = $domains.elements | Where-Object { $_.type -eq 'MANAGEMENT' } | Select-Object -First 1
Write-Host "domain: $($dom.name)  id=$($dom.id)"
$clusters = Invoke-RestMethod -SkipCertificateCheck "https://$SDDC/v1/clusters" -Headers $h
$cl = $clusters.elements | Where-Object { $_.name -eq $CLUSTER_NAME } | Select-Object -First 1
Write-Host "cluster: $($cl.name)  id=$($cl.id)"

# ── Edge cluster spec ────────────────────────────────────────────────────────
$spec = @{
    edgeClusterName  = $EDGE_CLUSTER_NAME
    edgeClusterType  = 'NSX-T'
    edgeFormFactor   = 'MEDIUM'
    tier0ServicesHighAvailability = 'ACTIVE_STANDBY'   # VKS 要 A/S
    mtu              = 1600
    asn              = 65051
    edgeRootPassword = $NSXPASS
    edgeAdminPassword= $NSXPASS
    edgeAuditPassword= $NSXPASS
    tier0RoutingType = 'STATIC'
    tier0Name        = $T0_NAME
    tier1Name        = 'vcf-m02-t1'
    edgeClusterProfileType = 'DEFAULT'
    edgeNodeSpecs = @(
        @{
            edgeNodeName      = 'kosten-vcf91-en01.rtolab.local'
            managementIP      = '192.168.114.70/24'
            managementGateway = '192.168.114.254'
            edgeTepGateway    = '192.168.117.1'
            edgeTep1IP        = '192.168.117.28/24'
            edgeTep2IP        = '192.168.117.29/24'
            edgeTepVlan       = 117
            clusterId         = $cl.id
            interRackCluster  = $false
            uplinkNetwork     = @(@{ uplinkVlan=114; uplinkInterfaceIP='192.168.114.72/24'; peerIP='192.168.114.254/24' })
        },
        @{
            edgeNodeName      = 'kosten-vcf91-en02.rtolab.local'
            managementIP      = '192.168.114.71/24'
            managementGateway = '192.168.114.254'
            edgeTepGateway    = '192.168.117.1'
            edgeTep1IP        = '192.168.117.30/24'
            edgeTep2IP        = '192.168.117.31/24'
            edgeTepVlan       = 117
            clusterId         = $cl.id
            interRackCluster  = $false
            uplinkNetwork     = @(@{ uplinkVlan=114; uplinkInterfaceIP='192.168.114.73/24'; peerIP='192.168.114.254/24' })
        }
    )
}

if ($DryRun) { Write-Host "[DryRun] POST /v1/edge-clusters" -ForegroundColor DarkGray; $spec|ConvertTo-Json -Depth 20|Write-Host; exit 0 }

# ── Validation ───────────────────────────────────────────────────────────────
Write-Host "驗證 edge cluster spec..." -ForegroundColor Cyan
$val = Invoke-RestMethod -SkipCertificateCheck -Method Post "https://$SDDC/v1/edge-clusters/validations" -Headers $h -Body ($spec|ConvertTo-Json -Depth 20) -ContentType 'application/json'
Write-Host "  validation id=$($val.id)  status=$($val.executionStatus)/$($val.resultStatus)"
$vid = $val.id
do {
    Start-Sleep 10
    $vr = Invoke-RestMethod -SkipCertificateCheck "https://$SDDC/v1/edge-clusters/validations/$vid" -Headers $h
    Write-Host "  [$(Get-Date -Format HH:mm:ss)] $($vr.executionStatus)/$($vr.resultStatus)"
} while ($vr.executionStatus -eq 'IN_PROGRESS')
if ($vr.resultStatus -ne 'SUCCEEDED') {
    Write-Host "✗ 驗證失敗：" -ForegroundColor Red
    $vr.validationChecks | Where-Object { $_.resultStatus -ne 'SUCCEEDED' } | ForEach-Object { Write-Host "   - $($_.description): $($_.errorResponse.message)" }
    exit 1
}
Write-Host "  ✓ 驗證通過" -ForegroundColor Green
if ($Validate) { Write-Host "（-Validate 模式，停在驗證）"; exit 0 }

# ── Deploy ───────────────────────────────────────────────────────────────────
Write-Host "送出 edge cluster 部署（約 30-60 分鐘）..." -ForegroundColor Yellow
$task = Invoke-RestMethod -SkipCertificateCheck -Method Post "https://$SDDC/v1/edge-clusters" -Headers $h -Body ($spec|ConvertTo-Json -Depth 20) -ContentType 'application/json'
Write-Host "  task id=$($task.id)"
$deadline=(Get-Date).AddMinutes(90)
do {
    Start-Sleep 60
    $t = Invoke-RestMethod -SkipCertificateCheck "https://$SDDC/v1/edge-clusters/$($task.id)" -Headers $h 2>$null
    Write-Host "  [$(Get-Date -Format HH:mm:ss)] $($t.status)"
    if ($t.status -in 'COMPLETED','Active','FAILED') { break }
} while ((Get-Date) -lt $deadline)
Write-Host "edge cluster: $($t.status)  → 下一步 Step1b-Setup-Centralized-TGW.ps1" -ForegroundColor Green
