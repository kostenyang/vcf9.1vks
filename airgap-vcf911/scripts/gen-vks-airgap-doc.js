const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, ImageRun, PageBreak, BorderStyle
} = require('docx');

const SHOTS = 'E:\\9.1\\doc-shots\\vks-airgap';
const SUP   = 'E:\\9.1\\doc-shots\\vks-supervisor';
const OUT   = 'E:\\9.1\\VCF911-VKS-AirGap-StepByStep.docx';

const C = { blue: '1F4E79', gray: '595959', red: 'C00000', green: '2E7D32', amber: 'B77E00' };
const W_UI = 600;

const H1 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_1, spacing: { before: 340, after: 160 } });
const H2 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_2, spacing: { before: 260, after: 120 } });
const H3 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_3, spacing: { before: 200, after: 100 } });
const P = (t, o = {}) => new Paragraph({
  children: [new TextRun({ text: t, size: o.size || 21, bold: o.bold, color: o.color, italics: o.italics })],
  spacing: { after: o.after != null ? o.after : 110 }, alignment: o.align });
const CODE = t => new Paragraph({
  children: t.split('\n').map((ln, i) => new TextRun({ text: ln, font: 'Consolas', size: 16, break: i ? 1 : 0 })),
  shading: { type: ShadingType.CLEAR, fill: 'F4F4F4' },
  spacing: { before: 70, after: 70 }, indent: { left: 220 } });
const BULLET = t => new Paragraph({
  children: [new TextRun({ text: t, size: 21 })], bullet: { level: 0 }, spacing: { after: 70 } });
const NOTE = (t, fill, color) => new Paragraph({
  children: [new TextRun({ text: t, size: 20, color: color || C.gray })],
  shading: { type: ShadingType.CLEAR, fill: fill || 'FFF6E5' },
  spacing: { before: 90, after: 90 }, indent: { left: 120, right: 120 },
  border: { left: { style: BorderStyle.SINGLE, size: 18, color: color || C.amber } } });
const PB = () => new Paragraph({ children: [new PageBreak()] });

