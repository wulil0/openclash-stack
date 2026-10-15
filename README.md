# OpenClash 规则整合方案（OpenClash Rules Stack）

把 4 个互补的 OpenClash 规则项目整合成一套开箱即用的方案：底座一次配好，去广告、AI 专项分流、随手加规则各就其位，互不打架。

---

## 一、使用了哪些项目

| # | 项目 | 仓库 | 许可 | 本方案用它做什么 | 数据更新频率 |
|---|---|---|---|---|---|
| 1 | Aethersailor/Custom_OpenClash_Rules | https://github.com/Aethersailor/Custom_OpenClash_Rules | CC-BY-SA-4.0 | **底座**：保姆级设置方案＋订阅转换模板（Fake-IP、DNS 防污染防泄漏、国内外分流、策略组） | GeoIP/GeoSite 由 OpenClash 每日自动拉取 |
| 2 | AyraHikari/openclash_adguard | https://github.com/AyraHikari/openclash_adguard | 见上游仓库 | **去广告**：AdGuard / EasyList 规则转成的 Clash classical 规则 | GitHub Actions 每 12 小时自动更新 |
| 3 | rorojiao/clash_rules | https://github.com/rorojiao/clash_rules | 见上游仓库 | **AI 专项**：50+ 家 AI 服务域名规则＋链式代理（dialer-proxy）模板 | 每天自动更新 |
| 4 | Zeral-Zhang/openclash-helper | https://github.com/Zeral-Zhang/openclash-helper | 见上游仓库 | **随手加规则**：浏览器插件，任意网页右键加直连/代理规则 | 手动，随用随加 |

> 注意：不要用 `guyue2005/custom_openclash_rules` 那个 fork，它是 2025 年 11 月从 Aethersailor 原项目 fork 出来后就没再更新的；直接用 Aethersailor 的原项目。

本仓库为原创整合文档与配置片段，不复制上游仓库内容。本仓库新增内容采用 MIT 许可。

---

## 二、技术说明

### 2.1 整体架构

```
                ┌─ 国内域名 ─→ 运营商 DNS 直连（绕过内核，零影响）
用户流量 ─→ OpenClash (Mihomo 内核, Fake-IP 模式)
                └─ 国外流量 ─→ 规则引擎按顺序匹配 ─→ 策略组
                        │
                        ├─ ① adguard_allow → DIRECT（广告白名单，先放行）
                        ├─ ② adguard_block / oisd_small → REJECT（广告拦截）
                        ├─ ③ ai-services → AI服务（AI 站点走专用分组）
                        └─ ④ 底座规则（GeoSite 分流、流媒体、游戏等）→ 各自的分流组
```

规则引擎是**按顺序、首个命中即停止**的，所以 `rules` 列表的顺序就是优先级。本方案的三条规则应放在用户自有规则之前、底座通用规则之前。

### 2.2 rule-provider 工作原理

`rule-providers` 是 Mihomo 的远程规则集机制：

```yaml
adguard_block:
  type: http            # 从 URL 下载
  behavior: classical   # 规则格式（见 2.3）
  path: ./ruleset/adguard_block.yaml   # 本地缓存路径（相对配置文件目录）
  url: https://raw.githubusercontent.com/...  # 上游地址
  interval: 43200       # 更新间隔（秒），43200 = 12 小时
```

OpenClash 启动时下载一次，之后每隔 `interval` 自动更新并热重载，无需重启。本地缓存保证断网时仍有规则可用。

### 2.3 behavior 的三种格式（关键）

| behavior | payload 内容 | 说明 |
|---|---|---|
| `classical` | 完整规则行，如 `DOMAIN-SUFFIX,google.com` | 最通用，本方案三个 provider 全用这个 |
| `domain` | 纯域名，如 `google.com`（**不带**类型前缀） | 写错会导致整行被当成字面域名，永远匹配不上 |
| `ipcidr` | IP 段，如 `1.1.1.1/32` | 用于 IP 规则集 |

**实测坑**：`rorojiao/clash_rules` 的 README 里 `ai-services.yaml` 写的是 `behavior: domain`，但文件内容实际是 classical 格式（条目全带 `DOMAIN-SUFFIX,` 前缀，158 条已逐条验证）。若按 README 配成 `domain`，Mihomo 会把 `DOMAIN-SUFFIX,ai.com` 当成一个字面域名去匹配——**永远命中不了**，且不报错。本方案已修正为 `classical`。

### 2.4 为什么 allow 必须在 block 之前

OpenClash/Mihomo 不支持在**单个**规则集内写例外（allow 盖住 block）。AyraHikari 因此把规则拆成两个文件：`adguard_allow.yaml`（244 条白名单）和 `adguard_block.yaml`（27.4 万条黑名单）。引用时白名单必须在前：

```yaml
rules:
  - RULE-SET,adguard_allow,DIRECT   # 先放行：避免误杀
  - RULE-SET,adguard_block,REJECT  # 再拦截
```

顺序反了会导致白名单域名也被拦截。

### 2.5 内存取舍

| 黑名单 | 条目数 | 文件大小 | 适用 |
|---|---|---|---|
| oisd_small（默认） | 约 5.6 万条 | 2.1MB | 小内存路由器（Redmi AX3000 256MB 等）无压力 |
| adguard_block（完整版） | 约 27.4 万条 | 10.7MB | 内存 ≥512MB 的设备，拦截更全 |

Mihomo 会把规则集解析后常驻内存，27 万条规则约多占几十 MB 且拖慢启动。默认配置用 oisd_small；内存充足时换 `config/rule-providers-full.yaml`。

