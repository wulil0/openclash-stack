# OpenClash 规则整合方案（OpenClash Rules Stack）

把 4 个互补的 OpenClash 规则项目整合成一套开箱即用的方案：底座一次配好，去广告、AI 专项分流、随手加规则各就其位，互不打架。

## 四层架构

| 层 | 项目 | 角色 | 更新方式 |
|---|---|---|---|
| 底座 | [Aethersailor/Custom_OpenClash_Rules](https://github.com/Aethersailor/Custom_OpenClash_Rules) | 保姆级设置方案＋订阅转换模板：Fake-IP、DNS 防污染防泄漏、国内外分流、策略组 | 按 Wiki 配一次；GeoIP/GeoSite 每日自动更新 |
| 去广告 | [AyraHikari/openclash_adguard](https://github.com/AyraHikari/openclash_adguard) | AdGuard / EasyList 转成的 Clash 去广告规则 | GitHub Actions 每 12 小时自动更新 |
| AI 专项 | [rorojiao/clash_rules](https://github.com/rorojiao/clash_rules) | 50+ 家 AI 服务域名规则＋链式代理（dialer-proxy）模板 | 每天自动更新 |
| 随手加规则 | [Zeral-Zhang/openclash-helper](https://github.com/Zeral-Zhang/openclash-helper) | 浏览器插件：任意网页右键加直连/代理规则 | 手动，随用随加 |

> 注意：不要用 `guyue2005/custom_openclash_rules` 那个 fork，它是 2025 年 11 月从原项目 fork 出来后就没再更新的；直接用 Aethersailor 的原项目。

## 为什么这样分层

- **底座管框架**：DNS、Fake-IP、分流策略组、订阅转换，一次配好长期不管。上游规则（GeoSite、dnsmasq-china-list 等）由底座每日自动拉新。
- **去广告独立成 rule-provider**：底座自带的广告过滤已于 2025-07 停用（会导致 dnsmasq 故障），用 AyraHikari 的方案补上，allow/block 分两个 provider，按顺序引用即可。
- **AI 流量单独分组**：AI 站点域名变得快，rorojiao 的规则每天更新；想让 AI 走单独出口（比如美国原生 IP）时，它的 dialer-proxy 链式代理模板直接可用。
- **长尾靠手工**：再全的规则也覆盖不了冷门站，helper 插件右键一点就加规则，不用进路由器翻配置。

## 快速开始

1. 按 [docs/01-底座.md](docs/01-底座.md)，照 Aethersailor 的 Wiki 把 OpenClash 底座配好（Fake-IP 模式）。
2. 把 [config/rule-providers.yaml](config/rule-providers.yaml) 里的 `rule-providers` 段粘进 OpenClash 配置（或加到覆写文件），再把 `rules` 段的三条按顺序加进规则列表。
3. 可选：按 [docs/03-AI专项.md](docs/03-AI专项.md) 配链式代理，让 AI 流量走指定出口。
4. 日常：在浏览器装 openclash-helper 插件，遇到分流不对的站右键加规则（见 [docs/04-随手加规则.md](docs/04-随手加规则.md)）。

## 文件说明

```
openclash-stack/
├── README.md                  # 本文件：架构与快速开始
├── config/
│   ├── rule-providers.yaml    # 默认（轻量）：去广告黑名单用 oisd small（2.1MB），适合小内存路由器
│   ├── rule-providers-full.yaml # 完整版：去广告黑名单用 adguard_block（10.7MB/27万条），内存充足时用
│   └── overwrite-example.yaml # 覆写示例：在 Aethersailor 覆写基础上叠加本方案
├── docs/
│   ├── 01-底座.md             # 底座设置要点
│   ├── 02-去广告.md           # 去广告接入说明
│   ├── 03-AI专项.md           # AI 规则与链式代理
│   └── 04-随手加规则.md       # helper 插件使用
└── scripts/
    └── check-upstream.sh      # 检查上游规则源是否可达
```

## 上游项目与许可

本项目为原创整合文档与配置片段，不复制上游仓库内容。各上游项目许可如下，使用时请遵守：

- Aethersailor/Custom_OpenClash_Rules：CC-BY-SA-4.0
- AyraHikari/openclash_adguard：见上游仓库
- rorojiao/clash_rules：见上游仓库
- Zeral-Zhang/openclash-helper：见上游仓库

本仓库新增内容采用 MIT 许可。
