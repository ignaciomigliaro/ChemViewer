import importlib.util
import json
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

    def test_mechanism_yaml_uses_relocatable_xyz_variants(self):
        import yaml
        from chemrefine.config import load_config
        from chemrefine.mechanism_batch import expand

        alternatives = self.root / 'substrates'
        alternatives.mkdir()
        (alternatives / 'A.xyz').write_bytes((self.root / 'seed.xyz').read_bytes())
        (alternatives / 'B.xyz').write_bytes((self.root / 'seed.xyz').read_bytes())
        step = {'step': 1, 'engine': 'orca', 'template': 'ts.inp'}
        stage = {
            'name': 'stage_1',
            'reactant': {'sources': [{'input_dir': 'substrates'}]},
            'product': {'input': 'seed.xyz'},
            'ts_guesser': {'method': 'idpp', 'scoring_steps': [{**step, 'operation': 'sp', 'on_failure': 'stop'}]},
            'ts_steps': [step],
        }
        self.path.write_text(json.dumps({'mechanism': {'max_variants': 2, 'stages': [stage]}}))
        self.assertTrue(bridge.act({'action': 'write-mechanism-yaml', 'config_path': str(self.path)})['ok'])
        text = self.path.read_text()
        self.assertTrue(text.startswith('mechanism:\n'))
        self.assertEqual(yaml.safe_load(text)['mechanism']['stages'][0], stage)
        self.assertEqual([variant.name for variant in expand(load_config(self.path))], ['A', 'B'])
        (self.root / 'templates/ts.inp').write_text('! HF STO-3G\n')
        (self.root / 'templates/cpu.slurm.header').write_text('#!/bin/bash\n')
        with patch.dict(os.environ, {'PATH': str(self.root)}):
            report = bridge.inspect_workflow(self.path)
        self.assertTrue(any(row['name'] == 'Workflow YAML' for row in report['checks']), report)
        self.assertTrue(any(row['name'] == 'orca' and row['status'] == 'error' for row in report['checks']))
        self.assertFalse(any(row['name'] == 'Input structures' for row in report['checks']))
        (alternatives / 'C.xyz').write_bytes((self.root / 'seed.xyz').read_bytes())
        self.path.write_text(json.dumps({'mechanism': {'max_variants': 2, 'stages': [stage]}}))
        with self.assertRaisesRegex(Exception, 'produces 3 variants'):
            bridge.act({'action': 'write-mechanism-yaml', 'config_path': str(self.path)})

    def test_mechanism_schema_and_contextual_yaml(self):
        from chemrefine.config import load_config

        schema = bridge.act({'action': 'mechanism-schema', 'config_path': str(self.path)})
        self.assertIn('operation', schema['config']['$defs']['StepConfig']['properties'])
        self.assertIn('freq', schema['engines']['orca']['operations'])
        self.assertIn('basis', schema['engines']['pyscf']['options_schema']['properties'])
        self.assertNotIn('$OUTPUT_CONTRACT', schema['engines']['pyscf']['starter'])

        step = {'step': 1, 'engine': 'pyscf', 'options': {'method': 'hf'}, 'template': 'seed.py'}
        stages = [{
            'name': 'example',
            'reactant': {'sources': [{'input': 'seed.xyz'}], 'steps': [step]},
            'product': {'input': 'seed.xyz'},
            'ts_guesser': {'method': 'idpp', 'scoring_steps': [{**step, 'operation': 'sp'}]},
            'ts_steps': [step],
        }]
        config = {'mechanism': {'stages': stages}}
        first = ['mechanism', 'stages', '0', 'reactant', 'steps', '0']
        request = {'config': config, 'config_path': str(self.path), 'overrides': [
            {'path': [], 'yaml': 'template_dir: templates/inside'},
            {'path': first, 'yaml': 'options:\n  basis: sto-3g'},
            {'path': ['mechanism'], 'yaml': 'seed: 73'},
        ]}
        preview = bridge.act({**request, 'action': 'preview-mechanism-yaml'})['yaml']
        self.assertIn('basis: sto-3g', preview)
        self.assertFalse(self.path.exists())
        (self.root / 'templates/seed.py').write_text('# fixture template\n')
        self.path.write_text(json.dumps(config))
        bridge.act({**request, 'action': 'write-mechanism-yaml'})
        exported = load_config(self.path)
        self.assertEqual(exported.mechanism.seed, 73)
        self.assertEqual(exported.mechanism.stages[0].reactant.steps[0].options, {'method': 'hf', 'basis': 'sto-3g'})
        self.assertEqual((exported.template_dir / 'seed.py').read_text(), '# fixture template\n')
        for invalid, detail in [('[]', 'mapping'), ('[', 'workflow')]:
            with self.subTest(invalid=invalid), self.assertRaisesRegex(ValueError, detail):
                bridge.act({**request, 'action': 'preview-mechanism-yaml', 'overrides': [{'path': [], 'yaml': invalid}]})

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

    def test_partial_orca_package_rejected(self):
        self.config('orca', 'template: step1.inp')
        (self.root / 'templates/step1.inp').write_text('! HF STO-3G\n')
        binary = self.root / 'orca'
        binary.write_text('#!/bin/sh\nexit 0\n'); binary.chmod(0o755)
        with patch.dict(os.environ, {'PATH': str(self.root)}):
            report = bridge.inspect_workflow(self.path)
        self.assertTrue(any(c['name'] == 'ORCA installation' and c['status'] == 'error' for c in report['checks']))

    def test_mac_preflight_rejects_non_mac_orca_without_executing_it(self):
        import subprocess
        self.config('orca', 'template: step1.inp')
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        binary=self.root/'orca';binary.write_text('#!/bin/sh\nexit 0\n');binary.chmod(0o755)
        for architecture in ['ELF 64-bit x86-64 executable','PE32+ executable x86-64']:
            with self.subTest(architecture=architecture), patch.dict(os.environ, {'PATH':str(self.root)}), patch.object(bridge.sys,'platform','darwin'), patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,architecture)) as probe:
                report=bridge.inspect_workflow(self.path)
            self.assertTrue(any(c['name']=='ORCA platform' and c['status']=='error' for c in report['checks']))
            probe.assert_called_once_with(['/usr/bin/file',str(binary)],capture_output=True,text=True)

    def test_mac_cuda_is_rejected_before_backend_provisioning(self):
        self.config('mlip', 'options: {task_name: omol, device: cuda}')
        self.path.write_text(self.path.read_text().replace('max_cores: 1','max_cores: 1\nmax_gpus: 1'))
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        with patch.object(bridge.sys,'platform','darwin'), patch('chemrefine.engines.preflight_backends') as backend:
            report=bridge.inspect_workflow(self.path)
        self.assertFalse(report['ok'])
        self.assertTrue(any(c['status']=='error' and 'CUDA is unavailable' in c['detail'] for c in report['checks']))
        backend.assert_not_called()

    def test_complete_orca_helper_families_accepted(self):
        self.config('orca', 'template: step1.inp')
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        (self.root / 'templates/step1.inp').write_text('! HF STO-3G\n')
        binary = self.root / 'orca'
        binary.write_text('#!/bin/sh\nexit 0\n'); binary.chmod(0o755)
        for names in (('orca_startup', 'orca_leanscf'), ('orca_scf', 'orca_gtoint')):
            with self.subTest(helpers=names):
                for name in names:
                    helper = self.root / name
                    helper.write_text('#!/bin/sh\nexit 0\n'); helper.chmod(0o755)
                with patch.dict(os.environ, {'PATH': str(self.root)}):
                    report = bridge.inspect_workflow(self.path)
                self.assertTrue(report['ok'], report)
                for name in names:
                    (self.root / name).unlink()

    def test_missing_header_blocks_even_local_run(self):
        self.config()
        bridge.act(dict(action='scaffold', config_path=str(self.path)))
        (self.root / 'templates/cpu.slurm.header').unlink()
        with patch('chemrefine.engines.preflight_backends'), patch('chemrefine.agent_tools.start_run') as launch:
            result = bridge.act(dict(action='run', config_path=str(self.path)))
        self.assertFalse(result['started']); launch.assert_not_called()
        self.assertTrue(any(c['status'] == 'error' and 'header' in c['detail'].lower() for c in result['report']['checks']))

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

    def test_recovery_actions_forward_target_and_use_preflight(self):
        report = dict(ok=True, checks=[], requiredBackends=[], missingBackends=[])
        for action in ('run', 'resume', 'rebuild-cache', 'rebuild-nms', 'rerun', 'rerun-errors'):
            with self.subTest(action=action), patch.object(bridge, 'inspect_workflow', return_value=report) as check, patch('chemrefine.agent_tools.start_run', return_value={'pid': 123, 'log': 'test.log'}) as launch:
                target = None if action in ('run', 'resume') else '2'
                result = bridge.act(dict(action=action, config_path=str(self.path), target=target))
                self.assertTrue(result['started'])
                launch.assert_called_once_with(str(self.path.resolve()), action=action, target=target)
                check.assert_called_once_with(str(self.path.resolve()), prepare_models=True)

    def test_energy_summary_minimum_names_missing_and_nonfinite(self):
        self.config()
        self.path.write_text(self.path.read_text() + '  - step: 2\n    name: refine\n    engine: pyscf\n')
        out = self.root / 'outputs'; out.mkdir()
        (out / 'steps.csv').write_text('Step,Conformer,Energy (Hartree),Energy type\n1,0,-1.0,electronic\n1,1,-1.1,electronic\n1,2,nan,electronic\n')
        result = bridge.act(dict(action='summary', config_path=str(self.path)))
        self.assertEqual(len(result['steps']), 2)
        first, second = result['steps']
        self.assertEqual(first['name'], 'Step 1'); self.assertEqual(second['name'], 'refine')
        self.assertEqual(first['energy_hartree'], -1.1); self.assertEqual(first['count'], 2)
        self.assertEqual(first['conformer'], '1'); self.assertTrue(first['previous'])
        self.assertIsNone(second['energy_hartree'])

    def test_python_environment_check_uses_selected_interpreter(self):
        import json
        binary = self.root / 'my-env/bin/python'; binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/sh\nexit 0\n'); binary.chmod(0o755)
        data = dict(python=str(binary), prefix=str(binary.parent.parent), fairchem='test', missing_server=[])
        with patch.object(bridge, 'child_run', return_value=json.dumps(data)) as run:
            result = bridge.act(dict(action='check-python', config_path=str(self.path), python_path=str(binary.parent.parent)))
        self.assertEqual(run.call_args.args[0][0], str(binary))
        self.assertIn('ExtOpt server imports available', result['detail'])
        for invalid in ('', str(self.root / 'missing')):
            with self.subTest(path=invalid), self.assertRaises(ValueError):
                bridge.act(dict(action='check-python', config_path=str(self.path), python_path=invalid))

    def test_status_is_real_chemrefine_status(self):
        self.config()
        result = bridge.act(dict(action='status', config_path=str(self.path)))
        self.assertFalse(result['running'])
        self.assertEqual(result['steps'][0]['engine'], 'pyscf')
        self.assertFalse(result['steps'][0]['cached'])


if __name__ == '__main__':
    unittest.main()
