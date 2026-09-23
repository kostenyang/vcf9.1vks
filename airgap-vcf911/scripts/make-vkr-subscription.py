#!/usr/bin/env python3
"""為鏡像下來的 VKr 目錄產生 content library 訂閱用的 lib.json / items.json。

  1) 先抓官方 items.json:curl -s https://wp-content.broadcom.com/v2/latest/items.json -o wp-items.json
  2) python make-vkr-subscription.py wp-items.json <出力目錄> <item 名稱> [<item 名稱> ...]
  3) 把產出的 lib.json / items.json 放到 depot 的 .../PROD/COMP/VKR/ 底下
"""
import json, sys, uuid, os
src, outdir, names = sys.argv[1], sys.argv[2], set(sys.argv[3:])
items = json.load(open(src, encoding='utf-8')).get('items', [])
sel = [x for x in items if x.get('name') in names]
if len(sel) != len(names):
    missing = names - {x['name'] for x in sel}
    sys.exit(f'找不到這些 item:{missing}')
json.dump({'items': sel}, open(os.path.join(outdir, 'items.json'), 'w', encoding='utf-8'), indent=1)
json.dump({'vcspVersion': '2', 'contentVersion': '1', 'version': '1', 'name': 'vkr-local',
           'itemsHref': 'items.json', 'id': 'urn:uuid:' + str(uuid.uuid4()),
           'capabilities': {'transferIn': ['httpGet'], 'transferOut': ['httpGet']}},
          open(os.path.join(outdir, 'lib.json'), 'w', encoding='utf-8'), indent=1)
print('wrote lib.json / items.json for', len(sel), 'items')
