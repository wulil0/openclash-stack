# OpenClash 规则整合方案（OpenClash Rules Stack）

在既有 OpenClash/Mihomo 底座上叠加广告过滤与精确 AI 分流。此仓库提供规则片段和 OpenClash 覆写模块，**不是独立可运行的订阅配置**；部署前须核对策略组、备份与回滚。

---

## 一、使用了哪些项目

| # | 项目 | 仓库 | 许可 | 本方案用它做什么 | 数据更新频率 |
|---|---|---|---|---|---|
| 1 | Aethersailor/Custom_OpenClash_Rules | https://github.com/Aethersailor/Custom_OpenClash_Rules | CC-BY-SA-4.0 | **底座**：保姆级设置方案＋订阅转换模板（Fake-IP、DNS 防污染防泄漏、国内外分流、策略组） | GeoIP/GeoSite 由 OpenClash 每日自动拉取 |
| 2 | AyraHikari/openclash_adguard | https://github.com/AyraHikari/openclash_adguard | 见上游仓库 | **去广告**：AdGuard / EasyList 规则转成的 Clash classical 规则 | GitHub Actions 每 12 小时自动更新 |
| 3 | rorojiao/clash_rules | https://github.com/rorojiao/clash_rules | 见上游仓库 | **AI 专项**：提供可选广覆盖上游规则和链式代理参考；默认使用更精确的内联清单 | 默认内联清单需手动维护 |
| 4 | Zeral-Zhang/openclash-helper | https://github.com/Zeral-Zhang/openclash-helper | 见上游仓库 | **随手加规则**：浏览器插件，任意网页右键加直连/代理规则 | 手动，随用随加 |

> 注意：不要用 `guyue2005/custom_openclash_rules` 那个 fork，它是 2025 年 11 月从 Aethersailor 原项目 fork 出来后就没再更新的；直接用 Aethersailor 的原项目。

本仓库为原创整合文档与配置片段，不复制上游仓库内容。本仓库新增内容采用 MIT 许可；各上游规则及工具保留其各自许可。

---

## 二、技术说明

### 2.1 整体架构

```
                ┌─ 国内域名 ─→ 运营商 DNS 直连（绕过内核，零影响）
用户流量 ─→ OpenClash (Mihomo 内核, Fake-IP 模式)
                └─ 国外流量 ─→ 规则引擎按顺序匹配 ─→ 策略组
                        │
                        ├─ ① AND(广告黑名单, NOT 白名单) → REJECT（只拦需要拦的）
                        ├─ ② ai-services → AI服务（精确 AI 域名走专用分组）
                        ├─ ③ 非广告白名单命中 → 继续匹配原有规则
                        └─ ④ 底座规则（GeoSite 分流、流媒体、游戏等）→ 各自的分流组
```

规则引擎**按顺序、首个命中即停止**。本方案两条规则应放在通用分流和 `MATCH` 之前，但不要覆盖原有 DNS/节点/策略组/其他规则。广告白名单只排除拦截，不再强制 `DIRECT`。

### 2.2 rule-provider 工作原理

`rule-providers` 是 Mihomo 的远程规则集机制：

```yaml
adguard_block:
  type: http            # 从 URL 下载
  behavior: classical   # 规则格式（见 2.3）
  format: yaml          # provider 文件格式
  path: ./ruleset/adguard_block.yaml   # 本地缓存路径（相对配置文件目录）
  url: https://raw.githubusercontent.com/...  # 上游地址
  interval: 43200       # 更新间隔（秒），43200 = 12 小时
```

以上是 `type: http` 规则集示例：Mihomo 会使用缓存并按 `interval` 检查更新；是否成功下载需以运行日志为准。默认 AI 规则改用 `type: inline`，不进行远程下载。

### 2.3 behavior 的三种格式（关键）

| behavior | payload 内容 | 说明 |
|---|---|---|
| `classical` | 完整规则行，如 `DOMAIN-SUFFIX,google.com` | 本方案的远程广告 provider 与内联 AI provider 均使用此格式 |
| `domain` | 纯域名，如 `google.com`（**不带**类型前缀） | 写错会导致整行被当成字面域名，永远匹配不上 |
| `ipcidr` | IP 段，如 `1.1.1.1/32` | 用于 IP 规则集 |

