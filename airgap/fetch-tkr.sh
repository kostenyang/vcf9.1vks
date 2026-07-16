#!/usr/bin/env bash
# Air-gap staging 端:從 VMware 公開 VKr Content Library 抓 TKr(vSphere Kubernetes Release)映像。
# 免帳號、純 HTTPS、不需 vCenter。含「續傳 + SHA256 校驗」(wp-content 會 HTTP 200 但檔案截斷)。
#
# 來源 = https://wp-content.vmware.com/v2/latest/  (vcsp v2:lib.json + items.json)
# 每個 item = 4 檔:photon-ova.ovf + photon-ova-disk1.vmdk(主檔 5-7GB) + .mf(SHA256) + .cert
#
# 用法:
#   ./fetch-tkr.sh list [k8s過濾]                              # 例:./fetch-tkr.sh list 1.32
#   ./fetch-tkr.sh get <item全名> [輸出目錄(預設 ./tkr)]       # 例:./fetch-tkr.sh get ob-24945258-photon-5-amd64-v1.32.7---vmware.3-fips-vkr.1
#
# 相依:curl + (jq 或 python3)其一。

set -euo pipefail
BASE="${BASE:-https://wp-content.vmware.com/v2/latest}"

_json_list() {   # stdin=items.json  arg1=過濾字串 → 印 "name<TAB>sizeGB"
  local filt="$1"
  if command -v jq >/dev/null; then
    jq -r --arg f "$filt" '.items[] | select(.name|test($f)) | "\(.name)\t\((([.files[].size]|add)/1e9*100|floor)/100)GB"'
  else
    python3 -c '
import sys,json,re
f=sys.argv[1]; j=json.load(sys.stdin)
for it in j["items"]:
    if re.search(f,it["name"]):
        sz=sum(x.get("size",0) for x in it.get("files",[]))
        print("%s\t%.2fGB"%(it["name"],sz/1e9))' "$filt"
  fi
}

cmd="${1:-list}"
case "$cmd" in
  list)
    filt="${2:-}"
    echo "抓 items.json(過濾:'${filt}')..."
    curl -fsSL "$BASE/items.json" | _json_list "$filt" | sort
    ;;
  get)
    ITEM="${2:?需要 item 全名;先跑 './fetch-tkr.sh list' 查}"
    OUT="${3:-./tkr}/$ITEM"
    mkdir -p "$OUT"
    for f in photon-ova.mf photon-ova.ovf photon-ova.cert photon-ova-disk1.vmdk; do
      echo "下載 $f ..."
      # 🔴 -C - 續傳 + --retry:wp-content/CDN 會靜默截斷(HTTP 200 卻少 bytes)
      curl -fSL -C - --retry 8 --retry-delay 3 --retry-all-errors -o "$OUT/$f" "$BASE/$ITEM/$f"
    done
    echo ""
    echo "SHA256 校驗(對 .mf)..."   # 🔴 HTTP 200 != 完整,必校驗
    ( cd "$OUT" && sha256sum -c <(awk -F'[()= ]+' '/SHA256/{print $3"  "$2}' photon-ova.mf) )
    echo ""
    echo "OK 校驗通過 -> $OUT  可搬過氣隙。"
    echo "封閉側匯入:govc library.import vks-tkr \"$OUT/photon-ova.ovf\""
    ;;
  *)
    echo "用法:$0 list [k8s過濾]  |  $0 get <item全名> [輸出目錄]"; exit 2;;
esac
