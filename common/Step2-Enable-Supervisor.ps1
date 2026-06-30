<#  Step2 — 啟用 Supervisor（兩路線共用，REST API）
    Endpoint: POST /api/vcenter/namespace-management/supervisors
    前置：Path A 的 Step1（VNA+profile）或 Path B 的 Step1/1b（edge+centralized profile）已跑完。

    -DryRun  只印 payload 不送出
    -VpcProfileId  指定要用的 VPC connectivity profile（預設 $VPC_PROFILE_ID）

    ⚠️ 9.1 supervisors API 的 VPC-mode body 官方未完整公開；本 spec 依 lab schema 組出，
       建議先 -DryRun 檢視，或先 UI 啟一次再 GET 對照。 #>
param(
    [switch]$DryRun,
    [string]$VpcProfileId = $null,
    [int]$ControlPlaneCount = 3,
    [string]$ControlPlaneSize = 'SMALL'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lab.ps1"
Connect-Vc
if (-not $VpcProfileId) { $VpcProfileId = $VPC_PROFILE_ID }

# ── 已啟用就跳過 ──────────────────────────────────────────────────────────────
# /supervisors/summaries 回 { items:[ { supervisor, info:{ config_status, name, APIEndpoint } } ] }
$sups = (Vc-Get '/api/vcenter/namespace-management/supervisors/summaries').items
if ($sups | Where-Object { $_.info.config_status -eq 'RUNNING' }) {
    Write-Host "已有 RUNNING Supervisor，跳過。直接 Step3。" -ForegroundColor Green
    $sups | ForEach-Object { Write-Host "  $($_.supervisor)  $($_.info.config_status)  $($_.info.APIEndpoint)" }
    exit 0
}

# ── 取 IDs ────────────────────────────────────────────────────────────────────
$cl    = Vc-Get "/api/vcenter/cluster?names=$CLUSTER_NAME"; $clId = $cl[0].cluster
$pols  = Vc-Get '/rest/vcenter/storage/policies'
$pol   = ($pols.value | Where-Object { $_.name -match 'Single Node' } | Select-Object -First 1)
if (-not $pol) { $pol = $pols.value | Select-Object -First 1 }
$polId = $pol.policy
Write-Host "cluster=$clId  storage_policy='$($pol.name)'"

# content library（TKG）
$libs = Vc-Get '/api/content/library'; $libId = $null
foreach ($l in $libs) { $d = Vc-Get "/api/content/library/$l"; if ($d.name -match 'tkg|tanzu|vks|kubernetes' -or $d.type -eq 'SUBSCRIBED') { $libId = $l } }
if (-not $libId) {
    Write-Host "⚠️ 找不到 TKG content library。先建 subscribed library：" -ForegroundColor Red
    Write-Host "   https://wp-content.vmware.com/supervisor/v1/latest/lib.json" -ForegroundColor Yellow
    if (-not $DryRun) { exit 1 }
}

# NSX project + VPC profile path
$prof = Nsx-Get "/policy/api/v1/orgs/default/projects/$PROJECT_ID/vpc-connectivity-profiles/$VpcProfileId"
Write-Host "VPC profile: $($prof.display_name)  path=$($prof.path)"
$svc = if ($prof.service_gateway.edge_cluster_paths) {"Centralized (edge)"} else {"Distributed (VNA/DTGW)"}
Write-Host "  → 模式：$svc"

# ── Supervisor spec（VPC mode）────────────────────────────────────────────────
$spec = @{
    name = $SUP_NAME
    control_plane = @{
        count = $ControlPlaneCount
        size  = $ControlPlaneSize
        storage_policy = $polId
        network = @{
            ip_management = @{
                dhcp_enabled = $false
                gateway_address = "$CP_GATEWAY/$CP_PREFIX"
                ip_assignments = @(@{ assignee='NODE'; ranges=@(@{ address=$CP_START_IP; count=5 }) })
            }
            services = @{
                dns = @{ servers=$DNS_SERVERS; search_domains=$DNS_SEARCH }
                ntp = @{ servers=$NTP_SERVERS }
            }
        }
    }
    workloads = @{
        images = @{ kubernetes_content_library = $libId }
        edge   = @{ provider = 'NSX_VPC' }
        network = @{
            network_type = 'NSX_VPC'
            ip_management = @{
                dhcp_enabled = $false
                ip_assignments = @(@{ assignee='SERVICE'; ranges=@(@{ address=$SERVICE_CIDR; count=512 }) })
            }
            nsx_vpc = @{
                nsx_project              = "/orgs/default/projects/$PROJECT_ID"
                vpc_connectivity_profile = $prof.path
                default_private_cidrs    = @(@{ address=$VPC_PRIVATE_CIDR; prefix=$VPC_PRIVATE_PREFIX })
            }
            services = @{
                dns = @{ servers=$DNS_SERVERS; search_domains=$DNS_SEARCH }
                ntp = @{ servers=$NTP_SERVERS }
            }
        }
        storage = @{ ephemeral_storage_policy=$polId; image_storage_policy=$polId }
    }
}

if ($DryRun) {
    Write-Host "`n[DryRun] POST /api/vcenter/namespace-management/supervisors" -ForegroundColor DarkGray
    $spec | ConvertTo-Json -Depth 20 | Write-Host
    exit 0
}

Write-Host "`n送出 Supervisor 啟用..." -ForegroundColor Yellow
try { $r = Vc-Post '/api/vcenter/namespace-management/supervisors' $spec; Write-Host "✓ 已接受" -ForegroundColor Green; $r|ConvertTo-Json -Depth 4|Write-Host }
catch { Write-Host "✗ $($_.ErrorDetails.Message)" -ForegroundColor Red; exit 1 }

# ── 輪詢 ──────────────────────────────────────────────────────────────────────
$deadline = (Get-Date).AddMinutes(90)
do {
    Start-Sleep 60
    $m = (Vc-Get '/api/vcenter/namespace-management/supervisors/summaries') | Select-Object -First 1
    Write-Host "  [$(Get-Date -Format HH:mm:ss)] $($m.config_status)"
    if ($m.config_status -in 'RUNNING','ERROR') { break }
} while ((Get-Date) -lt $deadline)
Write-Host "最終：$($m.config_status)" -ForegroundColor $(if($m.config_status -eq 'RUNNING'){'Green'}else{'Yellow'})