const TOTAL = 9000;
function table(headers, rows, pct) {
  const widths = pct.map(p => Math.round(TOTAL * p / 100));
  const hdr = new TableRow({ tableHeader: true, children: headers.map((h, i) => new TableCell({
    width: { size: widths[i], type: WidthType.DXA },
    shading: { type: ShadingType.CLEAR, fill: C.blue },
    children: [new Paragraph({ children: [new TextRun({ text: h, bold: true, color: 'FFFFFF', size: 19 })] })] })) });
  const body = rows.map((r, ri) => new TableRow({ children: r.map((c, i) => new TableCell({
    width: { size: widths[i], type: WidthType.DXA },
    shading: ri % 2 ? { type: ShadingType.CLEAR, fill: 'F7F9FC' } : undefined,
    children: [new Paragraph({ children: [new TextRun({ text: String(c), size: 18 })] })] })) }));
  return new Table({ rows: [hdr].concat(body), columnWidths: widths, width: { size: TOTAL, type: WidthType.DXA } });
}
function pngSize(p) { const b = fs.readFileSync(p); return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) }; }
let figNo = 0;
function fig(dir, file, caption, maxW) {
  const p = path.join(dir, file);
  const out = []; figNo++;
  if (fs.existsSync(p)) {
    const { w, h } = pngSize(p); const cw = maxW || W_UI; const ch = Math.round(cw * h / w);
    out.push(new Paragraph({ children: [new ImageRun({ type: 'png', data: fs.readFileSync(p), transformation: { width: cw, height: ch } })],
      alignment: AlignmentType.CENTER, spacing: { before: 140, after: 40 } }));
  } else {
    out.push(new Paragraph({ children: [new TextRun({ text: '[ 缺圖:' + file + ' ]', italics: true, color: C.red, size: 18 })], alignment: AlignmentType.CENTER }));
  }
  out.push(new Paragraph({ children: [new TextRun({ text: '圖 ' + figNo + '\u3000' + caption, size: 18, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 180 } }));
  return out;
}
const F  = (f, c, w) => fig(SHOTS, f, c, w);
const FS = (f, c, w) => fig(SUP, f, c, w);
const cli = f => { const p = path.join(SHOTS, 'cli', f); return fs.existsSync(p) ? fs.readFileSync(p, 'utf8').replace(/\r/g, '').trim() : '[缺:' + f + ']'; };

const doc = new Document({
  styles: { default: {
    heading1: { run: { size: 30, bold: true, color: C.blue }, paragraph: { spacing: { before: 340, after: 160 } } },
    heading2: { run: { size: 25, bold: true, color: C.blue }, paragraph: { spacing: { before: 260, after: 120 } } },
    heading3: { run: { size: 22, bold: true, color: '2E5F8A' }, paragraph: { spacing: { before: 200, after: 100 } } },
    document: { run: { font: 'Microsoft JhengHei', size: 21 } } } },
  sections: [{ properties: { page: { margin: { top: 900, bottom: 900, left: 1000, right: 1000 } } }, children: [

    // 封面
    new Paragraph({ children: [new TextRun({ text: '', size: 24 })], spacing: { after: 1800 } }),
    new Paragraph({ children: [new TextRun({ text: 'VCF 9.1.1 air-gap 環境', size: 44, bold: true, color: C.blue })], alignment: AlignmentType.CENTER }),
    new Paragraph({ children: [new TextRun({ text: 'vSphere Supervisor + VKS 部署實作手冊', size: 36, bold: true, color: C.blue })], alignment: AlignmentType.CENTER, spacing: { after: 300 } }),
    new Paragraph({ children: [new TextRun({ text: 'VDS + Foundation Load Balancer(不使用 Avi)', size: 24, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 160 } }),
    new Paragraph({ children: [new TextRun({ text: '自建 Software Depot 供應 VKr 與 VKS Standard Packages', size: 22, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 900 } }),
    new Paragraph({ children: [new TextRun({ text: '實作日期:2026-09-22 ~ 09-23', size: 21 })], alignment: AlignmentType.CENTER }),
    new Paragraph({ children: [new TextRun({ text: '依據:github.com/vmware/vsphere-supervisor — airgapped/air-gapped-vcf91.md', size: 19, color: C.gray })], alignment: AlignmentType.CENTER }),
    PB(),

    H1('目錄'),
    ...['一、摘要與成果', '二、環境與角色', '三、Step 1:取得 VKr(vSphere Kubernetes release)',
        '四、Step 2:把 VKr 鏡像進自建 Software Depot', '五、Step 3:建立 Content Library',
        '六、Step 4:啟用 Supervisor(VDS + Foundation LB)', '七、Step 5:建立 vSphere Namespace',
        '八、Step 6:開啟 Software Depot 的 OCI 上傳', '九、Step 7:搬移 VKS Standard Packages OCI 映像',
        '十、Step 8:部署 VKS guest cluster', '十一、Step 9:在 guest cluster 安裝 add-on(cert-manager)',
        '十二、踩坑與排錯', '十三、沒有 govc 怎麼做(工具對照)', '附錄 A:指令彙整', '附錄 B:CLI 輸出'].map(t => P(t, { after: 60 })),
    PB(),

    // 一
    H1('一、摘要與成果'),
    NOTE('目標:在完全沒有對外網路的 VCF 9.1.1 環境裡,把 vSphere Supervisor 啟用起來、開出 VKS guest cluster,'
       + '並且讓 guest cluster 能安裝 VKS Standard Packages(cert-manager)。所有映像來源改為「自建 Software Depot」。'
       + '負載平衡器**不使用 Avi**,改用 VCF 9.1 內建的 Foundation Load Balancer。', 'E8F5E9', C.green),
    P('結論:全部成功。', { bold: true, color: C.green }),
    BULLET('Supervisor vcf-m02-sup01:config RUNNING / kubernetes READY,3 台 ESXi 皆為 agent node(spherelet v1.34.5)。'),
    BULLET('VKS guest cluster vks-cl01:v1.36.2+vmware.2,control plane 1 + worker 1,節點取得 workload 網段 IP。'),
    BULLET('cert-manager 1.20.2 由「自建 depot 的 OCI registry」安裝完成,guest cluster 全程無外網。'),
    BULLET('VKr 1.36.2 與 1.35.6 已鏡像進自建 depot(5.9 GB),並以「訂閱式 content library」供 vCenter 同步。'),
    H2('與官方文件的差異'),
    table(['項目', '官方 air-gapped-vcf91.md', '本次實作'],
      [['VKr 來源', 'wp-content.broadcom.com/v2/latest/(Bastion 下載後手動上傳)', '用 depot token 鏡像進自建 depot,再以訂閱式 CL 自動同步(免手動上傳)'],
       ['Supervisor 映像庫', '建議指派 Content Library', '9.1.1 vCenter 已內建 wcpagent + spherelet,不需指派'],
       ['OCI registry', 'VCF Software Depot 內建(9.1 起)', '相同:vcf-m02-fleet01.home.lab/v2/'],
       ['CLI', 'VCF CLI(vcf context / vcf addon)', 'kubectl-vsphere + Carvel CR(VCF CLI 需 portal 下載,未取得)'],
       ['LB', '未指定', 'Foundation Load Balancer(需求:不用 Avi)']],
      [16, 42, 42]),
    PB(),

    // 二
    H1('二、環境與角色'),
    table(['角色', '元件', '位址 / 版本'],
      [['vCenter', 'vcf-m02-vc01.home.lab', '10.0.1.19 / 9.1.1.0-25712839'],
       ['ESXi ×3', 'vcf-m02-esx01~03.home.lab', '10.0.1.14-16 / 9.1.1.0-25714478'],
       ['Supervisor', 'vcf-m02-sup01', 'API 10.0.0.182、FLB VIP 192.168.15.64'],
       ['Software Depot(OCI)', 'vcf-m02-fleet01.home.lab', '10.0.1.23(VCF Fleet)'],
       ['VSP(平台)', 'vcf-m02-vsp01.home.lab', '10.0.0.172'],
       ['自建 HTTP depot', 'vcf9depotserver', '10.0.0.61:8888(/depot)'],
       ['管理網段', 'SDDC-DPortGroup-VM-Mgmt(VLAN 0)', '10.0.0.0/23、gw 10.0.0.1'],
       ['Workload 網段', 'SDDC-Workload-VM(VLAN 5)', '192.168.15.0/24、gw 192.168.15.254'],
       ['DNS / NTP', 'AD / RouterOS', '10.0.0.200 / 10.0.1.254']],
      [22, 38, 40]),
    NOTE('前置(nested 專用):管理與 workload 兩個 dvPortgroup 都要開啟 Promiscuous mode / Forged transmits / MAC address changes,'
       + '否則 Supervisor 控制平面 VM 與 guest cluster 節點會通不到網路。', 'FFF6E5', C.amber),
    PB(),

    // 三
    H1('三、Step 1:取得 VKr(vSphere Kubernetes release)'),
    P('VKr 是 VKS guest cluster 節點的作業系統映像(Photon / Ubuntu),官方 air-gap 文件指定的下載點是:'),
    CODE('https://wp-content.broadcom.com/v2/latest/        # 公開、免 token,本身就是 content library 訂閱 URL\n'
       + '  lib.json / items.json / <item>/item.json + .ovf/.vmdk/.mf/.cert'),
    P('實測:該站列出 138 個 item、涵蓋 k8s v1.16.8 ~ v1.36.2 共 70 個版本,新版有 photon-5 / ubuntu-2204 / ubuntu-2404 三種。'),
    H2('3.1 另一條路:用 VCF depot token 直接抓(本次採用)'),
    P('VCF 的 product version catalog 內有 VKR 元件,用 depot token 即可取得,不需要 activation code:'),
    CODE('# 列出 VKR 全部內容(token-only)\n'
       + 'pwsh My-VcfDepot.v3.ps1 -TokenFile token.txt -Component VKR -Summary\n'
       + '  Components: 1   Files: 1006   Total: 750.38 GB'),
    NOTE('🔴 檔名陷阱:舊版 VKr 用通用檔名 photon-ova.ovf / photon-ova-disk1.vmdk,新版(1.35.6、1.36.x)才是帶版本的 '
       + 'photon-5-amd64-v1.36.2---vmware.2-vkr.3.ovf。一律從 catalog 的 binaries[].fileName 取,不要自己拼 —— '
       + 'dl.broadcom.com 對不存在的路徑回 403(不是 404),拼錯會被誤判成「沒有授權」。', 'FDECEA', C.red),
    P('以 catalog 正確檔名實測 36 個 photon 版本,token 可下載的是「每條支援線的最新 patch + VCF 隨附版」共 5 個:'),
    table(['k8s 版本', '說明'],
      [['v1.36.2+vmware.2-vkr.3', '最新;本次 guest cluster 使用'],
       ['v1.35.6+vmware.2-vkr.3', '1.35 線最新;本次一併鏡像'],
       ['v1.34.9+vmware.2-vkr.4', '1.34 線最新'],
       ['v1.34.2+vmware.2-vkr.2', 'VCF 9.1.0 隨附版'],
       ['v1.33.13+vmware.2-fips-vkr.4', '1.33 線最新']],
      [34, 66]),
    NOTE('要更舊的版本 → 走 wp-content.broadcom.com(連 1.36.1 這種舊 patch 都給)。'
       + 'VCF Download Tool 的 artifacts 命令(--component VKR / VKS_STANDARD_PACKAGES)也能抓,但**只接受 activation code**,'
       + '本 lab 四份 code 全數 403,故改用 token 路徑。', 'FFF6E5', C.amber),
    PB(),

    // 四
    H1('四、Step 2:把 VKr 鏡像進自建 Software Depot'),
    CODE('pwsh My-VcfDepot.v3.ps1 -TokenFile /root/token.txt -Component VKR -Type INSTALL \\\n'
       + '     -FileNameLike "*photon-5-amd64-v1.36.2*" -Download -OutDir /depot\n'
       + 'pwsh My-VcfDepot.v3.ps1 -TokenFile /root/token.txt -Component VKR -Type INSTALL \\\n'
       + '     -FileNameLike "*photon-5-amd64-v1.35.6*" -Download -OutDir /depot'),
    P('下載後會逐檔比對 catalog 的 sha256。結果:'),
    CODE(cli('01-vkr-mirror.txt')),
    H2('4.1 產生 content library 訂閱用的 lib.json / items.json'),
    P('depot 目錄本身只有檔案,要讓 vCenter 用「訂閱式」同步,必須在 VKR 目錄放 lib.json 與 items.json。'
      + 'items.json 直接取 wp-content 的原始條目(只保留要發佈的 item),item.json 鏡像時已一併下載:'),
    CODE('{ "vcspVersion": "2", "contentVersion": "1", "version": "1", "name": "vkr-local",\n'
       + '  "itemsHref": "items.json", "id": "urn:uuid:<uuid>",\n'
       + '  "capabilities": { "transferIn": ["httpGet"], "transferOut": ["httpGet"] } }'),
    CODE('# 放到 /depot/PROD/COMP/VKR/ 之後驗證\n'
       + 'curl -s -o /dev/null -w "%{http_code}\\n" http://10.0.0.61:8888/PROD/COMP/VKR/lib.json   # 200'),
    PB(),

    // 五
    H1('五、Step 3:建立 Content Library'),
    P('兩種都可以,本次兩種都建:'),
    table(['類型', '用途', '建立方式'],
      [['Local(vks-tkr)', '手動 govc library.import 上傳 VKr OVF', 'govc library.create -ds <datastore> vks-tkr'],
       ['Subscribed(vkr-depot)', '訂閱自建 depot,新版自動同步', 'govc library.create -sub <lib.json URL> -sub-autosync=true']],
      [22, 38, 40]),
    CODE(cli('02-content-library.txt')),
    ...F('01-content-libraries.png', 'Content Libraries:vkr-depot(已訂閱)與 vks-tkr(本機)並存'),
    ...F('03-vkr-depot-items.png', 'vkr-depot → OVF & OVA Templates:兩個 VKr 已從自建 depot 同步完成(Stored Locally = 是)'),
    NOTE('🔑 KubernetesRelease(kr)物件**只有用舊 API 指派 content library 才會生成**:\n'
       + 'PATCH /api/vcenter/namespace-management/clusters/{cluster}  {"default_kubernetes_service_content_library":"<libId>"}\n'
       + '只做新的 PATCH supervisors/{id}/workloads/images/settings → 映像進得來,但 kr/osimage 永遠是空的,'
       + '建 cluster 會被 webhook 擋「Missing compatible KR/OSImage」。', 'FDECEA', C.red),
    PB(),

    // 六
    H1('六、Step 4:啟用 Supervisor(VDS + Foundation Load Balancer)'),
    P('vSphere Client → 左上選單 → Supervisor Management → GET STARTED,共 8 步。'
      + '路由是 /ui/app/workload-platform/vsphere-network-introduction(workload-management 這個舊路由在 9.1.1 已不存在)。'),
    ...FS('07-step1-flb.png', 'Step 1:網路堆疊選 vSphere Distributed Switch (VDS),Load Balancer Type 選 Foundation Load Balancer'),
    ...FS('10-step2-filled.png', 'Step 2:CLUSTER DEPLOYMENT 分頁,Supervisor 名稱與叢集;HA 關閉(nested lab)'),
    ...FS('12-step3-storage-set.png', 'Step 3:三個 storage policy 都選 vSAN Default Storage Policy'),
    ...FS('18-step4-done.png', 'Step 4:管理網路 Static、10.0.0.182-186/23、gw 10.0.0.1、DNS 10.0.0.200、NTP 10.0.1.254'),
    ...FS('20-step5-static-pg.png', 'Step 5:Workload 網路選 VLAN 5 的 SDDC-Workload-VM,K8s Service 網段 10.96.0.0/23'),
    ...FS('26-step6-done.png', 'Step 6:Foundation LB — One Arm / Small / HA 1;管理網路名稱 flb-mgmt-net(不可與 Supervisor 管理網路同名),VIP 192.168.15.64-95'),
    ...FS('28-step8-review.png', 'Step 8:Ready to complete 檢視後 FINISH'),
    NOTE('🔴 FINISH 會擋「名稱 SDDC-Workload-VM 必須符合 RFC-1123」:workload 的 Network Name 會自動帶入 port group 名稱,'
       + '含大寫就過不了 → 改成全小寫 sddc-workload-vm(port group 本身不用改名)。', 'FDECEA', C.red),
    ...FS('16-deploy-success-mtu1500.png', '(參考)Installer 類似流程的完成畫面;Supervisor 啟用約 27 分鐘後 config_status=RUNNING'),
    H2('6.1 主機節點卡在 Configuring 的處理'),
    P('Supervisor 顯示 RUNNING、但 Host Config Status 一直是 Configuring、kubernetes_status=WARNING,'
      + '且 kubectl get nodes 只看得到 control plane VM —— 表示 ESXi 主機沒有裝上 spherelet。'),
    CODE('# 確認 desired solution 與 compliance\n'
       + 'GET /api/esx/settings/clusters/{c}/software/solutions   → com.vmware.vsphere-wcp (VMware-Spherelet-1-34)\n'
       + 'GET /api/esx/settings/clusters/{c}/software/compliance  → NON_COMPLIANT\n'
       + 'POST /api/esx/settings/clusters/{c}/software?action=apply&vmw-task=true {"accept_eula":true}\n'
       + '  → FAILED: Health Check for \'vcf-m02-esx03\' failed   ← vSAN 健康檢查擋住 remediation'),
    CODE('# 解法(nested lab):把非 green 的 vSAN 檢查靜音後重跑 apply\n'
       + '$hs.VsanHealthSetVsanClusterSilentChecks($cl.ExtensionData.MoRef, @("nvmeonhcl","perfsvcstatus","vsanenablesupportinsight"), $null)'),
    P('重跑後約 4 分鐘完成,三台主機變成 Ready/agent,Supervisor kubernetes_status 轉為 READY。'),
    ...FS('35-supervisor-hostconfig.png', '修復後:Config Status 與 Host Config Status 都是 Running'),
    PB(),

    // 七
    H1('七、Step 5:建立 vSphere Namespace'),
    CODE('POST /api/vcenter/namespaces/instances/v2\n'
       + '{\n'
       + '  "supervisor": "<supervisor-id>",          // 注意:不是 "cluster"\n'
       + '  "namespace": "vks-ns01",\n'
       + '  "storage_specs": [ { "policy": "<vSAN Default Storage Policy id>" } ],\n'
       + '  "vm_service_spec": {\n'
       + '    "content_libraries": [ "<vks-tkr library id>" ],\n'
       + '    "vm_classes": [ "best-effort-small", "best-effort-medium", "guaranteed-small" ]\n'
       + '  }\n'
       + '}'),
    ...F('05-namespace-vks-ns01.png', 'vks-ns01:Config Status Running / Kubernetes Status Active,已關聯 1 個 content library 與 3 個 VM class'),
    PB(),

    // 八
    H1('八、Step 6:開啟 Software Depot 的 OCI 上傳'),
    P('VCF 9.1 的 Software Depot(跑在 VCF Fleet 上)內建一個 OCI registry,提供 Supervisor Services 與 VKS Standard Packages 的映像。'
      + '預設**只讀**,直接 push 會得到 405 Method Not Allowed:'),
    CODE('imgpkg: Error: POST https://vcf-m02-fleet01.home.lab/v2/.../blobs/uploads/:\n'
       + '        unexpected status code 405 Method Not Allowed (openresty)'),
    P('官方提供 toggle 腳本(vsphere-supervisor repo / airgapped/scripts),需要 VSP FQDN 與 VSP admin 帳密:'),
    CODE('./toggle_software_depot_oci_image_upload.sh enable \\\n'
       + '    --vsp-host       vcf-m02-vsp01.home.lab \\\n'
       + '    --admin-username admin \\\n'
       + "    --admin-password '<password>'\n\n"
       + '# 內部動作:POST /api/v1/identity/token(x-www-form-urlencoded, grant_type=password)\n'
       + '#           → 找 components 裡的 vcf-fleet-depot → POST components/{id}?action=apply\n'
       + '#             {"spec":{"configuration":{"oci":{"offlineWriteEnabled":true}}}}\n'
       + 'Software Depot config update is success!'),
    NOTE('⚠ 官方明確要求:所有映像上傳完成後,要再跑一次 disable 關掉 —— 因為這個上傳通道**沒有認證**。', 'FFF6E5', C.amber),
    NOTE('Windows / Git-Bash 執行這個腳本時不要設 MSYS_NO_PATHCONV=1,否則 curl 讀不到 /tmp 的 payload 檔(Failed to open)。', 'FFF6E5', C.amber),
    PB(),

    // 九
    H1('九、Step 7:搬移 VKS Standard Packages 的 OCI 映像'),
    P('先確認 guest cluster 需要哪個版本 —— VKS 會在 guest cluster 內建一個 PackageRepository,air-gap 時它會 timeout,'
      + '錯誤訊息就直接告訴你來源與版本:'),
    CODE('$ kubectl get pkgr -n vmware-system-tkg\n'
       + 'vks-addons-3.7.0-20260618   Reconcile failed: Fetching resources: Error\n\n'
       + 'image: projects.packages.broadcom.com/vsphere/supervisor/vks-standard-packages/3.7.0-20260618/vks-addons:3.7.0-20260618\n'
       + 'err:   Get "https://projects.packages.broadcom.com/v2/": dial tcp 52.37.255.221:443: i/o timeout'),
    P('用官方 oci_image_depot_migrator.py(需要 imgpkg + python3)搬進自建 depot。有網路的 Bastion 可以一次做完 download+upload:'),
    CODE('# 先確認會落在哪個 repo(腳本內建 projects→depot 的路徑對應表)\n'
       + 'python oci_image_depot_migrator.py map-target-repo \\\n'
       + '  -s projects.packages.broadcom.com/vsphere/supervisor/vks-standard-packages/3.7.0-20260618/vks-addons:3.7.0-20260618 \\\n'
       + '  -t vcf-m02-fleet01.home.lab\n'
       + '→ vcf-m02-fleet01.home.lab/vks-standard-packages/ga/3.7.0-20260618/vks-addons\n\n'
       + '# 實際搬移(download → tar → upload;跨氣隙時拆成 download / upload 兩段)\n'
       + 'python oci_image_depot_migrator.py copy -s <同上> -t vcf-m02-fleet01.home.lab --work-dir .'),
    CODE(cli('03-oci-depot.txt')),
    PB(),

    // 十
    H1('十、Step 8:部署 VKS guest cluster'),
    H2('10.1 取得 kubectl 與登入'),
    CODE('# Supervisor 首頁即可下載(9.1.0 起 kubectl-vsphere 已標記 deprecated,官方建議改用 VCF CLI vcf context)\n'
       + 'curl -sk https://<supervisor-api>/wcp/plugin/windows-amd64/vsphere-plugin.zip -o vsphere-plugin.zip\n\n'
       + 'KUBECTL_VSPHERE_PASSWORD=<pw> kubectl-vsphere login --server=10.0.0.182 \\\n'
       + '    --insecure-skip-tls-verify --vsphere-username administrator@vsphere.local'),
    H2('10.2 Cluster YAML(v1beta2)'),
    CODE('apiVersion: cluster.x-k8s.io/v1beta2\n'
       + 'kind: Cluster\n'
       + 'metadata:\n'
       + '  name: vks-cl01\n'
       + '  namespace: vks-ns01\n'
       + 'spec:\n'
       + '  clusterNetwork:\n'
       + '    pods:     { cidrBlocks: ["172.20.0.0/16"] }\n'
       + '    services: { cidrBlocks: ["10.96.0.0/16"] }\n'
       + '  topology:\n'
       + '    classRef:                      # v1beta2 是 classRef.name,不是 class\n'
       + '      name: builtin-generic-v3.3.0 # 套用時會自動升到最新相容的 v3.7.0\n'
       + '    version: v1.36.2+vmware.2-vkr.3\n'
       + '    controlPlane: { replicas: 1 }\n'
       + '    workers:\n'
       + '      machineDeployments:\n'
       + '        - class: node-pool\n'
       + '          name: np1\n'
       + '          replicas: 1\n'
       + '    variables:\n'
       + '      - name: vmClass\n'
       + '        value: best-effort-small\n'
       + '      - name: storageClass\n'
       + '        value: vsan-default-storage-policy'),
    CODE('kubectl apply -f vks-cluster01.yaml\nkubectl get cluster -n vks-ns01'),
    ...F('07-vks-cluster.png', 'Namespace → Compute → Kubernetes clusters:vks-cl01 Available=True、Distribution Version v1.36.2---vmware.2-vkr.3'),
    NOTE('版本要對得上 Kubernetes Service 的版本:\n'
       + 'GET /api/vcenter/namespace-management/supervisor-services/tkg.vsphere.vmware.com/versions → 3.7.0-embedded+v1.36\n'
       + '舊的 VKr(例如 1.32.7)KR 會是 Ready=False / Compatible=False(CompatibilityError,label incompatible),'
       + '換成 1.36.x 才會 True/True。', 'FDECEA', C.red),
    PB(),

    // 十一
    H1('十一、Step 9:在 guest cluster 安裝 add-on(cert-manager)'),
    H2('11.1 讓 guest cluster 信任 depot 憑證'),
    P('depot 的憑證由 vCenter VMCA 簽發,guest cluster 節點預設不信任。用 ClusterClass 的 osConfiguration 變數加進系統信任區(會觸發節點滾動更新):'),
    CODE('# 取得 VMCA 根憑證\n'
       + 'curl -sk https://<vcenter>/certs/download.zip -o vc-certs.zip   # 取 certs/lin/<hash>.0\n\n'
       + '# 以 JSON patch 只新增一個變數(不要整份 apply,會掉 webhook 自動加的 bootstrapAddons)\n'
       + 'kubectl patch cluster vks-cl01 -n vks-ns01 --type=json -p \'[{"op":"add",\n'
       + '  "path":"/spec/topology/variables/-","value":{"name":"osConfiguration","value":\n'
       + '  {"trust":{"additionalTrustedCAs":[{"caCert":{"content":"-----BEGIN CERTIFICATE-----..."}}]}}}}]\''),
    H2('11.2 把 PackageRepository 指到自建 depot'),
    CODE('# 內建那個(vmware-system-tkg)改成 depot 位址\n'
       + 'kubectl patch pkgr vks-addons-3.7.0-20260618 -n vmware-system-tkg --type=merge -p \\\n'
       + '  \'{"spec":{"fetch":{"imgpkgBundle":{"image":"vcf-m02-fleet01.home.lab/vks-standard-packages/ga/3.7.0-20260618/vks-addons:3.7.0-20260618"}}}}\''),
    NOTE('🔑 kapp-controller 的 packaging-global-namespace 是 **tkg-system**,但內建 repository 把 Package 裝在 vmware-system-tkg,'
       + '所以其他 namespace 看不到套件(PackageInstall 會報 Package ... not found)。'
       + '要在 tkg-system 另外建一個 PackageRepository 指向同一個 bundle,套件才會全叢集可見。', 'FDECEA', C.red),
    CODE('apiVersion: packaging.carvel.dev/v1alpha1\n'
       + 'kind: PackageRepository\n'
       + 'metadata:\n'
       + '  name: vks-addons-depot\n'
       + '  namespace: tkg-system\n'
       + 'spec:\n'
       + '  fetch:\n'
       + '    imgpkgBundle:\n'
       + '      image: vcf-m02-fleet01.home.lab/vks-standard-packages/ga/3.7.0-20260618/vks-addons:3.7.0-20260618'),
    H2('11.3 安裝 cert-manager'),
    CODE('apiVersion: packaging.carvel.dev/v1alpha1\n'
       + 'kind: PackageInstall\n'
       + 'metadata:\n'
       + '  name: cert-manager\n'
       + '  namespace: vks-addons\n'
       + 'spec:\n'
       + '  serviceAccountName: cert-manager-sa      # 需搭配 cluster-admin ClusterRoleBinding\n'
       + '  packageRef:\n'
       + '    refName: cert-manager.kubernetes.vmware.com\n'
       + '    versionSelection:\n'
       + '      constraints: 1.20.2+vmware.1-vks.1'),
    P('官方使用 VCF CLI 的等價指令(需先從 Broadcom portal 下載 VCF CLI 與 plugin bundle):'),
    CODE('vcf context create supervisor1 --endpoint https://<supervisor-api> --username administrator@vsphere.local --type k8s\n'
       + 'vcf context use supervisor1:vks-ns01:vks-cl01\n'
       + 'vcf addon install cert-manager --addon-release-name cert-manager.kubernetes.vmware.com.1.20.2-vmware.1-vks.1 \\\n'
       + '    --namespace vks-ns01 --cluster-name vks-cl01'),
    CODE(cli('04-addon-install.txt')),
    PB(),

    // 十二
    H1('十二、踩坑與排錯'),
    table(['#', '症狀', '原因 / 處置'],
      [['1', 'dl.broadcom.com 回 403', '路徑不存在也是 403(不是 404)。舊版 VKr 檔名是 photon-ova.ovf,新版才帶版本 → 一律讀 catalog 的 fileName'],
       ['2', 'vcf-download-tool artifacts 失敗', 'artifacts 只吃 activation code(binaries 才吃 token);code 過期就 403,與指令無關'],
       ['3', '建 cluster 被擋 Missing compatible KR/OSImage', 'KR/OSImage 只有舊 API default_kubernetes_service_content_library 會生成'],
       ['4', 'KR 是 Ready=False / Compatible=False', 'VKr 版本與 Kubernetes Service 版本不合(本環境 3.7.0-embedded+v1.36 → 要 1.36.x)'],
       ['5', 'imgpkg push 得到 405', 'Software Depot OCI registry 預設唯讀 → 跑 toggle_software_depot_oci_image_upload.sh enable'],
       ['6', 'Supervisor 精靈 FINISH 被擋 RFC-1123', 'workload Network Name 自動帶 port group 名(含大寫)→ 改小寫'],
       ['7', 'Host Config Status 卡 Configuring 0/12', 'spherelet 的 vLCM remediation 被 vSAN 健康檢查擋 → 靜音非 green 檢查再 apply'],
       ['8', 'PackageInstall 報 Package not found', 'Package 裝在 vmware-system-tkg,但 global namespace 是 tkg-system → 在 tkg-system 另建 repository'],
       ['9', 'kubectl apply -f cluster.yaml 被 webhook 擋', '整份 apply 會掉 webhook 自動加的 bootstrapAddons → 改用 JSON patch 增量修改'],
       ['10', 'toggle 腳本 curl 讀不到檔', 'Git-Bash 下不要設 MSYS_NO_PATHCONV=1']],
      [5, 37, 58]),
    PB(),

    H1('十三、沒有 govc 怎麼做(工具對照)'),
    P("本手冊指令以 govc 示範,但客戶現場常常沒有這支工具。以下是等價做法 —— PowerCLI 與 vSphere Client UI 不需要額外安裝任何東西。"),
    H2('13.1 連線方式'),
    CODE("# PowerCLI\nConnect-VIServer <vc> -User administrator@vsphere.local -Password '<pw>'\n\n# REST(vSphere Automation API)\nS=$(curl -sk -X POST -u 'administrator@vsphere.local:<pw>' https://<vc>/api/session | tr -d '\"')\nH=\"vmware-api-session-id: $S\"\n\n# govc(單檔 exe)\nexport GOVC_URL='https://<vc>' GOVC_USERNAME='administrator@vsphere.local' GOVC_PASSWORD='<pw>' GOVC_INSECURE=1\nexport MSYS_NO_PATHCONV=1      # Git-Bash 必加,否則 inventory 路徑會被轉成 C:\\..."),
    H2('13.2 對照表'),
    table(['動作', 'govc', 'PowerCLI', 'UI / REST'],
      [["建訂閱式 Content Library", "library.create -sub <lib.json> -sub-autosync=true -ds <ds> <name>", "New-ContentLibrary -Name <n> -Datastore <ds> -SubscriptionUrl <url> -AutomaticSync", "UI:Content Libraries → CREATE → Subscribed;REST:POST /api/content/subscribed-library"], ["建本機 Content Library", "library.create -ds <ds> <name>", "New-ContentLibrary -Name <n> -Datastore <ds>", "UI:CREATE → Local;REST:POST /api/content/local-library"], ["匯入 OVF", "library.import -n <item> <lib> 'E:\\path\\x.ovf'", "New-ContentLibraryItem -ContentLibrary <lib> -Name <item> -ItemType ovf -Files 'E:\\path\\x.ovf'", "UI:CL → ACTIONS → Import Item(.ovf/.vmdk/.mf/.cert 要一起選);REST 需四步"], ["列 CL / item", "library.ls;library.ls '/<lib>/*'", "Get-ContentLibrary / Get-ContentLibraryItem", "REST:GET /api/content/local-library、GET /api/content/library/item?library_id="], ["指派 K8s 映像庫", "無對應", "無對應", "UI:Supervisor → Configure → Kubernetes Services → Content Library → EDIT;REST:PATCH namespace-management/clusters/{c}"], ["建 workload port group", "dvs.portgroup.add -dvs <vds> -type earlyBinding -vlan 5 <name>", "New-VDPortgroup -VDSwitch <vds> -Name <n> -VlanId 5", "UI:Networking → VDS → ACTIONS → Distributed Port Group → New"], ["promiscuous / forged / MAC", "繁瑣", "ReconfigureDVPortgroup_Task + DVSSecurityPolicy", "UI:dvPortgroup → Edit → Security(三項 Accept)"], ["主機 esxcli", "host.esxcli -host.ip <ip> <cmd>", "(Get-EsxCli -VMHost <h> -V2).<ns>.<cmd>.Invoke()", "ESXi Shell / SSH"], ["VM 內執行指令", "guest.run -vm <vm> -- <cmd>", "Invoke-VMScript -VM <vm> -ScriptText '<cmd>'", "Guest Operations API"], ["建 vSphere Namespace", "無對應", "無對應", "UI:Namespaces → CREATE NAMESPACE;REST:POST /api/vcenter/namespaces/instances/v2"], ["vLCM remediate(spherelet)", "無對應", "vLCM cmdlet(有限)", "UI:Cluster → Updates → Image → REMEDIATE ALL;REST:software?action=apply"], ["guest cluster / add-on", "無對應", "無對應", "kubectl(Cluster / PackageRepository / PackageInstall)"]],
      [15, 25, 26, 34]),
    H2('13.3 REST 實例(本 lab 實測格式)'),
    CODE("curl -sk -X POST -H \"$H\" -H 'Content-Type: application/json' \\\n  https://<vc>/api/content/subscribed-library -d '{\n    \"name\": \"vkr-depot\",\n    \"type\": \"SUBSCRIBED\",\n    \"storage_backings\": [ { \"type\": \"DATASTORE\", \"datastore_id\": \"datastore-15\" } ],\n    \"subscription_info\": {\n      \"subscription_url\": \"http://<depot>:8888/PROD/COMP/VKR/lib.json\",\n      \"authentication_method\": \"NONE\",\n      \"automatic_sync_enabled\": true,\n      \"on_demand\": false } }'\n\n# 查 moref\ncurl -sk -H \"$H\" https://<vc>/api/vcenter/datastore | jq -r '.[]|\"\\(.datastore)  \\(.name)\"'\n#   datastore-15  m01-cl01-ds-vsan01\ncurl -sk -H \"$H\" https://<vc>/api/vcenter/cluster   | jq -r '.[]|\"\\(.cluster)  \\(.name)\"'\n#   domain-c9  m01-cl01"),
    NOTE("現場沒有 govc 的建議組合:Content Library 建立與 OVF 匯入用 PowerCLI(一行完成,REST 要四步);Supervisor / Namespace / 映像庫指派這些本來就沒有 govc 對應的動作用 UI 或 REST;guest cluster 與 add-on 一律 kubectl。", 'E8F5E9', C.green),
    PB(),

    // 附錄
    H1('附錄 A:指令彙整'),
    CODE('### Step 1-2  VKr 取得與鏡像\n'
       + 'pwsh My-VcfDepot.v3.ps1 -TokenFile token.txt -Component VKR -Summary\n'
       + 'pwsh My-VcfDepot.v3.ps1 -TokenFile token.txt -Component VKR -Type INSTALL \\\n'
       + '     -FileNameLike "*photon-5-amd64-v1.36.2*" -Download -OutDir /depot\n\n'
       + '### Step 3  Content Library\n'
       + 'govc library.create -ds <ds> vks-tkr\n'
       + "govc library.import -n <item-name> vks-tkr 'E:\\path\\photon-ova.ovf'\n"
       + 'govc library.create -sub http://10.0.0.61:8888/PROD/COMP/VKR/lib.json -sub-autosync=true -ds <ds> vkr-depot\n'
       + 'curl -X PATCH /api/vcenter/namespace-management/clusters/{cluster} \\\n'
       + '     -d \'{"default_kubernetes_service_content_library":"<libId>"}\'\n\n'
       + '### Step 5  Namespace\n'
       + 'curl -X POST /api/vcenter/namespaces/instances/v2 -d @ns.json\n\n'
       + '### Step 6-7  OCI\n'
       + './toggle_software_depot_oci_image_upload.sh enable --vsp-host <vsp> --admin-username admin --admin-password <pw>\n'
       + 'python oci_image_depot_migrator.py copy -s <projects.packages...> -t <fleet-fqdn> --work-dir .\n'
       + 'curl -sk https://<fleet-fqdn>/v2/_catalog\n'
       + './toggle_software_depot_oci_image_upload.sh disable --vsp-host <vsp> ...   # 完成後關閉\n\n'
       + '### Step 8-9  Cluster 與 add-on\n'
       + 'kubectl apply -f vks-cluster01.yaml\n'
       + 'kubectl patch cluster vks-cl01 -n vks-ns01 --type=json --patch-file=patch-trust.json\n'
       + 'kubectl apply -f vks-addons-repo-global.yaml\n'
       + 'kubectl apply -f cert-manager-install.yaml\n'
       + 'kubectl get pkgi -n vks-addons && kubectl get pods -n cert-manager'),
    PB(),
    H1('附錄 B:CLI 輸出'),
    H2('B.1 VKr 鏡像'),
    CODE(cli('01-vkr-mirror.txt')),
    H2('B.2 Content Library'),
    CODE(cli('02-content-library.txt')),
    H2('B.3 Software Depot OCI'),
    CODE(cli('03-oci-depot.txt')),
    H2('B.4 Add-on 安裝'),
    CODE(cli('04-addon-install.txt')),
  ] }]
});

Packer.toBuffer(doc).then(b => { fs.writeFileSync(OUT, b); console.log('written', OUT, b.length, 'bytes, figures:', figNo); });
