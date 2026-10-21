"""Local SSH transport. Arguments and data never interpolate into remote shell code."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import shlex
import subprocess
import sys
import tempfile


def ssh_arguments(profile, agent, persistent=False):
    host = profile.get('host', '').strip()
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.@:-]*', host):
        raise ValueError('Use an SSH alias or user@hostname, without options or spaces. Configure ports/jump hosts in ~/.ssh/config.')
    python = profile.get('python', 'python3').strip() or 'python3'
    if '\x00' in python or '\n' in python:
        raise ValueError('Invalid remote Python path.')
    # expanduser inside remote Python is unavailable before it launches: shell expands only leading ~/.
    command = ('"$HOME"/' + shlex.quote(python[2:])) if python.startswith('~/') else shlex.quote(python)
    bootstrap = "import base64,sys;" + ("sys.argv.append('--chemviewer-serve');" if persistent else "") + "exec(compile(base64.b64decode(" + repr(base64.b64encode(agent).decode()) + "),'<chemviewer-remote>','exec'))"
    setup = profile.get('setup', '').strip()
    # Setup is deliberately executable user-authored shell, not inferred from any file.
    shell = 'set -e\n' + (setup + '\n' if setup else '') + 'chemviewer_remote_python=' + command + '\nif [ -d \"$chemviewer_remote_python\" ]; then chemviewer_remote_python=\"$chemviewer_remote_python/bin/python\"; fi\nexec \"$chemviewer_remote_python\" -c ' + shlex.quote(bootstrap)
    control = control_path(host)
    return ['/usr/bin/ssh', '-S', str(control), '-o', 'ControlMaster=auto', '-o', 'ControlPersist=8h', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2', host, '/bin/bash -c ' + shlex.quote(shell)]


def control_path(host):
    directory = Path('/private/tmp') / ('chemviewer-ssh-' + str(os.getuid()))
    directory.mkdir(mode=0o700, exist_ok=True)
    stat = directory.lstat()
    if directory.is_symlink() or stat.st_uid != os.getuid() or stat.st_mode & 0o077:
        raise ValueError('SSH control directory must be private and owned by you.')
    return directory / hashlib.sha256(host.encode()).hexdigest()[:20]


def collect_workflow(folder):
    folder = Path(folder)
    files = {}
    size = 0
    excluded = {'.git', '.venv', 'venv', '__pycache__', 'outputs', 'scratch', '.DS_Store'}
    for root, dirs, names in os.walk(folder, followlinks=False):
        dirs[:] = [name for name in dirs if name not in excluded and not name.startswith('.')]
        for name in names:
            path = Path(root) / name
            relative = path.relative_to(folder)
            # Send workflow inputs only, never secrets or arbitrary environment files.
            if path.is_symlink() or name.startswith('.') or path.suffix.lower() not in {'.yaml', '.yml', '.xyz', '.inp', '.py', '.header', '.json', '.txt'}:
                continue
            size += path.stat().st_size
            if size > 100_000_000 or len(files) >= 2000:
                raise ValueError('Workflow upload exceeds 100 MB / 2,000 files. Use a dedicated workflow input folder.')
            files[str(relative)] = base64.b64encode(path.read_bytes()).decode()
    if 'input.yaml' not in files:
        raise ValueError('Choose a workflow folder containing input.yaml.')
    return files


def ssh_exchange(args, payload):
    child = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    previous = signal.getsignal(signal.SIGTERM)
    def cancel(signum, frame):
        child.terminate()
        raise RuntimeError('SSH request cancelled. Submitted remote jobs continue independently.')
    signal.signal(signal.SIGTERM, cancel)
    try:
        stdout, stderr = child.communicate(payload, timeout=90)
        return subprocess.CompletedProcess(args, child.returncode, stdout, stderr)
    except BaseException as error:
        child.kill()
        try:
            child.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            for stream in (child.stdin, child.stdout, child.stderr):
                if stream:
                    stream.close()
        if isinstance(error, subprocess.TimeoutExpired):
            raise ValueError('SSH request timed out after 90 seconds. Check the remote environment or cancel and retry; already submitted jobs continue on the cluster.') from None
        raise
    finally:
        signal.signal(signal.SIGTERM, previous)


def run(request):
    profile = request['profile']
    payload = request['request']
    if payload['action'] == 'connection-command':
        agent = Path(__file__).with_name('remote_agent.py').read_bytes()
        arguments = ssh_arguments(profile, agent, persistent=True)
        return dict(arguments=arguments)
    if payload['action'] == 'gui-command':
        # stdin EOF owns the editor lifetime. The GUI never detaches or submits work.
        config = payload.get('path', '')
        program = """import os,sys,subprocess,threading
