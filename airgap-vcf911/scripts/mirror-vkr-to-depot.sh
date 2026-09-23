#!/bin/bash
# 把 VKr 鏡像進自建 Software Depot(token-only,不需要 activation code)
# 依賴:pwsh 7 + My-VcfDepot.v3.ps1(kostenyang/vcf9offlinescript)
# 用法:./mirror-vkr-to-depot.sh /root/token.txt /depot "photon-5-amd64-v1.36.2" "photon-5-amd64-v1.35.6"
set -u
TOKEN=${1:?token file}; OUT=${2:?depot dir}; shift 2
for P in "$@"; do
  echo "=== $P $(date +%H:%M)"
  pwsh -NoProfile -File ./My-VcfDepot.v3.ps1 -TokenFile "$TOKEN" \
       -Component VKR -Type INSTALL -FileNameLike "*${P}*" -Download -OutDir "$OUT" 2>&1 | tail -6
done
du -sh "$OUT/PROD/COMP/VKR"
