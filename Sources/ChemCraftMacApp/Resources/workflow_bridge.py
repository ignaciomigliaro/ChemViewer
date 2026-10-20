"""ChemViewer's native ChemRefine controls. Uses the installed, pinned public API."""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path

_child = None


def _stop(signum, _frame):
    if _child is not None and _child.poll() is None:
        os.killpg(_child.pid, signal.SIGTERM)
    raise SystemExit(128 + signum)


def child_run(arguments, *, timeout=180):
    global _child
    _child = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        out, err = _child.communicate(timeout=timeout)
        if _child.returncode:
            raise RuntimeError((err + '\n' + out).strip()[-12000:] or 'Dependency preparation failed.')
        return out
    except subprocess.TimeoutExpired:
        os.killpg(_child.pid, signal.SIGTERM)
        _child.communicate()
        raise RuntimeError('Dependency/model preparation timed out. Prepare this backend/model before running.')
    finally:
        _child = None


def inspect_workflow(path, *, prepare_models=False):
    from chemrefine.validate import validate_config_file
    from chemrefine.engines import get_engine, preflight_backends
    from chemrefine.engines.api import ExecutablesDeclaring, ProvisionableEngine
    from chemrefine.engines._provision import resolve_launcher
    checks, required, missing = [], set(), set()

    def row(name, status, detail):
        checks.append(dict(name=name, status=status, detail=str(detail)))

    path = Path(path).expanduser().resolve()
    if not path.is_file():
        row('input.yaml', 'error', f'Workflow not found: {path}')
        return dict(ok=False, checks=checks, requiredBackends=[], missingBackends=[])
    report = validate_config_file(path)
    for issue in report.issues:
        row(' / '.join(map(str, issue.loc)) or 'Workflow', 'error', issue.message)
    for warning in report.warnings:
        blocking = warning.kind in ('input', 'template', 'executable', 'whitespace-path', 'budget', 'slurm-header')
        row(' / '.join(map(str, warning.loc)) or 'Workflow', 'error' if blocking else 'warning', warning.message)
    config = report.config
    if config is None:
        return dict(ok=False, checks=checks, requiredBackends=[], missingBackends=[])
    row('Workflow YAML', 'ok', path)
    if config.dispatch == 'slurm' or (config.dispatch == 'auto' and shutil.which('sbatch')):
        row('Local execution', 'error', "Set dispatch: local to run from this Mac.")
    else:
        row('Local execution', 'ok', config.dispatch)
    seed = config.input or config.default_input()
    if Path(seed).exists():
        row('Input structures', 'ok', seed)
    try:
        config.output_dir.mkdir(parents=True, exist_ok=True)
        config.scratch_dir.mkdir(parents=True, exist_ok=True)
        for folder in (config.output_dir, config.scratch_dir):
            if not os.access(folder, os.W_OK):
                raise PermissionError(f'Not writable: {folder}')
        row('Output and scratch', 'ok', f'{config.output_dir}\n{config.scratch_dir}')
    except OSError as error:
        row('Output and scratch', 'error', error)
    seen_executables = set()
    for step in config.steps:
        engine = get_engine(step.engine)
        label = f'Step {step.step} · {step.engine}'
        if isinstance(engine, ExecutablesDeclaring):
            for number, key in enumerate(engine.executable_keys):
                if key in seen_executables:
                    continue
                seen_executables.add(key)
                value = config.executables.get(key)
                if number > 0 and not value:
                    continue
                value = value or {'qc': 'qchem'}.get(key, key)
                if number > 0 and Path(value).is_dir():
                    row(key, 'ok', value)
                    continue
                executable = shutil.which(str(value))
                if executable is None:
                    row(key, 'error', f'Executable not found or not executable: {value}. Install it or choose its full path.')
                else:
                    row(key, 'ok', executable)
                    if key == 'orca':
                        directory = str(Path(executable).resolve().parent)
                        os.environ['ORCADIR'] = directory
                        os.environ['PATH'] = directory + os.pathsep + os.environ.get('PATH', '')
                        # ORCA 6.1 ships startup/leanscf, rather than the older
                        # scf/gtoint pair. Accept complete helper sets, not a mix.
                        helper_sets = (('orca_startup', 'orca_leanscf'), ('orca_scf', 'orca_gtoint'))
                        def helpers_present(names):
                            return all((Path(directory) / name).is_file() and os.access(Path(directory) / name, os.X_OK) for name in names)
                        if not any(helpers_present(names) for names in helper_sets):
                            row('ORCA installation', 'error', 'Missing ORCA helpers beside orca: expected orca_startup + orca_leanscf (6.1), or orca_scf + orca_gtoint. Install the complete ORCA package.')
                        if sys.platform == 'darwin':
                            architecture = subprocess.run(['/usr/bin/file', executable], capture_output=True, text=True).stdout.strip()
                            if 'ELF' in architecture or 'PE32' in architecture:
                                row('ORCA platform', 'error', f'Choose the macOS package. {architecture}')
        if step.engine in ('orca', 'mlip-extopt', 'pyscf-extopt'):
            from chemrefine.ids import step_template_path
            suffix = getattr(engine, 'template_suffix', 'inp')
            template = step_template_path(config.template_dir, step.step, template=step.template, suffix=suffix)
            if template.is_file():
                text = template.read_text(errors='replace')
                parallel = [int(a or b) for a, b in re.findall(r'\bPAL(\d+)\b|\bnprocs\s+(\d+)', text, flags=re.I)]
                if parallel and max(parallel) > 1 and shutil.which('mpirun') is None:
                    row(label + ' MPI', 'error', 'Parallel ORCA needs the MPI runtime matching its distribution. Install it, or choose a serial template.')
        if isinstance(engine, ProvisionableEngine):
            options = step.options or {}
            if sys.platform == 'darwin' and options.get('device') == 'cuda':
                row(label + ' device', 'error', 'CUDA is unavailable on this Mac; choose device: cpu before installing a backend.')
                continue
            requirement = None
            try:
                requirement = engine.backend_requirement(step.options or {})
                required.add(requirement.extra)
                preflight_backends([step])
                row(label + ' backend', 'ok', requirement.extra)
            except Exception as error:
                if requirement is not None:
                    missing.add(requirement.extra)
                row(label + ' backend', 'error', error)
                continue
            options = step.options or {}
            if sys.platform == 'darwin' and options.get('device') == 'cuda':
                row(label + ' device', 'error', 'CUDA is unavailable on this Mac; choose device: cpu.')
            model_path = options.get('model_path')
            deferred_model = False
            if model_path:
                checkpoint = Path(model_path).expanduser()
                if not checkpoint.is_absolute():
                    checkpoint = path.parent / checkpoint
                if not checkpoint.is_file():
                    deferred_model = any(s.step < step.step and s.engine == 'mlip-train' for s in config.steps) and checkpoint.resolve().is_relative_to(config.output_dir.resolve())
                    row(label + ' checkpoint', 'warning' if deferred_model else 'error',
                        f'Model will be produced by an earlier training step: {checkpoint}' if deferred_model else f'Missing model checkpoint: {checkpoint}')
            if prepare_models and step.engine in ('mlip', 'mlip-extopt') and not deferred_model:
                try:
                    python = resolve_launcher(requirement, options.get('backend_python'))
                    knobs = {key: options[key] for key in ('task_name', 'model_name', 'device', 'model_path') if key in options}
                    if model_path:
                        knobs['model_path'] = str(checkpoint)
                    knobs['charge'] = step.charge if step.charge is not None else config.charge
                    knobs['multiplicity'] = step.multiplicity if step.multiplicity is not None else config.multiplicity
                    code = 'import json,sys; from chemrefine.engines.mlip.calculator import build_calculator; build_calculator(**json.loads(sys.argv[1])); print("Model loaded")'
                    child_run([python, '-c', code, json.dumps(knobs)], timeout=180)
                    row(label + ' model', 'ok', 'Selected calculator and weights loaded successfully.')
                except Exception as error:
                    row(label + ' model', 'error', error)
                    if 'ModuleNotFoundError' in str(error) or 'ImportError' in str(error):
                        missing.add(requirement.extra)
            elif step.engine in ('mlip', 'mlip-extopt'):
                row(label + ' model', 'warning', 'The selected weights are loaded and verified by Run ChemRefine before any pipeline jobs start.')
    return dict(ok=not any(c['status'] == 'error' for c in checks), checks=checks,
                requiredBackends=sorted(required), missingBackends=sorted(missing))


