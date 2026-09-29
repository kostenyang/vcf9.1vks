#!/bin/bash
# 輪詢 Supervisor 的 config_status,直到 RUNNING 為止。
#   VC_HOST=vcf-m02-vc01.home.lab VC_USER='administrator@vsphere.local' VC_PASS='...' ./watch-sup.sh
LOG=${LOG:-./sup.log}
VC=${VC_HOST:?set VC_HOST}
USER=${VC_USER:-administrator@vsphere.local}
PASS=${VC_PASS:?set VC_PASS}
while true; do
  S=$(curl -sk -X POST -u "$USER:$PASS" "https://$VC/api/session" | tr -d '"')
  J=$(curl -sk -H "vmware-api-session-id: $S" "https://$VC/api/vcenter/namespace-management/supervisors/summaries")
  CS=$(echo "$J" | grep -o '"config_status":"[A-Z_]*"' | head -1 | cut -d'"' -f4)
  KS=$(echo "$J" | grep -o '"kubernetes_status":"[A-Z_]*"' | head -1 | cut -d'"' -f4)
  MSG=$(echo "$J" | python -c "import sys,json;d=json.load(sys.stdin);m=d['items'][0]['info'].get('messages',[]);print(' ;; '.join(x.get('details',{}).get('default_message',str(x))[:160] for x in m))" 2>/dev/null)
  echo "$(date +%H:%M:%S) config=$CS k8s=$KS $MSG" >> "$LOG"
  [ "$CS" = "RUNNING" ] && { echo "SUP_RUNNING" >> "$LOG"; break; }
  sleep 60
done
