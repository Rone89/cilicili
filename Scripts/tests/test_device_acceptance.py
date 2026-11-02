"""Prevent retained evidence, skipped tests, and unrelated crashes claiming acceptance."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('acceptance', Path(__file__).resolve().parents[1] / 'device-acceptance.py')
a = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(a)


class AcceptanceEvidenceTests(unittest.TestCase):
    def test_old_completed_report_never_measures_new_lifecycle_actions(self):
        report = {'runID': 'old-run', 'context': {'build': '51', 'testPlan': 'full'},
                  'status': 'completed', 'trials': [{'outcome': 'observed'}]}
        result = a.report_summary(report, '52')
        self.assertFalse(result['matchesInstalledBuild'])
        self.assertEqual(result['lifecycleAcceptance'], 'notMeasuredByThisReport')

    def test_skip_failure_or_wrong_test_count_cannot_pass(self):
        passing = {'totalTestCount': 3, 'passedTests': 3, 'failedTests': 0, 'skippedTests': 0}
        self.assertTrue(a.simulator_passed(passing))
        for changed in [{'skippedTests': 1}, {'failedTests': 1}, {'totalTestCount': 2}, {}]:
            self.assertFalse(a.simulator_passed(dict(passing, **changed) if changed else {}))

    def test_confirmation_is_neither_issue_nor_normal_until_clarified(self):
        result = a.manual_observation('确认')
        self.assertEqual(result['userObservation'], '确认')
        self.assertEqual(result['status'], 'needsClarification')
        normal = a.manual_observation('正常')
        self.assertEqual(a.acceptance_result([], [result, normal, normal]), 'manualPending')

    def test_explicit_manual_choices_and_missing_observations(self):
        for answer in ['1', '正常', '通过', 'OK']:
            self.assertEqual(a.manual_observation(answer)['status'], 'userReportedNormal')
        for answer in ['2', '异常']:
            self.assertEqual(a.manual_observation(answer)['status'], 'userReportedIssue')
        self.assertEqual(a.manual_observation('')['status'], 'pending')
        self.assertEqual(a.acceptance_result([], []), 'manualPending')
        self.assertEqual(a.acceptance_result([], [{'status': 'unrecognized'}] * 3), 'manualPending')

    def test_only_three_explicit_normals_without_errors_close_manual_acceptance(self):
        normal = a.manual_observation('1')
        self.assertEqual(a.acceptance_result([], [normal] * 3), 'userReportedNormal')
        self.assertEqual(a.acceptance_result(['capture failed'], [normal] * 3), 'requiresReview')
        self.assertEqual(a.acceptance_result([], [normal, normal, a.manual_observation('2')]), 'requiresReview')

    def test_crash_filter_excludes_other_apps_and_path_traversal(self):
        names = ['bili-2026-11-02-123000.ips', 'bili-overseas.diskwrites.ips', '../bili-2026.ips']
        payload = {'result': {'files': [{'name': n, 'relativePath': n} for n in names]}}
        self.assertEqual(a.crash_names(payload), {'bili-2026-11-02-123000.ips'})


if __name__ == '__main__':
    unittest.main()
