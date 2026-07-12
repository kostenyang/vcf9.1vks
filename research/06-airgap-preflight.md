# 06 — VCF 9.1 VKS air-gap preflight（2026-07-12）

本次新增 [`../airgap/`](../airgap/) 工具並從 Codex 主機對現有 lab 做**唯讀**驗證；沒有安裝
Supervisor Service、上傳 OCI image 或變更任何 VCF 資源。

## 已驗證

| 測項 | 結果 |
|---|---|
| `airgap_tool.py` unit tests | PASS（5/5）|
| example config schema / credential guard | PASS |
| download / upload command generation | PASS |
| vCenter `192.168.114.11:443` | TCP PASS（unsandboxed host network）|
| 現有 download server `172.16.10.50:443` | TCP PASS |
| `https://172.16.10.50/v2/` | **HTTP 404** |

## 關鍵判讀

`172.16.10.50` 現在是存放 VCF download-tool binaries 的 nginx/depot server，但 `/v2/` 回 404，
所以它**不是目前可供 VKS 使用的 OCI Registry endpoint**。不可把它直接填入
`airgap/config.json` 的 `depot_fqdn`。

VCF 9.1 air-gap 下一步必須先從 VCF Fleet / Software Depot UI 或 API 取得 distribution registry
的實際 FQDN，並確認：

```text
GET https://<distribution-registry-fqdn>/v2/
```

回覆 HTTP 200，或未登入時回 HTTP 401。取得正確 FQDN 後，再從 air-gap Admin Host 執行：

```bash
python3 airgap_tool.py --config config.json check
```

## 尚未聲稱完成

- 尚未取得 Software Depot distribution registry FQDN。
- 尚未搬移 VKS Service / Standard Packages OCI bundles。
- 尚未驗證 Supervisor 與 VKS nodes 對 Depot CA 的 trust。
- 尚未在完全斷網條件下新建另一個 VKS cluster。

因此目前結論是「工具與管理路徑 preflight 已驗證」，不是「air-gap VKS 已端到端完成」。
