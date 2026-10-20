// ChemViewer integration; upstream ChemRefine remains unmodified.
(() => {
  const send = payload => window.webkit.messageHandlers.chemViewerWorkflow.postMessage(payload);
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
      try { await b.refreshStatus(); data = await send({action:'summary'}); render(); }
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
    window.chemViewerDashboard = {refresh, render, get data() { return data; }};
    refresh();
    setInterval(() => { if (!document.hidden) refresh(); }, 5000);
  }
  install();
})();
