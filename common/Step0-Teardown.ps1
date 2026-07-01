<#  Step0-Teardown — 全拆（逆序）：VKS cluster → namespace → Supervisor → VNA → VPC profile → IP blocks
    用法：  pwsh Step0-Teardown.ps1 [-DryRun]
    -DryRun：只印操作，不實際送出（NSX DELETE 支援；kubectl/VC 部分仍只印步驟）

    ⚠️ 順序不能顛倒：Supervisor 必須先 disable 才能刪 VPC profile；
       VNA node 必須先刪才能刪 VNA cluster。 #>
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lab.ps1"

$vnaBase = "/policy/api/v1/infra/sites/default/enforcement-points/default/virtual-network-appliance-clusters/$VNA_CLUSTER_ID"

function Step { param($n,$msg) Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Ok   { param($msg)    Write-Host "  ✓ $msg"   -ForegroundColor Green }
function Skip { param($msg)    Write-Host "  (skip) $msg" -ForegroundColor DarkGray }
function Warn { param($msg)    Write-Host "  ⚠ $msg"   -ForegroundColor Yellow }

# ── 0. 取得 vCenter session（kubectl 不需要 session）─────────────────────────
Connect-Vc

# ── 1. 刪 VKS cluster（kubectl）─────────────────────────────────────────────
Step "1/9" "Delete VKS cluster '$VKS_CLUSTER' in namespace '$NS_NAME'"
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Warn "kubectl 未安裝，跳過 VKS cluster 刪除（或手動刪）"
} else {
    if ($DryRun) {
        Write-Host "  [DryRun] kubectl vsphere login / kubectl delete cluster $VKS_CLUSTER -n $NS_NAME" -ForegroundColor DarkGray
    } else {
        # kubectl vsphere login with 30s timeout (Supervisor API may be unreachable from this host)
        $loginJob = Start-Job -ScriptBlock {
            param($kubectl, $sup_api, $vcuser, $vcpass)
            & $kubectl vsphere login --server=$sup_api `
                --vsphere-username=$vcuser --vsphere-password=$vcpass `
                --insecure-skip-tls-verify 2>&1
        } -ArgumentList $KUBECTL, $SUP_API_VIP, $VCUSER, $VCPASS
        $null = Wait-Job $loginJob -Timeout 30
        if ($loginJob.State -ne 'Completed') {
            Stop-Job $loginJob; Remove-Job $loginJob -Force
            Warn "Supervisor API $SUP_API_VIP`:6443 unreachable (30s timeout) — skipping kubectl cluster deletion"
        } else {
            Receive-Job $loginJob -ErrorAction SilentlyContinue | Out-Null; Remove-Job $loginJob
            & $KUBECTL config use-context $NS_NAME 2>&1 | Out-Null
            $exists = & $KUBECTL get cluster $VKS_CLUSTER -n $NS_NAME --ignore-not-found 2>&1
            if ($exists -match $VKS_CLUSTER) {
                & $KUBECTL delete cluster $VKS_CLUSTER -n $NS_NAME 2>&1 | Write-Host
                Write-Host "  等候 cluster 刪除（最多 15 分鐘）..."
                $dl = (Get-Date).AddMinutes(15)
                do {
                    Start-Sleep 30
                    $chk = & $KUBECTL get cluster $VKS_CLUSTER -n $NS_NAME --ignore-not-found 2>&1
                    Write-Host "  [$(Get-Date -Format HH:mm:ss)] $chk"
                } while ($chk -match $VKS_CLUSTER -and (Get-Date) -lt $dl)
                Ok "cluster gone"
            } else { Skip "cluster '$VKS_CLUSTER' not found" }
        }
    }
}

# ── 2. 刪 namespace ───────────────────────────────────────────────────────────
Step "2/9" "Delete namespace '$NS_NAME'"
if ($DryRun) {
    Write-Host "  [DryRun] DELETE /api/vcenter/namespaces/instances/$NS_NAME" -ForegroundColor DarkGray
} else {
    $gone = Vc-Delete "/api/vcenter/namespaces/instances/$NS_NAME"
    if ($gone) {
        Write-Host "  等候 namespace 移除..."
        $dl = (Get-Date).AddMinutes(10)
        do {
            Start-Sleep 20
            try { $ns = Vc-Get "/api/vcenter/namespaces/instances/$NS_NAME" } catch { $ns = $null }
            Write-Host "  [$(Get-Date -Format HH:mm:ss)] exists=$($null -ne $ns)"
        } while ($null -ne $ns -and (Get-Date) -lt $dl)
        Ok "namespace gone"
    } else { Skip "namespace '$NS_NAME' not found" }
}

