"""Hermetic transport tests. Local Bash substitutes for SSH; no cluster jobs run."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1] / 'Sources/ChemCraftMacApp/Resources'


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


agent = load('remote_agent')
bridge = load('remote_bridge')


class RemoteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='chemviewer-remote-')
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_persistent_helper_reuses_process_after_error(self):
        child = subprocess.Popen([sys.executable, str(ROOT/'remote_agent.py'), '--chemviewer-serve'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            requests = [dict(action='list',path=str(self.root)),dict(action='list',path=str(self.root/'absent')),dict(action='list',path=str(self.root))]
            replies=[]
            for request in requests:
                child.stdin.write(json.dumps(request)+'\n'); child.stdin.flush()
                replies.append(json.loads(child.stdout.readline().split('CHEMVIEWER_JSON:',1)[1]))
            self.assertEqual([x['ok'] for x in replies],[True,False,True])
            self.assertEqual({x['server_pid'] for x in replies},{child.pid})
            child.stdin.close(); child.wait(timeout=5)
        finally:
            if child.poll() is None: child.kill();child.wait()
            child.stdout.close();child.stderr.close()

    def test_actual_ssh_command_enters_persistent_mode_without_eof(self):
        import select
        profile=dict(host='synthetic',python=sys.executable)
        arguments=bridge.run(dict(profile=profile,request=dict(action='connection-command')))['arguments']
        child=subprocess.Popen(['/bin/bash','-c',arguments[-1]],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            for _ in range(2):
                child.stdin.write(json.dumps(dict(action='list',path=str(self.root))).encode()+b'\n');child.stdin.flush()
                self.assertTrue(select.select([child.stdout],[],[],5)[0], 'Persistent request waited for stdin EOF')
                reply=json.loads(child.stdout.readline().split(b'CHEMVIEWER_JSON:',1)[1])
                self.assertTrue(reply['ok'])
            child.stdin.close();child.wait(timeout=5)
        finally:
            if child.poll() is None:child.kill();child.wait()
            child.stdout.close();child.stderr.close()

    def test_connection_preparation_does_not_execute_ssh(self):
        with patch.object(bridge,'ssh_exchange') as exchange:
            result=bridge.run(dict(profile=dict(host='synthetic'),request=dict(action='connection-command')))
            self.assertIn('--chemviewer-serve',result['arguments'][-1])
            exchange.assert_not_called()

    def test_alias_options_and_shell_injection_refused(self):
        for host in ('-oProxyCommand=id', 'a;touch /tmp/pwn', 'a\nwhoami', 'a host', ''):
            with self.assertRaises(ValueError):
                bridge.ssh_arguments({'host': host}, b'')
        args = bridge.ssh_arguments({'host': 'user@host-alias'}, b'')
        self.assertIn('BatchMode=yes', args)
        self.assertNotIn('StrictHostKeyChecking=no', args)
        self.assertIn('user@host-alias', args)
        self.assertIn('ControlPersist=8h', args)

    def test_wire_protocol_quotes_paths_and_preserves_bytes(self):
        file = self.root / "Café ' molecule $(touch SHOULD_NOT_EXIST).xyz"
        content = b'2\nenergy: -1.116759307204\nH 0 0 0\nH 0 0 .74\n'
        file.write_bytes(content)
        actual_run = subprocess.run
        def loopback(args, payload):
            # Execute exactly the command OpenSSH would pass to the remote login shell.
            return actual_run(['/bin/bash', '-c', args[-1]], input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        profile = dict(host='test-only', python=sys.executable)
        with patch.object(bridge, 'ssh_exchange', side_effect=loopback):
            listing = bridge.run(dict(profile=profile, request=dict(action='list', path=str(self.root))))
            result = bridge.run(dict(profile=profile, request=dict(action='read', path=str(file)), edit=True))
        self.assertEqual(listing['entries'][0]['name'], file.name)
        self.assertEqual(base64.b64decode(result['data']), content)
        self.assertEqual(result['sha256'], hashlib.sha256(content).hexdigest())
        self.assertFalse((self.root/'SHOULD_NOT_EXIST').exists())

    def test_remote_python_accepts_environment_folder(self):
        environment = self.root/'environment'; (environment/'bin').mkdir(parents=True)
        (environment/'bin/python').symlink_to(sys.executable)
        args = bridge.ssh_arguments(dict(host='test', python=str(environment)), b"print('ENVIRONMENT_FOLDER_OK')")
        result = subprocess.run(['/bin/bash', '-c', args[-1]], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b'ENVIRONMENT_FOLDER_OK', result.stdout)

    def test_remote_python_path_is_literal(self):
        marker = self.root / 'injected'
        args = bridge.ssh_arguments(dict(host='test', python=sys.executable + '; touch ' + str(marker)), b'')
        result = subprocess.run(['/bin/bash', '-c', args[-1]], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists())

    def test_read_cache_keeps_filename_and_refreshes(self):
        file = self.root / 'trajectory.xyz'
        file.write_text('1\nE=-1\nH 0 0 0\n')
        profile = dict(host='test-only', python=sys.executable)
        actual_run = subprocess.run
        with patch.object(bridge, 'ssh_exchange', side_effect=lambda args, payload: actual_run(['/bin/bash','-c',args[-1]], input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE)), patch.object(bridge.Path, 'home', return_value=self.root):
            first = bridge.run(dict(profile=profile, request=dict(action='read', path=str(file))))
            file.write_text('1\nE=-2\nH 0 0 1\n')
            second = bridge.run(dict(profile=profile, request=dict(action='read', path=str(file))))
        self.assertEqual(first['local'], second['local'])
        self.assertEqual(Path(second['local']).name, 'trajectory.xyz')
        self.assertEqual(Path(second['local']).read_bytes(), file.read_bytes())
        self.assertNotEqual(first['sha256'], second['sha256'])

    def test_editor_refuses_concurrent_update_and_symlink(self):
        path = self.root / 'input.yaml'; path.write_text('dispatch: slurm\n')
        original = agent.execute(dict(action='read', path=str(path)))
        change = dict(action='write', path=str(path), sha256=original['sha256'], data=base64.b64encode(b'dispatch: local\n').decode())
        path.write_text('changed elsewhere')
        with self.assertRaisesRegex(ValueError, 'changed'):
            agent.execute(change)
        path.write_text('dispatch: slurm\n')
        saved = agent.execute(change)
        self.assertTrue(saved['saved']); self.assertEqual(path.read_text(), 'dispatch: local\n')
        link = self.root / 'link'; link.symlink_to(path)
        change.update(path=str(link), sha256=saved['sha256'])
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            agent.execute(change)

    def test_upload_excludes_outputs_hidden_symlinks_and_never_overwrites(self):
        folder = self.root/'workflow'; folder.mkdir()
        (folder/'input.yaml').write_text('dispatch: slurm\n')
        (folder/'seed.xyz').write_text('2\nH2\nH 0 0 0\nH 0 0 .74\n')
        (folder/'.credentials').write_text('secret')
        (folder/'outputs').mkdir(); (folder/'outputs/result.xyz').write_text('excluded')
        (folder/'alias.xyz').symlink_to(folder/'seed.xyz')
        files = bridge.collect_workflow(folder)
        self.assertEqual(set(files), {'input.yaml','seed.xyz'})
        first = agent.execute(dict(action='upload',path=str(self.root),files=files))
        second = agent.execute(dict(action='upload',path=str(self.root),files=files))
        self.assertNotEqual(first['path'], second['path'])
        self.assertEqual(Path(first['config']).read_bytes(), (folder/'input.yaml').read_bytes())
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            agent.execute(dict(action='upload',path=str(self.root),files={'../escape': ''}))

    def config(self, dispatch='slurm'):
        (self.root/'seed.xyz').write_text('2\nH2\nH 0 0 0\nH 0 0 .74\n')
        (self.root/'templates').mkdir(exist_ok=True)
        (self.root/'templates/step1.inp').write_text('! HF STO-3G\n')
        (self.root/'templates/cpu.slurm.header').write_text('#SBATCH --time=00:05:00\n')
        path = self.root/'input.yaml'
        path.write_text('input: seed.xyz\ntemplate_dir: templates\noutput_dir: outputs\nscratch_dir: scratch\ndispatch: '+dispatch+'\nmax_cores: 1\nexecutables:\n  orca: /usr/bin/true\nsteps:\n  - step: 1\n    name: test\n    engine: orca\n    template: step1.inp\n')
        return path

    def test_environment_probe_has_no_workflow_or_submission_dependency(self):
        with patch('chemrefine.agent_tools.start_run') as launch:
            info = agent.execute(dict(action='info', path=str(self.root)))
            self.assertTrue(info['exists'])
            self.assertTrue(info['supported'])
            self.assertTrue(info['chemrefine'])
            launch.assert_not_called()

    def test_transport_timeout_cleans_up_ssh(self):
        from unittest.mock import MagicMock
        child = MagicMock()
        child.communicate.side_effect = [subprocess.TimeoutExpired('ssh',90), (b'',b'')]
        with patch.object(bridge.subprocess,'Popen',return_value=child):
            with self.assertRaisesRegex(ValueError, 'timed out after 90 seconds'):
                bridge.ssh_exchange(['ssh'], b'{}')
        child.kill.assert_called_once()
        self.assertEqual(child.communicate.call_count, 2)

    def test_remote_controls_refuse_local_dispatch_and_missing_slurm(self):
        path = self.config('local')
        with patch('chemrefine.agent_tools.start_run') as launch:
            with self.assertRaisesRegex(ValueError, 'dispatch: slurm'):
                agent.execute(dict(action='run',path=str(path)))
            path = self.config('slurm')
            with patch.object(agent.shutil,'which',return_value=None), self.assertRaisesRegex(ValueError, 'SLURM commands'):
                agent.execute(dict(action='run',path=str(path)))
            launch.assert_not_called()

    def test_remote_check_and_dispatch_use_supported_api(self):
        path = self.config()
        with patch.object(agent.shutil,'which',return_value='/cluster/bin/sbatch'), patch('chemrefine.agent_tools.start_run',return_value={'pid':123,'log':'test.log'}) as launch:
            report = agent.execute(dict(action='check',path=str(path)))
            self.assertTrue(report['ok']); launch.assert_not_called()
            for action in ('run','resume'):
                agent.execute(dict(action=action,path=str(path)))
                launch.assert_called_with(str(path), action=action)
        # /usr/bin/true is never executed: this tests orchestration only, not ORCA science.

    def test_missing_inputs_block_submission(self):
        path = self.config(); (self.root/'seed.xyz').unlink()
        with patch.object(agent.shutil,'which',return_value='/cluster/bin/sbatch'), patch('chemrefine.agent_tools.start_run') as launch:
            with self.assertRaisesRegex(ValueError, 'seed.xyz'):
                agent.execute(dict(action='run',path=str(path)))
            launch.assert_not_called()

    def test_status_reads_real_persisted_energies_and_step_names(self):
        path = self.config(); output=self.root/'outputs'; output.mkdir()
        (output/'steps.csv').write_text('Step,Conformer,Energy (Hartree),Energy type\n1,0,-1.116759307204,electronic\n')
        status = agent.execute(dict(action='status',path=str(path)))
        self.assertFalse(status['running'])
        self.assertEqual(status['results'][0]['name'], 'test')
        self.assertEqual(status['results'][0]['results']['rows'][0]['Energy (Hartree)'], '-1.116759307204')


if __name__ == '__main__':
    unittest.main()
