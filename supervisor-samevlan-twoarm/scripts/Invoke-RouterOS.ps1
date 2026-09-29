# RouterOS API client (port 8728) — configure NTP + interface IPs on routeros-clone 10.0.1.254
# 通用 RouterOS API 指令執行器。密碼從環境變數 ROS_PASS 帶入:
#   $env:ROS_PASS="..."; .Invoke-RouterOS.ps1 -Cmds @("/ip/address/print")
param([string]$Ip='10.0.1.254',[string]$User='admin',[string]$Pass=$env:ROS_PASS,[string[]]$Cmds)
$ErrorActionPreference='Stop'

function Write-Len($s,$len){
  if($len -lt 0x80){ $s.WriteByte($len) }
  elseif($len -lt 0x4000){ $l=$len -bor 0x8000; $s.WriteByte(($l -shr 8) -band 0xFF); $s.WriteByte($l -band 0xFF) }
  elseif($len -lt 0x200000){ $l=$len -bor 0xC00000; $s.WriteByte(($l -shr 16) -band 0xFF); $s.WriteByte(($l -shr 8) -band 0xFF); $s.WriteByte($l -band 0xFF) }
  else { $s.WriteByte((($len -shr 24) -band 0xFF) -bor 0xE0); $s.WriteByte(($len -shr 16) -band 0xFF); $s.WriteByte(($len -shr 8) -band 0xFF); $s.WriteByte($len -band 0xFF) }
}
function Send-Sentence($s,[string[]]$words){
  foreach($w in $words){ $b=[Text.Encoding]::ASCII.GetBytes($w); Write-Len $s $b.Length; $s.Write($b,0,$b.Length) }
  $s.WriteByte(0)
}
function Read-Byte($s){ $b=$s.ReadByte(); if($b -lt 0){ throw 'stream closed' }; return $b }
function Read-Len($s){
  $c=Read-Byte $s
  if(($c -band 0x80) -eq 0){ return $c }
  elseif(($c -band 0xC0) -eq 0x80){ return ((($c -band 0x3F) -shl 8) + (Read-Byte $s)) }
  elseif(($c -band 0xE0) -eq 0xC0){ return ((($c -band 0x1F) -shl 16) + ((Read-Byte $s) -shl 8) + (Read-Byte $s)) }
  else { return ((($c -band 0x0F) -shl 24) + ((Read-Byte $s) -shl 16) + ((Read-Byte $s) -shl 8) + (Read-Byte $s)) }
}
function Read-Word($s){
  $len=Read-Len $s; if($len -eq 0){ return $null }
  $buf=New-Object byte[] $len; $r=0; while($r -lt $len){ $n=$s.Read($buf,$r,$len-$r); if($n -le 0){ throw 'eof' }; $r+=$n }
  return [Text.Encoding]::ASCII.GetString($buf)
}
function Read-Sentence($s){ $w=@(); while($true){ $x=Read-Word $s; if($null -eq $x){ break }; $w+=$x }; return ,$w }
function Cmd($s,[string[]]$words){
  Send-Sentence $s $words
  $out=@(); while($true){ $sen=Read-Sentence $s; if($sen.Count -eq 0){ continue }; $out+=,$sen; if($sen[0] -eq '!done' -or $sen[0] -eq '!fatal'){ break }; if($sen[0] -eq '!trap'){ } }
  return $out
}

$tcp=New-Object Net.Sockets.TcpClient; $tcp.Connect($Ip,8728); $s=$tcp.GetStream()
"connected $Ip:8728"
# plain login (v6.43+/v7)
$r=Cmd $s @('/login',"=name=$User","=password=$Pass")
$flat = ($r | ForEach-Object { $_ -join ' ' }) -join ' | '
if($flat -match '=ret='){
  # old challenge-response
  $chal=($r | ForEach-Object{ $_ } | Where-Object{ $_ -match '^=ret=' }) -replace '^=ret=',''
  $cb=New-Object byte[] ($chal.Length/2); for($i=0;$i -lt $cb.Length;$i++){ $cb[$i]=[Convert]::ToByte($chal.Substring($i*2,2),16) }
  $md5=[Security.Cryptography.MD5]::Create()
  $pb=[Text.Encoding]::ASCII.GetBytes($Pass)
  $data=New-Object byte[] (1+$pb.Length+$cb.Length); $data[0]=0; [Array]::Copy($pb,0,$data,1,$pb.Length); [Array]::Copy($cb,0,$data,1+$pb.Length,$cb.Length)
  $hash=$md5.ComputeHash($data); $resp='00'+(($hash|ForEach-Object{ $_.ToString('x2') }) -join '')
  $r=Cmd $s @('/login',"=name=$User","=response=$resp")
}
$loginOk = ($r | Where-Object{ $_[0] -eq '!done' }).Count -gt 0 -and -not (($r|Where-Object{$_[0] -eq '!trap'}).Count -gt 0 -and $flat -notmatch '=ret=')
"login result: $((($r|ForEach-Object{$_ -join ' '}) -join ' | '))"

# ---- 任意指令 ----
# 用法: powershell -File Invoke-RouterOS.ps1 -Cmds '/ip/address/print','/ip/address/add|=address=172.16.10.254/24|=interface=ether1'
foreach($c in $Cmds){
  $words = $c -split '\|'
  "--- $c"
  (Cmd $s $words) | ForEach-Object { ($_ -join ' ') }
}
$tcp.Close()