# ── 3. Disable Supervisor ─────────────────────────────────────────────────────
Step "3/9" "Disable Supervisor '$SUP_NAME'"
if ($DryRun) {
    Write-Host "  [DryRun] GET summaries → DELETE /api/vcenter/namespace-management/supervisors/{id}" -ForegroundColor DarkGray
} else {
    $sums = (Vc-Get '/api/vcenter/namespace-management/supervisors/summaries').items
    if ($sums -and $sums.Count -gt 0) {
        $supId = $sums[0].supervisor
        Write-Host "  Supervisor id=$supId"
        Vc-Delete "/api/vcenter/namespace-management/supervisors/$supId" | Out-Null
        Write-Host "  等候 Supervisor disable（最多 30 分鐘）..."
        $dl = (Get-Date).AddMinutes(30)
        do {
            Start-Sleep 60
            $chk = (Vc-Get '/api/vcenter/namespace-management/supervisors/summaries').items
            $status = if ($chk) { $chk[0].info.config_status } else { 'GONE' }
            Write-Host "  [$(Get-Date -Format HH:mm:ss)] $status"
        } while ($chk -and $status -notin 'CONFIGURING','DISABLED' -and (Get-Date) -lt $dl)
        # wait until no supervisor left
        $dl2 = (Get-Date).AddMinutes(30)
        do {
            Start-Sleep 60
            $chk2 = (Vc-Get '/api/vcenter/namespace-management/supervisors/summaries').items
            $status2 = if ($chk2) { $chk2[0].info.config_status } else { 'GONE' }
            Write-Host "  [$(Get-Date -Format HH:mm:ss)] $status2"
        } while ($chk2 -and $status2 -ne 'GONE' -and (Get-Date) -lt $dl2)
        Ok "Supervisor disabled/gone"
    } else { Skip "no Supervisor found" }
}

# ── 4. 刪 VNA node ────────────────────────────────────────────────────────────
Step "4/9" "Delete VNA node 'vcf-m02-vna01'"
Nsx-Delete -DryRun:$DryRun "$vnaBase/virtual-network-appliances/vcf-m02-vna01" | Out-Null
if (-not $DryRun) {
    Write-Host "  等候 VNA node 刪除（最多 10 分鐘）..."
    $dl = (Get-Date).AddMinutes(10)
    do {
        Start-Sleep 30
        try { $r = Nsx-Get "$vnaBase/virtual-network-appliances/vcf-m02-vna01"; $exists = $true } catch { $exists = $false }
        Write-Host "  [$(Get-Date -Format HH:mm:ss)] exists=$exists"
    } while ($exists -and (Get-Date) -lt $dl)
    Ok "VNA node gone"
}

# ── 5. 刪 VPC Connectivity Profile（必須先於 VNA cluster）───────────────────
Step "5/9" "Delete VPC Connectivity Profile '$VPC_PROFILE_ID'"
Nsx-Delete -DryRun:$DryRun "/policy/api/v1/orgs/default/projects/$PROJECT_ID/vpc-connectivity-profiles/$VPC_PROFILE_ID" | Out-Null
if (-not $DryRun) { Ok "VPC profile deleted" }

# ── 6. 刪 VNA cluster（VPC profile 已刪才可刪）───────────────────────────────
Step "6/9" "Delete VNA cluster '$VNA_CLUSTER_ID'"
Nsx-Delete -DryRun:$DryRun $vnaBase | Out-Null
if (-not $DryRun) {
    Start-Sleep 10
    try { Nsx-Get $vnaBase | Out-Null; Warn "VNA cluster 仍存在，可能需要更長時間" }
    catch { Ok "VNA cluster gone" }
}

# ── 7. 刪 TransitGatewayAttachment（必須先於 DVC）────────────────────────────
Step "7/9" "Delete TransitGatewayAttachment '$TGW_ATTACH_ID'"
Nsx-Delete -DryRun:$DryRun "/policy/api/v1/orgs/default/projects/$PROJECT_ID/transit-gateways/default/attachments/$TGW_ATTACH_ID" | Out-Null
if (-not $DryRun) { Ok "TGW attachment deleted" }

# ── 8. 刪 DistributedVlanConnection（必須先於 IP blocks）─────────────────────
Step "8/9" "Delete DistributedVlanConnection '$DVC_ID'"
Nsx-Delete -DryRun:$DryRun "/policy/api/v1/infra/distributed-vlan-connections/$DVC_ID" | Out-Null
if (-not $DryRun) { Ok "DVC deleted" }

# ── 9. 刪 IP blocks ───────────────────────────────────────────────────────────
Step "9/9" "Delete IP blocks ($EXT_IPBLOCK_ID, $PRIV_TGW_ID)"
Nsx-Delete -DryRun:$DryRun "/policy/api/v1/infra/ip-blocks/$EXT_IPBLOCK_ID" | Out-Null
Nsx-Delete -DryRun:$DryRun "/policy/api/v1/infra/ip-blocks/$PRIV_TGW_ID"    | Out-Null
if (-not $DryRun) { Ok "IP blocks deleted" }

Write-Host @"

=== Teardown 完成 ===
  拆除順序：cluster → namespace → Supervisor → VNA node → VPC profile → VNA cluster → TGW attachment → DVC → IP blocks
  下一步（重新建立）：
    Python 方式：
      cd python
      py step1_setup_dtgw.py  (NSX 前置)
      py step2_enable_supervisor.py
      py step3_new_namespace.py
      py step4_new_vks_cluster.py
    PowerShell 方式：
      pwsh path-a-dtgw/Step1-Setup-DTGW.ps1
      pwsh common/Step2-Enable-Supervisor.ps1
      pwsh common/Step3-New-Namespace.ps1
      pwsh common/Step4-New-VksCluster.ps1
"@ -ForegroundColor Green
