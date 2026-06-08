<#  Step1b — 在 inner vCenter 建 TKG Content Library（Supervisor/VKS 必須）
    兩模式：
      -Mode Subscribed  （預設）訂閱 wp-content.vmware.com（inner vCenter 需能對外）
      -Mode Local       建本地 library（離線；之後手動 import TKR OVA）

    可選：
      -SubscriptionUrl  覆蓋訂閱來源（例：jumpbox 鏡像 http://172.16.10.32:8080/lib.json）
      -ProxyUrl         若 vCenter 要走 proxy 才能對外（注意：vCenter VAMI 也要設 proxy）
      -DatastoreId      存放 library 的 datastore（預設自動找 vsan）
      -DryRun

    ⚠️ inner vCenter（192.168.114.11）實測**連不到** wp-content.vmware.com（RESOURCE_INACCESSIBLE）。
       Subscribed 模式要先解決 inner vCenter 對外（DNS 轉發 / proxy / jumpbox 鏡像）。
       離線環境用 -Mode Local，再從 jumpbox（有網）下載 TKR 後 import。 #>
param(
    [ValidateSet('Subscribed','Local')] [string]$Mode = 'Subscribed',
    [string]$Name = 'tkg-content-library',
    [string]$SubscriptionUrl = 'https://wp-content.vmware.com/supervisor/v1/latest/lib.json',
    [string]$ProxyUrl,
    [string]$DatastoreId,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lab.ps1"
Connect-Vc

# ── 已存在就跳過 ──────────────────────────────────────────────────────────────
$libs = Vc-Get '/api/content/library'
foreach ($l in $libs) {
    $d = Vc-Get "/api/content/library/$l"
    if ($d.name -eq $Name) { Write-Host "✓ content library '$Name' 已存在 (id=$l, type=$($d.type))，跳過。" -ForegroundColor Green; exit 0 }
}

# ── 找 datastore ──────────────────────────────────────────────────────────────
if (-not $DatastoreId) {
    Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
    $pc = Connect-VIServer -Server $VC -User $VCUSER -Password $VCPASS -Force
    $ds = Get-Datastore | Where-Object { $_.Name -match 'vsan' } | Select-Object -First 1
    $DatastoreId = $ds.ExtensionData.MoRef.Value
    Disconnect-VIServer * -Confirm:$false -Force | Out-Null
}
Write-Host "datastore: $DatastoreId"

if ($Mode -eq 'Local') {
    # ── 本地 library（離線，無需對外）─────────────────────────────────────────
    $body = @{
        name = $Name
        type = 'LOCAL'
        publish_info = @{ published = $true; authentication_method = 'NONE' }  # 可選：發佈讓其他 vC 訂
        storage_backings = @(@{ datastore_id = $DatastoreId; type = 'DATASTORE' })
    }
    if ($DryRun) { Write-Host "[DryRun] POST /api/content/local-library"; $body|ConvertTo-Json -Depth 8|Write-Host; exit 0 }
    $id = Vc-Post '/api/content/local-library' $body
    Write-Host "✓ 本地 library '$Name' 建立成功 id=$id" -ForegroundColor Green
    Write-Host "下一步：從 jumpbox（有網）下載 TKR OVA，import 進這個 library。"
    Write-Host "  TKR 清單見 $SubscriptionUrl（jumpbox curl 得到）"
    exit 0
}

# ── Subscribed library ────────────────────────────────────────────────────────
$sub = @{
    authentication_method  = 'NONE'
    automatic_sync_enabled = $true
    on_demand              = $true
    subscription_url       = $SubscriptionUrl
}
# 取 SSL thumbprint（https 才需要）
if ($SubscriptionUrl -like 'https://*') {
    try {
        $h = ([uri]$SubscriptionUrl).Host
        $tp = (& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "
            `$c=New-Object Net.Sockets.TcpClient('$h',443);`$s=New-Object Net.Security.SslStream(`$c.GetStream(),`$false,({`$true}));`$s.AuthenticateAsClient('$h');
            `$cert=`$s.RemoteCertificate;(`$cert.GetCertHashString()-replace '(..)(?=.)','`$1:');`$s.Close();`$c.Close()" ) 2>$null
        if ($tp) { $sub.ssl_thumbprint = $tp; Write-Host "ssl_thumbprint=$tp" }
    } catch { Write-Host "（取 thumbprint 失敗，略過）" -ForegroundColor DarkGray }
}

$body = @{
    name = $Name
    type = 'SUBSCRIBED'
    storage_backings = @(@{ datastore_id = $DatastoreId; type = 'DATASTORE' })
    subscription_info = $sub
}
if ($DryRun) { Write-Host "[DryRun] POST /api/content/subscribed-library"; $body|ConvertTo-Json -Depth 8|Write-Host; exit 0 }

try {
    $id = Vc-Post '/api/content/subscribed-library' $body
    Write-Host "✓ subscribed library '$Name' 建立成功 id=$id" -ForegroundColor Green
} catch {
    Write-Host "✗ 建立失敗：$($_.ErrorDetails.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "若是 RESOURCE_INACCESSIBLE / Connection failed → inner vCenter 連不到 $SubscriptionUrl。" -ForegroundColor Yellow
    Write-Host "解法：" -ForegroundColor Yellow
    Write-Host "  a) 在 jumpbox（有網）做鏡像，-SubscriptionUrl http://172.16.10.32:<port>/lib.json"
    Write-Host "  b) 幫 inner vCenter 設 proxy / DNS 轉發後重試"
    Write-Host "  c) 改 -Mode Local，手動 import TKR OVA"
    exit 1
}