### 2.6 链式代理（dialer-proxy，可选）

```
[你的设备] → OpenClash → [前置中转] → [AI 出口] → AI 服务
                              ↑              ↑
                    ISP 只看到到这里的连接   AI 服务看到的是这个 IP
```

把 `proxies` 里出口节点的 `dialer-proxy` 指向前置节点，即可让 AI 流量单独走一条干净的出口（例如美国原生 IP），而日常流量走香港/日本。配置示例见 `docs/03-AI专项.md`。

### 2.7 对底座的依赖

本方案假设底座已按 Aethersailor 的 Wiki 配好（Fake-IP 模式），并满足：

- 存在名为 `AI服务` 的策略组（底座模板自带；没有的话用本仓库配置里注释掉的 `proxy-groups` 片段补上）；
- 不要再叠其他 DNS 插件（底座已处理 DNS 防污染防泄漏，"套娃"反而出问题）；
- 广告过滤**不要**按底座旧教程开（2025-07 已停用，会导致 dnsmasq 故障），去广告走本方案的 rule-provider。

---

## 三、使用说明

### 3.1 前置条件

- OpenWrt 路由器，已安装 OpenClash 插件；
- 有可用的代理订阅；
- 按 `docs/01-底座.md` 把底座配好（约 10 分钟，Wiki 图文教程）。

### 3.2 接入方式 A：手动合并（推荐新手）

1. 打开 OpenClash → 配置订阅 → 找到当前使用的配置文件，或直接编辑 `/etc/openclash/config/config.yaml`。
2. 把 `config/rule-providers.yaml` 中的 `rule-providers:` 整段合并进配置文件的 `rule-providers:`（没有则新建）。
3. 把 `rules:` 下的三条按顺序插入到配置文件 `rules:` 列表的**最前面**（在你自己的自定义规则之前）。
4. 如配置里没有 `AI服务` 分组，取消 `rule-providers.yaml` 底部注释掉的 `proxy-groups` 片段的注释，一并合并。
5. OpenClash → 保存 → 应用配置。去「规则集」页面确认三个 provider 显示"已下载"。

### 3.3 接入方式 B：远程覆写（进阶）

1. 把 `config/overwrite-example.yaml` 的注释取消、按实际情况改好，放到你自己的可访问 URL（如 GitHub raw）。
2. OpenClash → 覆写设置 → 添加该 URL，应用。
3. 覆写方式适合多设备共用一套配置；改动先在本地验证再推。

### 3.4 验证是否生效

1. **规则集已加载**：OpenClash → 规则集，三个 provider 状态正常、无报错。
2. **去广告**：访问 [d3ward.github.io/toolz/adblock.html](https://d3ward.github.io/toolz/adblock.html) 看拦截率。
3. **AI 分流**：访问 `claude.ai` 等 AI 站点，去 OpenClash → 连接记录，确认走了 `AI服务` 分组。
4. **日志排错**：OpenClash → 运行日志，搜 `RULE-SET` 看规则是否被正确引用；provider 下载失败会显示 HTTP 错误码。

### 3.5 完整版 / 轻量版切换

- 默认 `rule-providers.yaml`（轻量，oisd small）→ 想拦截更全时，换成 `rule-providers-full.yaml` 的内容（adguard_block），**二选一，不要同时用**。
- 切换后在 OpenClash 里重新应用配置，规则集会自动重新下载。

### 3.6 日常维护

- 上游规则自动更新（adguard 每 12 小时、oisd_small 和 ai-services 每天），无需手动干预。
- 上游挂了或换地址时，跑 `scripts/check-upstream.sh` 检查连通性：
  ```bash
  bash scripts/check-upstream.sh
  ```
- 遇到分流不对的冷门站：用 openclash-helper 浏览器插件右键加规则（见 `docs/04-随手加规则.md`），或按底座文档用 TG 机器人提交域名。

### 3.7 常见问题

| 现象 | 排查 |
|---|---|
| OpenClash 启动报错找不到 `AI服务` | 配置里没有该分组，取消 `rule-providers.yaml` 底部注释的 `proxy-groups` 片段 |
| 广告白名单没生效 | 检查 `adguard_allow` 是否在 `adguard_block` **之前** |
| AI 站点没走 AI 分组 | 确认 `RULE-SET,ai-services,AI服务` 在底座通用规则之前；去连接记录看实际命中 |
| 规则集下载失败 | 路由器能否直连 raw.githubusercontent.com；跑 `check-upstream.sh` 定位 |
| 内存占用高 / 启动慢 | 换回轻量版（oisd small）；检查是否误同时用了完整版和轻量版 |

---

## 四、文件说明

```
openclash-stack/
├── README.md                  # 本文件：项目、技術、使用说明
├── config/
│   ├── rule-providers.yaml      # 默认（轻量）：去广告黑名单用 oisd small（2.1MB）
│   ├── rule-providers-full.yaml # 完整版：去广告黑名单用 adguard_block（10.7MB/27万条）
│   └── overwrite-example.yaml   # 覆写示例：在 Aethersailor 覆写基础上叠加本方案
├── docs/
│   ├── 01-底座.md             # 底座设置要点
│   ├── 02-去广告.md           # 去广告接入说明与内存取舍
│   ├── 03-AI专项.md           # AI 规则与链式代理
│   └── 04-随手加规则.md       # helper 插件使用
└── scripts/
    └── check-upstream.sh      # 检查上游规则源是否可达
```
