# 06 — VCF 9.1 VKS air-gap 實測（2026-07-12）

本次新增 [`../airgap/`](../airgap/) 工具，先從 Codex 主機做 preflight，接著實際修復 VCF
Software Depot distribution registry，並完成 OCI artifact write/read smoke test。

## 已驗證

| 測項 | 結果 |
|---|---|
| `airgap_tool.py` unit tests | PASS（5/5）|
| example config schema / credential guard | PASS |
| download / upload command generation | PASS |
| vCenter `192.168.114.11:443` | TCP PASS（unsandboxed host network）|
| 現有 download server `172.16.10.50:443` | TCP PASS |
| `https://172.16.10.50/v2/` | **HTTP 404**，不是 OCI registry |
| Fleet registry pod `/v2/` | **HTTP 200**, `Docker-Distribution-Api-Version: registry/2.0` |
| OCI config blob upload | PASS |
| OCI manifest PUT + GET | PASS |
| smoke artifact | `codex-airgap-smoke:20260712` |
| manifest digest | `sha256:1743cc4d36219b8666928dd3989a0449c31086911ba55365e240f8d351ca80c7` |

## Registry endpoint

`172.16.10.50` 是存放 VCF download-tool binaries 的 nginx server，但 `/v2/` 回 404，不能
填入 `airgap/config.json` 的 `depot_fqdn`。

從 VCF Management Platform Gateway API route 實際找到 distribution registry 的外部入口：

```text
https://kosten-vcf91-fleet.rtolab.local/v2/
```

VCF 內部 route 是 `/v2` → `depot-service:7443`，後端 distribution service提供
`5000/TCP` 與 `5443/TCP`。正常外部驗證應為 HTTP 200，或未登入時 HTTP 401：

```bash
python3 airgap_tool.py --config config.json check
```

## 實際發現並修復的 platform 故障

一開始無法進行 upload，不是 air-gap script本身問題，而是 VCF Management Platform已故障：

1. `distribution-service` pod為 `0/1 Unknown`，Service沒有 endpoint。
2. Deployment無法重建，因 Kyverno admission webhook `connection refused`。
3. Kyverno五個 pod卡在 `.18` node，該 node的 Antrea agent已連續 13 天 readiness失敗。
4. Flux `source-controller` 也為 `Unknown`，使 `vmsp-global-config` 與 Depot HelmRelease無法 reconcile。

實際修復順序：

1. 刪除 stale Antrea DaemonSet pod；因 `.18` kubelet/container runtime卡住而無法完成 termination。
2. vCenter graceful guest restart失敗（Tools API回報 Tools not running）。
3. 對 worker VM `kosten-vcf91-vspp-s9wz5` 執行 vCenter reset；control-plane未重啟。
4. `.18` 回到 `Ready`，新 Antrea pod `2/2 Running`。
5. Kyverno三個 admission replicas與 background/cleanup controllers全部恢復 `Ready`。
6. 刪除 stale Flux `source-controller` pod，Deployment重建為 `1/1 Running`。
7. `vmsp-global-config`、`cert-manager`、`kyverno`、`depot-service`、`distribution-service`
   HelmRelease全部回到 `Ready=True`。
8. 刪除 stale distribution pod；新 pod `1/1 Running`，endpoint為
   `198.18.1.10:5000,5443`。

Registry恢復後，實際使用 OCI Distribution API上傳 2-byte config blob與無 layer manifest，
再以 tag GET回來，取得 HTTP 200與上述 digest。這證明 registry data path確實可寫。

## DNS查核更正

先前使用 jumpbox預設 resolver查不到 Fleet FQDN，不能據此判定 lab沒有 DNS。依
`kostenyang/lab-info`，`rtolab.local`權威 DNS是 `192.168.114.200`。直接指定該 DNS查詢已確認：

| FQDN | A record |
|---|---|
| `kosten-vcf91-fleet.rtolab.local` | `192.168.114.45` |
| `kosten-vcf91-vsp.rtolab.local` | `192.168.114.43` |
| `kosten-vcf91-vspp.rtolab.local` | `192.168.114.44` |

因此 Fleet DNS記錄存在；先前結論是 resolver context錯誤。後續所有 lab DNS判讀以
`lab-info`指定的 `.200`權威 DNS為準。

## 尚未完成

- 尚未在 platform恢復後，從正確 DNS context重新驗證 Fleet `.45:443`的官方外部 upload path。
- 尚未使用 `imgpkg` 搬移完整 VKS Service / Standard Packages bundles。
- 尚未驗證 Supervisor 與 VKS nodes 對 Depot CA 的 trust。
- 尚未在完全斷網條件下新建另一個 VKS cluster。

因此目前結論是「Software Depot Registry已實際修復並完成 OCI write/read」，不是「完整
air-gap VKS cluster已端到端完成」。下一步須先修好 Fleet DNS/VIP，再從 Admin Host執行
`imgpkg` bundle upload。