from pathlib import Path
config = CONFIG
args = [sys.executable, '-m', 'chemrefine', 'gui']
if config: args.append(str(Path(config).expanduser().absolute()))
args += ['--no-browser', '--port', '0']
env = dict(os.environ, PYTHONUNBUFFERED='1')
child = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
def output():
    for line in child.stdout:
        sys.stdout.buffer.write(line); sys.stdout.buffer.flush()
    os._exit(child.wait())
threading.Thread(target=output, daemon=True).start()
try: sys.stdin.buffer.read()
finally:
    child.terminate()
    try: child.wait(timeout=5)
    except subprocess.TimeoutExpired: child.kill(); child.wait()
""".replace('CONFIG', repr(config), 1)
        return dict(arguments=ssh_arguments(profile, program.encode()))
    if payload['action'] == 'tunnel-command':
        import socket
        remote_port = int(payload['port'])
        if not 1 <= remote_port <= 65535: raise ValueError('Invalid remote port.')
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            local_port = sock.getsockname()[1]
        arguments = ssh_arguments(profile, b'')[:-1]
        arguments[-1:-1] = ['-N', '-o', 'ExitOnForwardFailure=yes', '-L', f'127.0.0.1:{local_port}:127.0.0.1:{remote_port}']
        return dict(arguments=arguments, port=local_port)
    if payload['action'] == 'prepare-upload':
        return dict(files=collect_workflow(request['folder']))
    if payload['action'] == 'authenticate':
        ssh_arguments(profile, b'')
        command = ['/usr/bin/ssh', '-M', '-S', str(control_path(profile['host'].strip())), '-o', 'ControlPersist=8h', '-o', 'ControlMaster=auto', '-fN', profile['host'].strip()]
        fd, name = tempfile.mkstemp(prefix='chemviewer-ssh-', suffix='.command')
        with os.fdopen(fd, 'w') as stream:
            stream.write('#!/bin/bash\n' + shlex.join(command) + '\n')
        os.chmod(name, 0o700)
        return dict(terminal=name)
    if payload['action'] == 'upload':
        payload['files'] = collect_workflow(request['folder'])
    agent = Path(__file__).with_name('remote_agent.py').read_bytes()
    args = ssh_arguments(profile, agent)
    result = ssh_exchange(args, json.dumps(payload).encode())
    lines = result.stdout.decode('utf-8', errors='replace').splitlines()
    messages = [line[len('CHEMVIEWER_JSON:'):] for line in lines if line.startswith('CHEMVIEWER_JSON:')]
    if not messages:
        detail = result.stderr.decode('utf-8', errors='replace')[-5000:]
        if 'Permission denied' in detail:
            detail += '\nUse Authenticate in Terminal, complete the login, then retry.'
        raise ValueError(detail or 'No response from remote Python. Check Python path and SSH environment commands.')
    response = json.loads(messages[-1])
    if not response['ok']:
        raise ValueError(response.get('error', 'Remote operation failed.'))
    if result.returncode:
        raise ValueError(result.stderr.decode('utf-8', errors='replace')[-5000:] or 'SSH command failed.')
    data = response['result']
    if payload['action'] == 'read' and not request.get('edit'):
        contents = base64.b64decode(data.pop('data'), validate=True)
        if hashlib.sha256(contents).hexdigest() != data['sha256']:
            raise ValueError('Remote content checksum mismatch.')
        key = hashlib.sha256((profile['host'] + '\0' + data['path']).encode()).hexdigest()
        cache = Path.home() / 'Library/Caches/org.cleanroom.ChemViewer/remote' / key
        cache.mkdir(parents=True, exist_ok=True)
        target = cache / Path(data['path']).name
        temporary = cache / '.transfer'
        temporary.write_bytes(contents)
        temporary.replace(target)
        data['local'] = str(target)
    return data


if __name__ == '__main__':
    try:
        request = json.loads(Path(sys.argv[1]).read_text())
        response = dict(ok=True, result=run(request))
    except Exception as error:
        response = dict(ok=False, error=str(error))
    Path(sys.argv[2]).write_text(json.dumps(response, allow_nan=False))
