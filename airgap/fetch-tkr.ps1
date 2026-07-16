<#
.SYNOPSIS
  Air-gap staging 端:從 VMware 公開 VKr Content Library 抓 TKr(vSphere Kubernetes Release)映像。
  免帳號、純 HTTPS、不需 vCenter。含「續傳 + SHA256 校驗」(wp-content 會 HTTP 200 但檔案截斷)。

.DESCRIPTION
  來源 = https://wp-content.vmware.com/v2/latest/  (vcsp v2:lib.json + items.json)
  每個 TKr item = 4 檔:photon-ova.ovf + photon-ova-disk1.vmdk(主檔 5-7GB) + .mf(SHA256) + .cert

.EXAMPLE
  # 列出所有含 1.32 的版本
  .\fetch-tkr.ps1 -List -K8sVersion 1.32

.EXAMPLE
  # 下載指定 item 到 .\tkr\  (自動續傳 + 校驗)
  .\fetch-tkr.ps1 -Item ob-24945258-photon-5-amd64-v1.32.7---vmware.3-fips-vkr.1 -OutDir .\tkr
#>
[CmdletBinding()]
param(
  [switch]$List,
  [string]$K8sVersion = '',                         # 過濾用,如 "1.32"
  [string]$Item = '',                               # 要下載的 item 全名(資料夾名)
  [string]$OutDir = '.\tkr',
  [string]$BaseUrl = 'https://wp-content.vmware.com/v2/latest'
)
$ErrorActionPreference = 'Stop'
# Windows 10/11 內建 curl.exe(支援 -C - 續傳);找不到就退回 Invoke-WebRequest(不續傳)
$curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source

function Get-Items {
  Write-Host "抓 items.json ..." -ForegroundColor Cyan
  (Invoke-WebRequest "$BaseUrl/items.json" -UseBasicParsing).Content | ConvertFrom-Json
}

if ($List -or -not $Item) {
  $items = (Get-Items).items
  $rows = $items | Where-Object { $_.name -match [regex]::Escape($K8sVersion) } | ForEach-Object {
    $sz = ($_.files | Measure-Object size -Sum).Sum
    [pscustomobject]@{ Item = $_.name; SizeGB = [math]::Round($sz/1GB,2) }
  }
  $rows | Sort-Object Item | Format-Table -AutoSize
  Write-Host "共 $($rows.Count) 個(過濾:'$K8sVersion')。用 -Item <名稱> 下載。" -ForegroundColor Green
  return
}

# ---- 下載 ----
$dst = Join-Path $OutDir $Item
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$files = @('photon-ova.mf','photon-ova.ovf','photon-ova.cert','photon-ova-disk1.vmdk')
foreach ($f in $files) {
  $url = "$BaseUrl/$Item/$f"; $out = Join-Path $dst $f
  Write-Host "下載 $f ..." -ForegroundColor Cyan
  if ($curl) {
    # 🔴 -C - 續傳 + --retry:wp-content/CDN 會靜默截斷(HTTP 200 卻少 bytes)
    & $curl -fSL -C - --retry 8 --retry-delay 3 --retry-all-errors -o $out $url
  } else {
    Invoke-WebRequest $url -OutFile $out -UseBasicParsing
  }
}

# ---- 🔴 SHA256 校驗(HTTP 200 ≠ 完整;用 Get-FileHash,別用會爆 2GB 的工具)----
Write-Host "`nSHA256 校驗(對 .mf)..." -ForegroundColor Cyan
$ok = $true
Get-Content (Join-Path $dst 'photon-ova.mf') | ForEach-Object {
  if ($_ -match 'SHA256\((.+)\)=\s*([0-9a-f]+)') {
    $name = $Matches[1]; $want = $Matches[2].ToLower()
    $got  = (Get-FileHash (Join-Path $dst $name) -Algorithm SHA256).Hash.ToLower()
    $m = $got -eq $want
    Write-Host ("  {0}  {1}" -f $name, $(if($m){'MATCH'}else{'MISMATCH'})) -ForegroundColor $(if($m){'Green'}else{'Red'})
    if (-not $m) { $ok = $false }
  }
}
if ($ok) {
  Write-Host "`nOK 全部校驗通過 -> $dst  可搬過氣隙。" -ForegroundColor Green
  Write-Host "封閉側匯入:govc library.import vks-tkr `"$dst\photon-ova.ovf`"" -ForegroundColor Yellow
} else {
  Write-Host "`nFAIL 有檔案不符 —— 重跑本腳本會自動 -C - 續傳補完。" -ForegroundColor Red; exit 1
}