def act(request):
    from chemrefine import agent_tools
    path = str(Path(request['config_path']).expanduser().resolve())
    action = request.get('action', 'check')
    if action == 'status':
        return agent_tools.run_status(path, log_tail_lines=60)
    if action == 'scaffold':
        created = agent_tools.scaffold_templates(path, overwrite=False)
        return dict(created=created, report=inspect_workflow(path))
    if action == 'install':
        report = inspect_workflow(path)
        extras = report['missingBackends']
        if extras:
            child_run([sys.executable, '-m', 'chemrefine', 'backends', 'install', *extras], timeout=1800)
        return inspect_workflow(path)
    if action == 'check':
        return inspect_workflow(path)
    if action == 'run':
        report = inspect_workflow(path, prepare_models=True)
        if not report['ok']:
            return dict(started=False, report=report)
        # The actual ChemRefine detached process owns locking, scheduling and result files.
        result = agent_tools.start_run(path, action='run')
        return dict(started=True, report=report, **result)
    raise ValueError('Unknown workflow action')


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, _stop)
    parser = argparse.ArgumentParser()
    parser.add_argument('request')
    parser.add_argument('result')
    args = parser.parse_args()
    try:
        result = act(json.loads(Path(args.request).read_text()))
        Path(args.result).write_text(json.dumps(result, allow_nan=False))
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
