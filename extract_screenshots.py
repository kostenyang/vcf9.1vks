"""Extract wizard screenshots from session JSONL and save to screenshots/."""
import json, base64, os, sys

JSONL = r"C:\Users\Administrator\.claude\projects\C--Users-Administrator-Documents-rto\6aee50b4-9db4-4d62-999b-3eacadef290d.jsonl"
OUT   = r"C:\Users\Administrator\vcf9.1vks\screenshots"

TARGETS = {
    "ss_95693qxip":  "08-step4-mgmt-network.jpg",
    "ss_1671srv2o":  "09-step5-workload-network-top.jpg",
    "ss_952118r65":  "09-step5-workload-network.jpg",
    "ss_8457j45y2":  "10-step6-advanced.jpg",
    "ss_88704rvdk":  "11-step7-ready.jpg",
}

def find_image_data(obj):
    """Recursively find base64 image data in a parsed JSON object."""
    if isinstance(obj, dict):
        if obj.get("type") == "image":
            src = obj.get("source", {})
            if src.get("type") == "base64":
                return src.get("data")
        for v in obj.values():
            r = find_image_data(v)
            if r:
                return r
    elif isinstance(obj, list):
        for item in obj:
            r = find_image_data(item)
            if r:
                return r
    return None

found = {}

print(f"Scanning {JSONL} ...")
with open(JSONL, "r", encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, 1):
        raw = raw.strip()
        if not raw:
            continue
        for ss_id in TARGETS:
            if ss_id in found:
                continue
            if ss_id in raw:
                try:
                    obj = json.loads(raw)
                    data = find_image_data(obj)
                    if data:
                        found[ss_id] = data
                        print(f"  line {lineno}: found {ss_id} ({len(data)} b64 chars)")
                except Exception as e:
                    print(f"  line {lineno}: parse error for {ss_id}: {e}")
        if len(found) == len(TARGETS):
            print("  All targets found, stopping early.")
            break

print()
for ss_id, fname in TARGETS.items():
    if ss_id in found:
        out = os.path.join(OUT, fname)
        img = base64.b64decode(found[ss_id])
        with open(out, "wb") as f:
            f.write(img)
        print(f"  SAVED  {fname}  ({len(img):,} bytes)")
    else:
        print(f"  MISSING {ss_id} -> {fname}")
