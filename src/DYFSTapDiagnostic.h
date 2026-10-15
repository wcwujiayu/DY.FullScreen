//
//  DYFSTapDiagnostic.h
//  DY.FullScreen
//
//  轻量点击诊断（0.5.16 新增）。仅用于定位「我-喜欢 / 收藏 / 我-作品」宫格页
//  「点 N 打开 N+1」的错位根因：
//    · 点宫格 cell 时记录 indexPath 与屏幕坐标
//    · 详情页打开时记录实际加载的 awemeId
//  二者对不上即可区分「命中错位」还是「详情加载错位」。
//  默认关闭，仅在「DY.FullScreen → 诊断 → 开启点击诊断」后生效，
//  不影响正常使用的布局与透明逻辑（不在任何高频路径）。
//

#import <Foundation/Foundation.h>

void DYFSTapDiagnosticInstallHooks(void);
void DYFSTapDiagnosticSetEnabled(BOOL enabled);
BOOL DYFSTapDiagnosticEnabled(void);
