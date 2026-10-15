#!/usr/bin/env bash
# DY.FullScreen 静态检查
#
# 在 CI 中于构建之前运行（ubuntu runner，不需要 Theos / Xcode）。
# 检查项均为"防止回归"性质：版本来源唯一、模块不重新膨胀、
# 已移除的功能不复活、文案一致、模块划分完整。
#
# 用法：bash .github/scripts/static-checks.sh

set -uo pipefail

fail=0
ok()   { printf '  OK    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }

echo "== 1. 版本号唯一来源 =="
version="$(awk '/^Version:/ {print $2; exit}' control)"
if [ -z "$version" ]; then
  bad "无法从 control 读取 Version"
else
  ok "control 版本: $version"
fi
if [ -f .github/workflows/build.yml ] && grep -qE '_[0-9]+\.[0-9]+\.[0-9]+_' .github/workflows/build.yml; then
  bad "build.yml 出现硬编码版本号，应从 control 动态读取"
else
  ok "build.yml 未硬编码版本号"
fi

echo "== 2. 模块体量（防回归到单文件巨石）=="
# 上限 800：这个项目早期是 1747 行的单文件，护栏的目的是别退回去。
# 之前定 500 太紧，导致每次接近上限就得删注释 / 压日志来凑行数，
# 反而损害可读性 —— 本末倒置。800 既能挡住巨石，又留足表达空间。
limit=800
for f in src/*.m; do
  n=$(wc -l < "$f" | tr -d ' ')
  if [ "$n" -gt "$limit" ]; then
    bad "$f 共 $n 行，超过上限 $limit"
  else
    ok "$(basename "$f") $n 行"
  fi
done
total=$(cat src/*.m | wc -l | tr -d ' ')
ok "源码总行数: $total"

echo "== 3. 已移除功能不得复活 =="
# 评论区 / 视频详情底部透明化（DYFSApplyVideoDetailBottomTransparencyInView 及
# DYFSComment*Layout）是 0.3.15 的功能，0.4.x 实测无效后删除；本次按用户要求移除，
# 避免把视频文案、评论输入栏误透明导致看不见。加入下面数组防止将来复活。
removed=(
  "DYFSApplyRecommendationTransparencyInView"   # 0.3.15 版去灰底，已由 0.4.x 取代
  "DYFSNativeSettingsCellForRow"
  "DYFSFindLabelWithText"
  "DYFSClearSmallCardChrome"                    # 0.3.15 去灰底配套，已无调用者
  "DYFSApplyVideoDetailBottomTransparencyInView"
  "DYFSCommentPanelLayout"
  "DYFSCommentInputContainerLayout"
  "DYFSCommentInputBackgroundLayout"
  "DYFSCommentInputControllerLayout"
)
for sym in "${removed[@]}"; do
  if grep -rq "$sym" src/; then
    bad "已移除的标识符重新出现: $sym"
  fi
done
[ $fail -eq 0 ] && ok "已移除的 ${#removed[@]} 个标识符均未复活"

echo "== 4. 文案一致性 =="
if grep -rq "胖胖专属" src/ README.md; then
  bad "残留占位文案『胖胖专属』"
else
  ok "无残留占位文案"
fi
if grep -q "视频全屏启动" src/DYFSCommon.m; then
  ok "设置项标题: 视频全屏启动"
else
  bad "未找到设置项标题常量"
fi

echo "== 5. 模块划分完整性 =="
for mod in DYFSCommon DYFSContext DYFSLayout DYFSChrome DYFSTransparency DYFSCardTransparency DYFSBottomChrome DYFSSettings; do
  if [ -f "src/$mod.h" ] && [ -f "src/$mod.m" ]; then
    ok "$mod.h / $mod.m 成对存在"
  else
    bad "$mod 缺少 .h 或 .m"
  fi
done
if grep -q "DYFSLayoutInstallHooks\|DYFSChromeInstallHooks\|DYFSSettingsInstallHooks" src/Tweak.m; then
  ok "入口仅调度各模块的安装函数"
else
  bad "Tweak.m 未通过模块安装函数调度"
fi
if grep -qE '^\s*Class cls = NSClassFromString' src/Tweak.m; then
  bad "Tweak.m 仍在直接安装 hook，应下沉到各模块"
else
  ok "Tweak.m 不含直接 hook 安装代码"
fi

echo "== 6. 编译所需文件均被 Makefile 收录 =="
for f in src/*.m; do
  if grep -q "$(basename "$f")" Makefile; then
    ok "$(basename "$f") 已在 Makefile 中"
  else
    bad "$(basename "$f") 未加入 Makefile FILES"
  fi
done

echo
if [ $fail -eq 0 ]; then
  echo "静态检查全部通过"
else
  echo "静态检查未通过"
fi
exit $fail
