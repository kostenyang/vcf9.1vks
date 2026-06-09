"""
共用設定 + helper（對應 PowerShell 的 common/lab.ps1）。
其他 step 腳本 `from lab import *` 或 `import lab`。

需求：  pip install -r requirements.txt   （requests；step4 另需 kubernetes 或現成 kubectl）
用法：  python step3_new_namespace.py
        python step2_enable_supervisor.py --dry-run

所有值為 2026-06-08 實機部署後確認（與 lab.ps1 一致）。
"""
import base64
import json
import os
import ssl
import sys
import urllib3
import requests

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ── Lab 連線 ──────────────────────────────────────────────────────────────────
VC      = os.environ.get("VC",      "192.168.114.11")   # inner vCenter (kosten-vcf91-vc)
VCUSER  = os.environ.get("VCUSER",  "administrator@vsphere.local")
VCPASS  = os.environ.get("VCPASS",  "VMware1!VMware1!")
NSXVIP  = os.environ.get("NSXVIP",  "192.168.114.13")   # NSX Manager VIP
NSXUSER = os.environ.get("NSXUSER", "admin")
NSXPASS = os.environ.get("NSXPASS", "VMware1!VMware1!")
SDDC    = os.environ.get("SDDC",    "192.168.114.10")   # SDDC Manager
CLUSTER_NAME = "vcf-m02-cl01"

# ── IP 規劃（實機確認）────────────────────────────────────────────────────────
SUP_NAME        = "vcf-m02-supervisor"
SUP_API_VIP     = "192.168.114.132"   # Supervisor API endpoint（kubectl-vsphere login 用這個）
CP_START_IP     = "192.168.114.101"   # CP mgmt：5 consecutive .101-.105
CP_GATEWAY      = "192.168.114.254"
CP_PREFIX       = 24
DNS_SERVERS     = ["192.168.114.200"]
NTP_SERVERS     = ["192.168.114.200"]
DNS_SEARCH      = ["rtolab.local"]
# Supervisor 三段 CIDR（不可互相重疊；wizard 預設 Private(VPC)=Private TGW 會被擋）
SERVICE_CIDR    = "172.29.0.0"
SERVICE_PREFIX  = 16

EXT_IPBLOCK_CIDR = "192.168.114.128/26"  # external (public/LB/SNAT); /26 必須對齊邊界 .0/.64/.128/.192
PRIV_TGW_CIDR    = "172.30.0.0/16"       # private TGW block (VKS 要 /16)
VPC_PRIVATE_CIDR = "172.28.0.0"          # VPC Private CIDR（與 Private TGW 172.30 不重疊）
VPC_PRIVATE_PREFIX = 16

# NSX 資源命名
PROJECT_ID    = "default"
EXT_IPBLOCK_ID = "vcf-m02-vks-ext-ipblock"
PRIV_TGW_ID    = "vcf-m02-vks-priv-tgw"
VPC_PROFILE_ID = "vcf-m02-vks-vpc-profile"
VNA_CLUSTER_ID = "vcf-m02-vna-01"

# VKS namespace / cluster
NS_NAME       = "vks-automation"
VKS_CLUSTER   = "vks-auto-01"

# kubectl 路徑（非 PATH，固定）
KUBECTL = r"C:\Users\Administrator\vks-tools\bin\kubectl.exe"


# ── vCenter REST helper ───────────────────────────────────────────────────────
class Vc:
    """vCenter automation REST（/api）。對應 PS 的 Connect-Vc / Vc-Get / Vc-Post。"""
    def __init__(self):
        self.base = f"https://{VC}"
        enc = base64.b64encode(f"{VCUSER}:{VCPASS}".encode()).decode()
        r = requests.post(f"{self.base}/api/session",
                          headers={"Authorization": f"Basic {enc}"}, verify=False)
        r.raise_for_status()
        self.sid = r.json() if r.headers.get("content-type", "").startswith("application/json") else r.text.strip('"')
        self.hdr = {"vmware-api-session-id": self.sid, "Content-Type": "application/json"}

    def get(self, path):
        r = requests.get(f"{self.base}{path}", headers=self.hdr, verify=False)
        r.raise_for_status()
        return r.json()

    def post(self, path, body):
        r = requests.post(f"{self.base}{path}", headers=self.hdr,
                          data=json.dumps(body), verify=False)
        if not r.ok:
            raise RuntimeError(f"POST {path} -> {r.status_code}: {r.text}")
        return r.json() if r.text else None

    def delete(self, path):
        r = requests.delete(f"{self.base}{path}", headers=self.hdr, verify=False)
        if r.status_code == 404:
            return False
        if not r.ok:
            raise RuntimeError(f"DELETE {path} -> {r.status_code}: {r.text}")
        return True


# ── NSX Policy helper ─────────────────────────────────────────────────────────
class Nsx:
    """NSX Policy API（/policy/api/v1）。對應 PS 的 Nsx-Get / Nsx-Patch / Nsx-Put。"""
    def __init__(self):
        self.base = f"https://{NSXVIP}"
        enc = base64.b64encode(f"{NSXUSER}:{NSXPASS}".encode()).decode()
        self.hdr = {"Authorization": f"Basic {enc}", "Content-Type": "application/json"}

    def get(self, path):
        r = requests.get(f"{self.base}{path}", headers=self.hdr, verify=False)
        r.raise_for_status()
        return r.json()

    def patch(self, path, body, dry_run=False):
        if dry_run:
            print(f"  [DryRun] PATCH {path}\n{json.dumps(body, indent=2)}")
            return None
        r = requests.patch(f"{self.base}{path}", headers=self.hdr,
                           data=json.dumps(body), verify=False)
        if not r.ok:
            raise RuntimeError(f"PATCH {path} -> {r.status_code}: {r.text}")
        return r.json() if r.text else None

    def put(self, path, body, dry_run=False):
        if dry_run:
            print(f"  [DryRun] PUT {path}\n{json.dumps(body, indent=2)}")
            return None
        r = requests.put(f"{self.base}{path}", headers=self.hdr,
                        data=json.dumps(body), verify=False)
        if not r.ok:
            raise RuntimeError(f"PUT {path} -> {r.status_code}: {r.text}")
        return r.json() if r.text else None

    def delete(self, path, dry_run=False):
        if dry_run:
            print(f"  [DryRun] DELETE {path}")
            return True
        r = requests.delete(f"{self.base}{path}", headers=self.hdr, verify=False)
        if r.status_code == 404:
            print(f"  (already gone: {path})")
            return False
        if not r.ok:
            raise RuntimeError(f"DELETE {path} -> {r.status_code}: {r.text}")
        return True


def sddc_token():
    """SDDC Manager token（Path B 用）。"""
    r = requests.post(f"https://{SDDC}/v1/tokens",
                      json={"username": VCUSER, "password": VCPASS}, verify=False)
    r.raise_for_status()
    return r.json()["accessToken"]
