// ChemViewer integration; upstream ChemRefine remains unmodified.
(() => {
  const send = payload => window.webkit.messageHandlers.chemViewerWorkflow.postMessage(payload);
  window.chemViewerApplyUMAPython = async (path, overwrite) => {
    const b = window.Alpine && document.body && Alpine.$data(document.body);
    if (!b || !b.savedPath) throw new Error('Open a workflow first.');
    window.chemViewerCommitBackendFields?.();
    clearTimeout(b._timer);
    let config = b.cfg;
    if (b.rawEdit) {
      const parsed = await b.api('POST', '/api/parse', {yaml_text:b.yamlText});
      if (!parsed) throw new Error(b.flash || 'Invalid workflow YAML.');
      config = parsed.config;
    }
    let changed = 0;
    const heads = new Set(['omol','omat','odac','oc20','oc22','oc25','omc']);
    for (const step of config.steps || []) {
      if (!['mlip','mlip-extopt','mlip-train'].includes(String(step.engine).toLowerCase())) continue;
      const task = String(step.options?.task_name || step.options?.task || 'omol').toLowerCase();
      if (!heads.has(task)) continue;
      step.options = step.options || {};
      if (overwrite || !step.options.backend_python) { step.options.backend_python = path; changed++; }
    }
    if (changed) {
      const emitted = await b.api('POST', '/api/yaml', {config});
      if (!emitted) throw new Error(b.flash || 'Could not apply Python environment.');
      b.cfg = config; b.yamlText = emitted.yaml_text;
      window.chemViewerDashboard?.renderEnvironments();
    }
    return changed;
  };
  const fetchOriginal = window.fetch.bind(window);
  let launching = false;
  let notify = () => {};
  // Install before the editor scripts initialise, so even the first click is routed.
  window.fetch = async function(resource, options = {}) {
    const url = new URL(typeof resource === 'string' ? resource : resource.url, location.href);
    if (url.origin === location.origin && url.pathname === '/api/run' && options.method === 'POST') {
      if (launching) return new Response(JSON.stringify({error:'A workflow action is already being prepared.'}), {status:409});
      launching = true;
      try {
        const body = JSON.parse(options.body || '{}');
        notify('Saving editor and preparing ' + body.action + '…');
        const result = await send({action:body.action, target:body.target == null ? null : String(body.target)});
        if (!result.started) {
          const errors = (result.report?.checks || []).filter(c => c.status === 'error').map(c => c.name + ': ' + c.detail);
          throw new Error(errors.join('\n') || 'Workflow not started; check readiness above.');
        }
        notify(body.action + ' started (PID ' + result.pid + ').');
        setTimeout(() => window.chemViewerDashboard?.refresh(), 1200);
        return new Response(JSON.stringify(result), {status:200});
      } catch (e) {
        const message = String(e.message || e); notify(message);
        return new Response(JSON.stringify({error:message}), {status:400});
      } finally { launching = false; }
    }
    return fetchOriginal(resource, options);
  };
  function install() {
    let b;
    try { b = document.body && window.Alpine && Alpine.$data(document.body); } catch (_) {}
    const dashboard = document.querySelector('#run');
    if (!b || !b.api || !b.savedPath || !dashboard) { setTimeout(install, 150); return; }
    if (window.chemViewerDashboard) return;
    let loading = false, data = null;
    const environments = document.createElement('section');
    environments.id = 'chemviewer-python-environments';
    const heading = document.createElement('b'); heading.textContent = 'MLIP Python environments';
    const hint = document.createElement('p'); hint.className = 'muted';
    hint.textContent = 'Per-step Python overrides the UMA default above. Empty uses that default or a ChemRefine-managed backend. Edit raw YAML directly when raw editing is enabled.';
    const paths = document.createElement('div'); environments.append(heading,hint,paths);
    const anchor = dashboard.querySelector('table.runsteps');
    if (anchor) anchor.before(environments); else dashboard.appendChild(environments);
    function renderEnvironments() {
      const steps = (b.cfg.steps || []).filter(s => ['mlip','mlip-extopt','mlip-train'].includes(String(s.engine).toLowerCase()));
      const keys = new Set(steps.map(s => String(s.step)));
      for (const row of Array.from(paths.children)) if (!keys.has(row.dataset.step)) row.remove();
      for (const step of steps) {
        let row = Array.from(paths.children).find(r => r.dataset.step === String(step.step));
        if (!row) {
          row = document.createElement('label'); row.dataset.step = String(step.step);
          row.style.cssText = 'display:flex;gap:10px;align-items:center;margin-bottom:8px';
          const caption = document.createElement('span'); caption.style.minWidth = '120px';
          const input = document.createElement('input'); input.type='text'; input.style.flex='1';
          input.placeholder='Python executable (default above / managed backend)';
          input.addEventListener('input', () => { input.dataset.dirty = 'true'; });
          input.addEventListener('change', () => {
            const current = (b.cfg.steps || []).find(s => String(s.step) === row.dataset.step);
            if (!current || b.rawEdit) return;
            current.options = current.options || {};
            if (input.value.trim()) current.options.backend_python = input.value.trim();
            else delete current.options.backend_python;
            delete input.dataset.dirty; b.syncYaml();
          });
          row.append(caption,input); paths.appendChild(row);
        }
        row.firstChild.textContent = 'Step ' + step.step + (step.name ? ' · ' + step.name : '');
        const input = row.querySelector('input');
        input.setAttribute('aria-label', 'Python for step ' + step.step);
        input.disabled = !!b.rawEdit;
        if (document.activeElement !== input && !input.dataset.dirty) input.value = step.options?.backend_python || '';
      }
      environments.hidden = steps.length === 0;
    }

    window.chemViewerCommitBackendFields = () => {
      if (b.rawEdit) return;
      for (const input of paths.querySelectorAll('input[data-dirty]')) input.dispatchEvent(new Event('change'));
    };
    const section = document.createElement('section'); section.id = 'chemviewer-step-summary';
    section.style.cssText = 'border-top:1px solid #d6dde7;margin-top:12px;padding-top:10px;overflow-x:auto';
    // Only static markup is inserted; scientific data/names use textContent below.
    section.innerHTML = '<div style="display:flex;gap:10px;align-items:center"><b>Step energy summary</b><select aria-label="Energy units"><option value="1">Eh</option><option value="627.5094740630558">kcal/mol</option><option value="2625.4996394798254">kJ/mol</option><option value="27.211386245981">eV</option></select><button type="button">Copy table</button><button type="button">Refresh energies</button></div><p class="muted">Lowest reported energy per step. Different methods have different energy references.</p><p role="status" style="white-space:pre-wrap"></p><table class="runsteps"><thead><tr><th>Step / name</th><th>Engine</th><th>Status</th><th>Energy</th><th>Units</th><th>Energy type</th><th>Conformer</th><th>Count</th></tr></thead><tbody></tbody></table>';
    const existingTable = dashboard.querySelector('table.runsteps');
    if (existingTable) existingTable.before(section); else dashboard.appendChild(section);
    const units = section.querySelector('select'), tbody = section.querySelector('tbody');
    const panelStatus = section.querySelector('[role=status]');
    notify = message => { panelStatus.textContent = message; };
    dashboard.open = true;
    const buttons = section.querySelectorAll('button');
    function values(row) {
      const unit = units.options[units.selectedIndex].textContent;
      const energy = row.energy_hartree == null ? '—' : (row.energy_hartree * Number(units.value)).toFixed(Number(units.value) === 1 ? 10 : 6);
      return [row.step + ' · ' + row.name, row.engine, row.status + (row.previous ? ' (previous results)' : ''), energy, unit, row.energy_type || '—', row.conformer || '—', String(row.count)];
    }
    function render() {
      tbody.replaceChildren();
      for (const row of data?.steps || []) {
        const tr = document.createElement('tr');
        for (const value of values(row)) { const td = document.createElement('td'); td.textContent = value; tr.appendChild(td); }
        tbody.appendChild(tr);
      }
    }
    async function refresh() {
      if (loading) return;
      loading = true;
      try { renderEnvironments(); await b.refreshStatus(); data = await send({action:'summary'}); render(); }
      catch (e) { panelStatus.textContent = 'Could not load step energies: ' + String(e.message || e); }
      finally { loading = false; }
    }
    units.addEventListener('change', render);
    buttons[0].addEventListener('click', async () => {
      try {
        const text = ['Step / name\tEngine\tStatus\tEnergy\tUnits\tEnergy type\tConformer\tCount', ...(data?.steps || []).map(row => values(row).join('\t'))].join('\n');
        await send({action:'copy',text}); panelStatus.textContent = 'Step table copied.';
      } catch (e) { panelStatus.textContent = String(e.message || e); }
    });
    buttons[1].addEventListener('click', refresh);
    window.chemViewerDashboard = {refresh, render, renderEnvironments, get data() { return data; }};
    refresh();
    setInterval(() => { if (!document.hidden) refresh(); }, 5000);
  }
  install();
})();
