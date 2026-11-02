#!/usr/bin/env python3
"""Run existing simulator checks and collect guided iPhone acceptance evidence."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SIMULATOR = 'F0B4287D-8633-4CC1-B7C2-0A37F353FE7C'
CASES = [
    'testVideoDetailPlayerFullscreenRoundTripKeepsDetailShellMounted',
    'testVideoDetailBackgroundRecoveryKeepsPlayerSurfaceMounted',
    'testVideoDetailExitDuringRotationReturnsToHomeWithoutRebuildingPlayer',
]


def report_summary(report, installed_build):
    # A retained recovery report is never evidence of these manual lifecycle actions.
    return {'runID': report['runID'], 'build': report['context']['build'],
            'matchesInstalledBuild': report['context']['build'] == installed_build,
            'testPlan': report['context'].get('testPlan'), 'status': report['status'],
            'outcomes': [t['outcome'] for t in report['trials']],
            'lifecycleAcceptance': 'notMeasuredByThisReport'}


def simulator_passed(summary):
    return (summary.get('totalTestCount') == 3 and summary.get('passedTests') == 3
            and summary.get('failedTests') == 0 and summary.get('skippedTests') == 0)


def manual_observation(answer):
    value = answer.strip()
    if value.lower() in ('1', '正常', '通过', 'ok'):
        status = 'userReportedNormal'
    elif value in ('2', '异常'):
        status = 'userReportedIssue'
    else:
        status = 'needsClarification' if value else 'pending'
    return {'userObservation': value, 'status': status}


def acceptance_result(errors, observations):
    statuses = [v.get('status') if isinstance(v, dict) else v for v in observations]
    if errors or 'userReportedIssue' in statuses:
        return 'requiresReview'
    if len(statuses) == 3 and all(v == 'userReportedNormal' for v in statuses):
        return 'userReportedNormal'
    return 'manualPending'


def crash_names(payload):
    return {f['relativePath'] for f in payload['result']['files']
            if re.fullmatch(r'bili-\d{4}[^/]*\.ips', f['name'])
            and '/' not in f['relativePath'] and '\\' not in f['relativePath']}


def main():
    parser = argparse.ArgumentParser(description='cilicili 一键回归与真机引导取证')
    parser.add_argument('--device', default=os.environ.get('CILICILI_DEVICE_ID'),
                        help='iPhone UDID；也可设置 CILICILI_DEVICE_ID')
    parser.add_argument('--bundle-id', default='app.bamboo2779.brussels691')
    parser.add_argument('--non-interactive', action='store_true', help='自动回归与采集，人工项标待验证')
    parser.add_argument('--collect-only', action='store_true', help='只取证，不运行模拟器或人工引导')
    parser.add_argument('--no-open', action='store_true', help='完成后不打开 Finder')
    args = parser.parse_args()
    if not args.device:
        parser.error('请用 --device 指定 iPhone，或双击已配置的桌面入口。')
    output = ROOT / 'build' / 'device-acceptance'
    output.mkdir(parents=True, exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-'), dir=str(output)))
    summary = {'device': args.device, 'bundleID': args.bundle_id, 'errors': [],
               'simulator': 'notRun', 'manual': {}, 'report': None,
               'startedAt': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    print('结果目录：' + str(folder), flush=True)

    def run(name, command, timeout=40):
        with (folder / (name + '.log')).open('w') as log:
            try:
                result = subprocess.run(command, cwd=str(ROOT), stdout=log,
                                        stderr=subprocess.STDOUT, timeout=timeout)
            except (OSError, subprocess.TimeoutExpired) as exc:
                raise RuntimeError(name + '：' + str(exc)) from exc
        if result.returncode:
            raise RuntimeError(name + ' 失败，详见 ' + name + '.log')

    def device(name, command):
        path = folder / (name + '.json')
        run(name, ['xcrun', 'devicectl'] + command + ['--device', args.device,
            '--timeout', '20', '--json-output', str(path)])
        return json.loads(path.read_text())

    def pull_report(name):
        path = folder / (name + '.json')
        run(name, ['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', args.device,
                  '--domain-type', 'appDataContainer', '--domain-identifier', args.bundle_id,
                  '--source', 'Library/Application Support/PlaybackRecoveryTests/latest.json',
                  '--destination', str(path), '--timeout', '20'])
        value = json.loads(path.read_text())
        return value, hashlib.sha256(path.read_bytes()).hexdigest()

    try:
        apps = device('installed-app', ['device', 'info', 'apps', '--bundle-id', args.bundle_id])
        installed = next(a for a in apps['result']['apps'] if a['bundleIdentifier'] == args.bundle_id)
        summary['installedBuild'] = installed['bundleVersion']
        print('已核对手机 Build ' + summary['installedBuild'], flush=True)
        before = device('crashes-before', ['device', 'info', 'files', '--domain-type',
                        'systemCrashLogs', '--no-recurse', '--search', 'bili'])
        before_hash = None
        try:
            _, before_hash = pull_report('recovery-before')
        except (RuntimeError, ValueError, KeyError) as exc:
            summary['reportBeforeWarning'] = str(exc)

        if not args.collect_only:
            print('运行三项模拟器回归，约两分钟；详细进度写入 simulator.log。', flush=True)
            common = Path(subprocess.check_output(['git', 'rev-parse', '--git-common-dir'], cwd=str(ROOT), text=True).strip())
            if not common.is_absolute():
                common = (ROOT / common).resolve()
            command = ['python3', str(common.parent / 'Scripts/build-cache.py'), 'run', '--',
                       'xcodebuild', '-project', str(ROOT / 'bili.xcodeproj'), '-scheme', 'bili',
                       '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + SIMULATOR,
                       '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
                       '-skipPackagePluginValidation', '-resultBundlePath', str(folder / 'simulator.xcresult')]
            command += ['-only-testing:biliUITests/VideoDetailFlowUITests/' + case for case in CASES]
            command += ['CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'test']
            try:
                run('simulator', command, timeout=1200)
                run('simulator-summary', ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                    '--path', str(folder / 'simulator.xcresult'), '--format', 'json'])
                result = json.loads((folder / 'simulator-summary.log').read_text())
                if not simulator_passed(result):
                    raise RuntimeError('模拟器未取得 3/3、零跳过的结果')
                summary['simulator'] = 'passed3of3'
                print('模拟器 3/3 通过；真机音画仍需观察。', flush=True)
            except (RuntimeError, ValueError) as exc:
                summary['simulator'] = 'failed'
                summary['errors'].append(str(exc))

        tasks = [('rotation', '播放约十秒，横屏再回竖屏三次；暂停后再切换一次。'),
                 ('navigation', '返回列表，再打开同一视频，确认可播放／暂停，无双重声音。'),
                 ('background', '播放中退后台十秒再回来；主动暂停后重复。按原后台播放设置观察。')]
        for key, instruction in tasks:
            summary['manual'][key] = 'pending'
            if not args.non_interactive and not args.collect_only:
                print('\n' + instruction + '\n观察黑屏、有声无画、意外播放或闪退。')
                answer = input('完成后输入 1（正常）、2（异常），或回车（未确认）：').strip()
                observation = manual_observation(answer)
                summary['manual'][key] = observation
                if observation['status'] == 'needsClarification':
                    choice = input('刚才的输入需要确认：1 表示正常，2 表示异常，回车保留待确认：').strip()
                    observation['clarification'] = choice
                    observation['status'] = manual_observation(choice)['status']
                if observation['status'] == 'userReportedIssue':
                    observation['details'] = input('请补充异常动作、大概时刻和表现：').strip()

        if not args.non_interactive and not args.collect_only:
            print('\n在手机“我的 → 开发者与诊断 → 播放与网络诊断 → 启动链路性能日志”点复制；输入 c 读取这份日志，回车跳过。')
            if input('选择：').strip().lower() == 'c':
                try:
                    run('performance-copy', ['xcrun', 'devicectl', 'device', 'pasteboard',
                        'paste', '--device', args.device, '--quiet', '--timeout', '20'])
                    copied = folder / 'performance-copy.log'
                    text = copied.read_text()
                    if 'CiliCili 播放性能日志' not in text[:500]:
                        copied.unlink()
                        raise RuntimeError('剪贴板不是性能日志，未保留其内容')
                    copied.rename(folder / 'performance.txt')
                    summary['performanceLog'] = 'collectedByUserRequest'
                except (RuntimeError, ValueError) as exc:
                    (folder / 'performance-copy.log').unlink(missing_ok=True)
                    summary['errors'].append(str(exc))
        try:
            report, after_hash = pull_report('recovery-after')
            summary['report'] = report_summary(report, summary['installedBuild'])
            summary['report']['changedDuringSession'] = before_hash is not None and before_hash != after_hash
            summary['report']['sha256'] = after_hash
        except (RuntimeError, ValueError, KeyError) as exc:
            summary['errors'].append(str(exc))
        after = device('crashes-after', ['device', 'info', 'files', '--domain-type',
                       'systemCrashLogs', '--no-recurse', '--search', 'bili'])
        fresh = sorted(crash_names(after) - crash_names(before))
        summary['newBiliCrashFiles'] = fresh
        for index, name in enumerate(fresh):
            run('copy-crash-' + str(index), ['xcrun', 'devicectl', 'device', 'copy', 'from',
                '--device', args.device, '--domain-type', 'systemCrashLogs', '--source', name,
                '--destination', str(folder / name), '--timeout', '20'])
            header = json.loads((folder / name).read_text().splitlines()[0])
            identity = {k: header.get(k) for k in ['bundleID', 'build_version', 'timestamp']}
            identity['matchesInstalledApp'] = (header.get('bundleID') == args.bundle_id
                and header.get('build_version') == summary['installedBuild'])
            summary.setdefault('crashIdentity', []).append(identity)
        print('已归档恢复报告和新增同名崩溃记录；旧恢复报告不代表本轮人工操作通过。')
    except (RuntimeError, ValueError, KeyError, StopIteration, subprocess.SubprocessError) as exc:
        summary['errors'].append(str(exc) or '设备未找到目标应用')
    except (KeyboardInterrupt, EOFError):
        summary['errors'].append('用户中止，保留已采集部分结果')
    finally:
        summary['result'] = acceptance_result(summary['errors'], list(summary['manual'].values()))
        summary['endedAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (folder / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
        print('\n结果：' + str(folder / 'summary.json'))
        if summary['errors']:
            print('未全部完成：' + '；'.join(summary['errors']))
        print('人工观察以记录为准；无新增崩溃文件不等于从未闪退。')
        if not args.no_open:
            subprocess.run(['open', str(folder)], check=False)
    return 1 if summary['result'] == 'requiresReview' else 0


if __name__ == '__main__':
    sys.exit(main())
