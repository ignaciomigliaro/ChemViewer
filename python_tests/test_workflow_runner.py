import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('workflow_bridge', ROOT / 'Sources/ChemCraftMacApp/Resources/workflow_bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ChemViewer-workflow-test-')
        self.root = Path(self.temp.name)
        (self.root / 'templates').mkdir()
        (self.root / 'seed.xyz').write_text('2\nindependent H2 fixture\nH 0 0 0\nH 0 0 0.74\n')
        self.path = self.root / 'input.yaml'

    def tearDown(self):
        self.temp.cleanup()

    def config(self, engine='pyscf', options='options: {method: hf, basis: sto-3g, cores: 1}'):
        self.path.write_text('input: seed.xyz\ntemplate_dir: templates\noutput_dir: outputs\nscratch_dir: scratch\ndispatch: local\nmax_cores: 1\nsteps:\n  - step: 1\n    engine: ' + engine + '\n    ' + options + '\n')
        return self.path

    def test_missing_config_rejected(self):
        report = bridge.inspect_workflow(self.path)
        self.assertFalse(report['ok'])
        self.assertIn('input.yaml', report['checks'][0]['name'])

    def test_missing_seed_and_template_block_before_launch(self):
        self.config()
        (self.root / 'seed.xyz').unlink()
        with patch('chemrefine.agent_tools.start_run') as launch:
            result = bridge.act(dict(action='run', config_path=str(self.path)))
        self.assertFalse(result['started'])
        launch.assert_not_called()
        errors = '\n'.join(c['detail'] for c in result['report']['checks'] if c['status'] == 'error')
        self.assertIn('seed.xyz', errors)
        self.assertIn('template', errors.lower())

    def test_scaffold_creates_only_missing_files(self):
        self.config()
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        file = self.root / 'templates/step1.py'
        self.assertTrue(file.exists())
        file.write_text('# existing user template; preserve this\n')
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        self.assertEqual(file.read_text(), '# existing user template; preserve this\n')

    def test_missing_backend_reports_targeted_install(self):
        self.config()
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        with patch('chemrefine.engines.preflight_backends', side_effect=RuntimeError('backend not installed')):
            report = bridge.inspect_workflow(self.path)
        self.assertFalse(report['ok'])
        self.assertEqual(report['missingBackends'], ['pyscf'])
        self.assertEqual(report['requiredBackends'], ['pyscf'])

    def test_install_uses_only_declared_missing_backend(self):
        self.config()
        report = dict(ok=False, missingBackends=['pyscf'], requiredBackends=['pyscf'], checks=[])
        with patch.object(bridge, 'inspect_workflow', return_value=report), patch.object(bridge, 'child_run') as run:
            bridge.act(dict(action='install', config_path=str(self.path)))
        arguments = run.call_args.args[0]
        self.assertEqual(arguments[-4:], ['chemrefine', 'backends', 'install', 'pyscf'])

    def test_missing_orca_is_blocking(self):
        self.config('orca', 'template: step1.inp')
        (self.root / 'templates/step1.inp').write_text('! HF STO-3G\n')
        with patch.dict(os.environ, {'PATH': str(self.root)}):
            report = bridge.inspect_workflow(self.path)
        self.assertFalse(report['ok'])
        self.assertTrue(any(c['name'] == 'orca' and c['status'] == 'error' for c in report['checks']))

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS ORCA package check')
    def test_partial_orca_package_rejected(self):
        self.config('orca', 'template: step1.inp')
        (self.root / 'templates/step1.inp').write_text('! HF STO-3G\n')
        binary = self.root / 'orca'
        binary.write_text('#!/bin/sh\nexit 0\n'); binary.chmod(0o755)
        with patch.dict(os.environ, {'PATH': str(self.root)}):
            report = bridge.inspect_workflow(self.path)
        self.assertTrue(any(c['name'] == 'ORCA installation' and c['status'] == 'error' for c in report['checks']))

    def test_mlip_missing_weights_prevents_pipeline_launch(self):
        self.config('mlip', 'options: {task_name: omol, model_path: absent.pt}')
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        with patch('chemrefine.engines.preflight_backends'), patch.object(bridge, 'child_run', side_effect=RuntimeError('weights require access')), patch('chemrefine.agent_tools.start_run') as launch:
            result = bridge.act(dict(action='run', config_path=str(self.path)))
        self.assertFalse(result['started']); launch.assert_not_called()
        self.assertTrue(any(c['status'] == 'error' and ('checkpoint' in c['name'] or 'model' in c['name']) for c in result['report']['checks']))

    def test_partial_backend_import_failure_can_be_repaired(self):
        self.config('mlip', 'options: {task_name: omol}')
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        with patch('chemrefine.engines.preflight_backends'), patch.object(bridge, 'child_run', side_effect=RuntimeError('ModuleNotFoundError: missing dependency')):
            report = bridge.inspect_workflow(self.path, prepare_models=True)
        self.assertFalse(report['ok'])
        self.assertEqual(report['missingBackends'], ['mlip-fairchem'])

    def test_zero_gpu_budget_blocks_gpu_step(self):
        self.config('mlip', 'options: {task_name: omol, device: cuda}')
        self.path.write_text(self.path.read_text().replace('max_cores: 1', 'max_cores: 1\nmax_gpus: 0'))
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        with patch('chemrefine.engines.preflight_backends'), patch.object(bridge.sys, 'platform', 'linux'):
            report = bridge.inspect_workflow(self.path)
        self.assertFalse(report['ok'])
        self.assertTrue(any(c['status'] == 'error' and 'budget' in c['detail'].lower() for c in report['checks']))

    def test_status_is_real_chemrefine_status(self):
        self.config()
        result = bridge.act(dict(action='status', config_path=str(self.path)))
        self.assertFalse(result['running'])
        self.assertEqual(result['steps'][0]['engine'], 'pyscf')
        self.assertFalse(result['steps'][0]['cached'])


if __name__ == '__main__':
    unittest.main()