上游 `rorojiao/clash_rules` 的 `ai-services.yaml` 使用带 `DOMAIN-SUFFIX,` 等前缀的 classical 规则；如选择上游远程列表，应配置 `behavior: classical`，而不是 `domain`。默认内联列表也使用 `classical`。

### 2.4 为什么使用逻辑白名单例外

白名单并不等于直连。旧写法 `RULE-SET,adguard_allow,DIRECT` 会提前结束规则匹配，使一些本来应使用代理的网站被错误强制直连。新方案采用 Mihomo 的 `AND` + `NOT`：

```yaml
rules:
  - 'AND,((RULE-SET,oisd_small),(NOT,((RULE-SET,adguard_allow)))),REJECT'
  - RULE-SET,ai-services,AI服务
```

完整版将 `oisd_small` 换成 `adguard_block`。命中白名单的连接会继续按照原有的 AI、GeoSite 和其他底座规则决定直连或代理，不会被强制设为 `DIRECT`。详见 `docs/02-去广告.md`。

### 2.5 内存取舍

| 黑名单 | 条目数 | 文件大小 | 适用 |
|---|---|---|---|
| oisd_small（默认） | 约 5.6 万条 | 2.1MB | 小内存路由器（Redmi AX3000 256MB 等）无压力 |
| adguard_block（完整版） | 约 27.4 万条 | 10.7MB | 内存 ≥512MB 的设备，拦截更全 |

Mihomo 需要加载规则集；大规则集可能增加内存和启动耗时。条目数与文件体积随上游变化，先用轻量版测试，内存充足再考虑完整版。

### 2.6 链式代理（dialer-proxy，可选）

```
[你的设备] → OpenClash → [前置中转] → [AI 出口] → AI 服务
                              ↑              ↑
                    ISP 只看到到这里的连接   AI 服务看到的是这个 IP
```

把 `proxies` 里出口节点的 `dialer-proxy` 指向前置节点，即可让 AI 流量单独走一条干净的出口（例如美国原生 IP），而日常流量走香港/日本。配置示例见 `docs/03-AI专项.md`。

### 2.7 对底座的依赖

本方案假设底座已按 Aethersailor 的 Wiki 配好（Fake-IP 模式），并满足：

- 存在**名称完全匹配**的 `AI服务` 策略组；若不存在，应根据实际节点与策略组创建，不要照搬不存在的节点名；
- 不要再叠其他 DNS 插件（底座已处理 DNS 防污染防泄漏，"套娃"反而出问题）；
- 广告过滤**不要**按底座旧教程开（2025-07 已停用，会导致 dnsmasq 故障），去广告走本方案的 rule-provider。

---

## 三、使用说明

### 3.1 前置条件

- OpenWrt 路由器，已安装 OpenClash 插件；
- 有可用的代理订阅；
- 按 `docs/01-底座.md` 把底座配好（约 10 分钟，Wiki 图文教程）。

### 3.2 接入方式 A：手动合并（推荐新手）

1. 在 OpenClash 确认**实际使用的配置文件名**并备份，不要假设总叫 `config.yaml`。
2. 默认选 `config/rule-providers.yaml`；RAM 足够时可选 `config/rule-providers-full.yaml`，**二选一**。
3. 仅把 `rule-providers` 下三个 provider 合并进当前配置的同名顶层键，避免重复创建顶层键；核对同名 provider 的冲突。
4. 把 `rules` 下的**两条**规则依次放在原有通用规则和 `MATCH` 之前；保留你自己的其他规则、DNS、代理组和节点。
5. 确认已有完全同名的 `AI服务` 分组，不存在则按实际节点名创建；保存应用后检查连接记录和日志。详见 `docs/05-部署验证与回滚.md`。

### 3.3 接入方式 B：OpenClash 覆写模块（进阶）

