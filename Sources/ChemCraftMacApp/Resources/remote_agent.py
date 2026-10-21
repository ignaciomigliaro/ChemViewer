"""Original ChemViewer remote helper. Runs over authenticated SSH; no server install."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

LIMIT = 100_000_000


def remote_path(value):
    return Path(value).expanduser().absolute()


def execute(request):
    action = request['action']
    path = remote_path(request.get('path', '~'))
    if action == 'info':
        from importlib.metadata import version
        from importlib.util import find_spec
        return dict(python=sys.executable, chemrefine=version('chemrefine'), directory=str(path), exists=path.is_dir(), sbatch=shutil.which('sbatch'), squeue=shutil.which('squeue'), supported=find_spec('chemrefine.agent_tools') is not None)
    if action == 'list':
        entries = []
        with os.scandir(path) as listing:
            for item in listing:
                try:
                    # d_type avoids an NFS metadata lookup for ordinary entries.
                    directory = item.is_dir(follow_symlinks=True)
                    entries.append(dict(name=item.name, path=item.path, directory=directory, size=0))
                except OSError:
                    continue
                if len(entries) > 10000:
                    raise ValueError('Directory exceeds 10,000 entries. Choose a more specific path.')
        return dict(path=str(path), parent=str(path.parent), entries=sorted(entries, key=lambda x: (not x['directory'], x['name'].casefold())))
    if action == 'read':
        if path.stat().st_size > LIMIT:
            raise ValueError('File exceeds the 100 MB viewer limit.')
        data = path.read_bytes()
        if len(data) > LIMIT:
            raise ValueError('File grew beyond 100 MB.')
        return dict(path=str(path), data=base64.b64encode(data).decode(), sha256=hashlib.sha256(data).hexdigest())
    if action == 'write':
        # Explicit editor Save only; refuse overwriting a changed file.
        data = base64.b64decode(request['data'], validate=True)
        if len(data) > 2_000_000:
            raise ValueError('Editor limit is 2 MB.')
        old = path.read_bytes()
        if hashlib.sha256(old).hexdigest() != request['sha256']:
            raise ValueError('The remote file changed. Reopen it before saving.')
        if path.is_symlink():
            raise ValueError('Editing symlinks is disabled; open the target path.')
        fd, temp = tempfile.mkstemp(prefix='.chemviewer-', dir=str(path.parent))
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
            os.chmod(temp, path.stat().st_mode & 0o777)
            os.replace(temp, path)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
        return dict(path=str(path), sha256=hashlib.sha256(data).hexdigest(), saved=True)
    if action == 'upload':
        # New exclusive directory: never merge into or overwrite an existing workflow.
        import uuid
        root = path / ('ChemViewer-workflow-' + uuid.uuid4().hex[:12])
        files = request['files']
        decoded = []
        size = 0
        for name, encoded in files.items():
            relative = Path(name)
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unsafe upload path.')
            data = base64.b64decode(encoded, validate=True)
            size += len(data)
            if size > LIMIT:
                raise ValueError('Workflow exceeds 100 MB.')
            decoded.append((relative, data))
        if not any(str(name) == 'input.yaml' for name, _ in decoded):
            raise ValueError('Workflow folder must contain input.yaml.')
        root.mkdir(mode=0o700)
        try:
            for relative, data in decoded:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
        except Exception:
            shutil.rmtree(root)
            raise
        return dict(path=str(root), config=str(root / 'input.yaml'), count=len(decoded))
    if action in ('check', 'status', 'run', 'resume'):
        from chemrefine import agent_tools
        if action == 'status':
            result = agent_tools.run_status(str(path), log_tail_lines=60)
            from chemrefine.config import load_config
            config = load_config(path)
            result['results'] = [dict(step=step.step, name=step.name or 'Step ' + str(step.step), results=agent_tools.get_results(str(path), step=step.step, limit=20)) for step in config.steps]
            return result
        from chemrefine.validate import validate_config_file
        report = validate_config_file(path)
        from chemrefine.config import load_config
        config = load_config(path)
        if config.dispatch != 'slurm':
            raise ValueError('Set dispatch: slurm in the remote input.yaml. Local dispatch is refused by the remote controls.')
        missing = [name for name in ('sbatch', 'squeue') if not shutil.which(name)]
        if missing:
            raise ValueError('Missing SLURM commands: ' + ', '.join(missing) + '. Set the connection environment commands.')
        # Remote workstation-specific paths must be explicit; never silently reuse Mac paths.
        blocking = [item.message for item in report.warnings if item.kind in ('input', 'template', 'executable', 'whitespace-path', 'budget', 'slurm-header')]
        if blocking:
            raise ValueError('Remote preflight: ' + '; '.join(blocking))
        if not report.ok:
            raise ValueError(json.dumps(report.to_json()))
        if action == 'check':
            return dict(ok=True, python=sys.executable, config=str(path), validation=report.to_json())
        return agent_tools.start_run(str(path), action=action)
    raise ValueError('Unknown remote action: ' + action)


def response(request):
    try:
        return dict(ok=True, result=execute(request), server_pid=os.getpid())
    except Exception as error:
        return dict(ok=False, error=str(error), server_pid=os.getpid())


if __name__ == '__main__':
    if '--chemviewer-serve' in sys.argv:
        # One authenticated channel, many requests; imports stay warm between calls.
        for line in sys.stdin:
            try:
                reply = response(json.loads(line))
            except Exception as error:
                reply = dict(ok=False, error=str(error))
            print('CHEMVIEWER_JSON:' + json.dumps(reply, allow_nan=False, default=str), flush=True)
    else:
        reply = response(json.loads(sys.stdin.read()))
        print('CHEMVIEWER_JSON:' + json.dumps(reply, allow_nan=False, default=str), flush=True)
        sys.exit(0 if reply['ok'] else 1)
