#!/bin/bash
# 检查本方案引用的上游规则源是否可达（HTTP 200 即为正常）
set -u
URLS=(
  "https://raw.githubusercontent.com/AyraHikari/openclash_adguard/main/rules/adguard_allow.yaml"
  "https://raw.githubusercontent.com/AyraHikari/openclash_adguard/main/rules/adguard_block.yaml"
  "https://raw.githubusercontent.com/rorojiao/clash_rules/master/rules/ai-services.yaml"
  "https://raw.githubusercontent.com/hillz2/openclash_adblock/main/oisd_small.yaml"
  "https://github.com/Aethersailor/Custom_OpenClash_Rules"
)
fail=0
for u in "${URLS[@]}"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$u")
  if [ "$code" = "200" ]; then
    echo "OK   $u"
  else
    echo "FAIL($code) $u"
    fail=1
  fi
done
exit $fail