1. `config/overwrite-example.yaml` 现在是以 `[YAML]` 开头的 **OpenClash 模块文件**，不是完整 Mihomo YAML，也不是 Shell 脚本。
2. 通过 OpenClash 覆写模块功能导入该文件或你托管的 URL；**不要**粘贴到 `/etc/openclash/custom/openclash_custom_overwrite.sh`。
3. 模块含 `+rule-providers` 与 `+rules`；核对中文策略组名的兼容性、模块先后顺序和最终运行配置。如果底座模块覆盖整个 `rules`，需要调整模块加载逻辑。
4. 手动合并与模块覆写**选其一**，避免重复规则。参考 `docs/05-部署验证与回滚.md`。

### 3.4 验证是否生效

1. **规则集已加载**：OpenClash → 规则集，检查两个远程广告 provider 能正常下载；内联 AI provider 不需要下载。
2. **去广告**：访问 [d3ward.github.io/toolz/adblock.html](https://d3ward.github.io/toolz/adblock.html) 看拦截率。
3. **AI 分流**：访问 `claude.ai` 等 AI 站点，去 OpenClash → 连接记录，确认走了 `AI服务` 分组。
4. **日志排错**：OpenClash → 运行日志，搜 `RULE-SET` 看规则是否被正确引用；provider 下载失败会显示 HTTP 错误码。

### 3.5 完整版 / 轻量版切换

- 默认 `rule-providers.yaml`（轻量，oisd small）→ 想拦截更全时，换成 `rule-providers-full.yaml` 的内容（adguard_block），**二选一，不要同时用**。
- 切换后在 OpenClash 里重新应用配置，规则集会自动重新下载。

### 3.6 日常维护

- 远程广告 provider 按配置间隔检查更新；默认 `ai-services` 是人工维护的内联列表，**不会**自动更新。
- 上游挂了或换地址时，跑 `scripts/check-upstream.sh` 检查连通性：
  ```bash
  bash scripts/check-upstream.sh
  ```
- 遇到分流不对的冷门站：用 openclash-helper 浏览器插件右键加规则（见 `docs/04-随手加规则.md`），或按底座文档用 TG 机器人提交域名。

### 3.7 常见问题

| 现象 | 排查 |
|---|---|
| OpenClash 启动报错找不到 `AI服务` | 核对实际策略组名；按真实可用节点创建同名分组 |
| 广告白名单没生效 | 检查 `AND,((RULE-SET,黑名单),(NOT,((RULE-SET,adguard_allow))))` 是否在通用规则之前 |
| AI 站点没走 AI 分组 | 确认 `RULE-SET,ai-services,AI服务` 在底座通用规则之前；去连接记录看实际命中 |
| 规则集下载失败 | 核对远程广告 provider 的 URL、日志和网络；可运行 `check-upstream.sh`，AI 内联列表不需要下载 |
| 内存占用高 / 启动慢 | 换回轻量版（oisd small）；检查是否误同时用了完整版和轻量版 |

---

## 四、文件说明

- `config/rule-providers.yaml`：轻量规则片段（远程 oisd small + 内联 AI）
- `config/rule-providers-full.yaml`：大规则集片段（远程 AdGuard block + 内联 AI）
- `config/overwrite-example.yaml`：OpenClash **模块文件**（含 `[YAML]`，默认轻量版）
- `docs/01-底座.md`：基础 OpenClash 底座设置
- `docs/02-去广告.md`：白名单排除拦截与内存取舍
- `docs/03-AI专项.md`：默认精确 AI 规则及可选上游列表
- `docs/04-随手加规则.md`：OpenClash Helper
- `docs/05-部署验证与回滚.md`：手动部署、校验、备份和回滚
- `scripts/validate-config.py`：离线结构一致性校验（Python + PyYAML）
- `scripts/check-upstream.sh`：远程广告规则下载及基础内容检查
- `.github/workflows/validate.yml`：CI 静态校验

离线检查：`python3 scripts/validate-config.py`。该检查不能代替真实 OpenClash/Mihomo 运行验证。
