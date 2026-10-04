"""Regression checks for invalid design graphs that could strand a campaign."""
import copy
import json
import unittest

from ascension_catalog import SOURCE, render, validate


class CatalogueContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = json.loads(SOURCE.read_text())

    def setUp(self):
        self.data = copy.deepcopy(self.source)

    def test_complete_catalogue_validates(self):
        self.assertEqual(validate(self.data), [])

    def test_cycle_cannot_hide_behind_valid_ids(self):
        self.data['technologies'][0]['prerequisites'] = ['T008']
        self.assertTrue(any('Cycle detected' in e for e in validate(self.data)))

    def test_missing_dependency_is_reported(self):
        self.data['technologies'][0]['prerequisites'] = ['T999']
        self.assertTrue(any('missing prerequisite T999' in e for e in validate(self.data)))

    def test_facility_cannot_require_its_own_discovery(self):
        self.data['technologies'][1]['infrastructure_requirement'] = ['facility:T002']
        self.assertTrue(any('not unlocked by an ancestor' in e for e in validate(self.data)))

    def test_ship_is_not_a_laboratory_provider(self):
        self.data['technologies'][183]['infrastructure_requirement'] = ['facility:T085']
        self.assertTrue(any('missing facility provider' in e for e in validate(self.data)))

    def test_causal_ending_cannot_depend_on_fictional_physics(self):
        self.data['technologies'][199]['prerequisites'].append('T199')
        self.assertTrue(any('causal route requires speculative-only' in e for e in validate(self.data)))

    def test_negative_resource_cost_is_rejected(self):
        self.data['technologies'][0]['economic_cost']['materials']['refined_material'] = -1
        self.assertTrue(any('must be a positive integer' in e for e in validate(self.data)))

    def test_unknown_physics_needs_disclosure(self):
        self.data['technologies'][150]['science']['required_assumptions'] = ''
        self.assertTrue(any('missing science disclosure' in e for e in validate(self.data)))

    def test_reverse_dependency_drift_is_rejected(self):
        self.data['technologies'][0]['technologies_enabled'] = []
        self.assertTrue(any('reverse dependencies' in e for e in validate(self.data)))

    def test_renderer_is_stable_and_contains_every_record(self):
        first = render(self.data)
        self.assertEqual(first, render(copy.deepcopy(self.data)))
        self.assertEqual(first.count('\n### T'), 200)
        for node in self.data['technologies']:
            self.assertIn(node['name'], first)
            self.assertIn(node['gameplay_effect'], first)


if __name__ == '__main__':
    unittest.main()
