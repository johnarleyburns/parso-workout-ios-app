#!/usr/bin/env python3
"""Assert real SwiftPM target closure and Xcode links, without Apple SDKs."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'CadenceCore/Sources'


def manifest():
    return json.loads(subprocess.check_output(
        ['swift', 'package', '--package-path', str(ROOT / 'CadenceCore'), 'dump-package'], text=True))


class ModuleBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.targets = {target['name']: target for target in manifest()['targets']}

    def closure(self, name):
        seen = set()
        def visit(item):
            if item in seen:
                return
            seen.add(item)
            for dependency in self.targets.get(item, {}).get('dependencies', []):
                value = dependency.get('byName') or dependency.get('target') or dependency.get('product')
                visit(value[0])
        visit(name)
        return seen

    def test_fit_is_phone_only_and_bridge_has_one_definition(self):
        self.assertIn('CadencePortability', self.targets)
        self.assertIn('FreeExerciseDBPlusPlusFIT', self.closure('CadencePortability'))
        self.assertNotIn('FreeExerciseDBPlusPlusFIT', self.closure('CadenceCore'))
        bridges = list(SOURCES.glob('*/GarminFITBridge.swift'))
        self.assertEqual(bridges, [SOURCES / 'CadencePortability/GarminFITBridge.swift'])
        project = (ROOT / 'Cadence/Cadence.xcodeproj/project.pbxproj').read_text()
        for block in re.findall(r'isa = PBXNativeTarget;.*?\n\t\t};', project, re.S):
            if re.search(r'\n\s*name = Cadence;', block):
                self.assertIn('/* CadencePortability */', block)
            else:
                self.assertNotIn('/* CadencePortability */', block)

    def test_widgets_only_reach_light_contracts(self):
        self.assertEqual(self.closure('CadenceFeatures'), {'CadenceFeatures'})
        self.assertTrue((SOURCES / 'CadenceFeatures/WorkoutLiveActivityAttributes.swift').exists())
        self.assertTrue((SOURCES / 'CadenceWorkoutFeatures/WatchStrengthFlowModel.swift').exists())
        for path in (SOURCES / 'CadenceFeatures').glob('*.swift'):
            self.assertNotIn('import SwiftData', path.read_text())
            self.assertNotIn('import CadenceCore', path.read_text())


if __name__ == '__main__':
    unittest.main()
