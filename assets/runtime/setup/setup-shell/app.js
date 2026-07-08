(function () {
  const statusUrl = new URL('setup-shell-status.json', window.location.href).href;
  const pollMs = 1500;

  const els = {
    group: document.getElementById('group-label'),
    task: document.getElementById('task-label'),
    meta: document.getElementById('shell-meta'),
    stepPanel: document.getElementById('step-panel'),
    stepList: document.getElementById('step-list'),
    banner: document.getElementById('banner'),
    hero: document.getElementById('hero'),
  };

  function taskTone(phase, bannerKind) {
    if (phase === 'complete') return 'is-done';
    if (phase === 'failed' || bannerKind === 'fail') return 'is-fail';
    if (phase === 'reboot' || bannerKind === 'warn') return 'is-warn';
    if (phase !== 'running') return 'is-dim';
    return '';
  }

  function formatElapsed(ms) {
    const s = Math.floor(Math.max(0, ms) / 1000);
    const m = Math.floor(s / 60);
    const r = s % 60;
    return m + ':' + String(r).padStart(2, '0');
  }

  function visibleSteps(steps) {
    return (steps || []).filter(function (s) { return s.status !== 'done'; });
  }

  function stepClass(status) {
    if (status === 'current') return 'step step--current';
    return 'step step--pending';
  }

  function renderSteps(steps) {
    const list = visibleSteps(steps);
    els.stepPanel.classList.toggle('is-hidden', list.length === 0);
    els.stepList.innerHTML = '';
    for (const step of list) {
      const li = document.createElement('li');
      li.className = stepClass(step.status || 'pending');
      li.textContent = step.label || step.id || '';
      els.stepList.appendChild(li);
    }
  }

  function applyStatus(data) {
    if (!data) return;
    const phase = data.phase || 'running';
    const bannerKind = data.bannerKind || '';

    els.group.textContent = data.groupLabel || 'Setting up';
    els.task.textContent = data.taskLabel || data.currentStepLabel || 'Working…';
    els.task.className = 'task-label ' + taskTone(phase, bannerKind);

    if (els.meta) {
      const profile = data.profileName || 'WinMint';
      const elapsed = formatElapsed(Number(data.elapsedMs) || 0);
      els.meta.textContent = profile + ' · ' + elapsed + ' elapsed';
    }

    renderSteps(data.steps);

    els.banner.className = 'banner hidden';
    if (data.banner) {
      els.banner.textContent = data.banner;
      els.banner.classList.remove('hidden');
      els.banner.classList.add(bannerKind || 'warn');
    }
    if (data.heroPath) {
      els.hero.src = data.heroPath;
    }
  }

  async function poll() {
    try {
      const res = await fetch(`${statusUrl}?t=${Date.now()}`, { cache: 'no-store' });
      if (res.ok) {
        applyStatus(await res.json());
      }
    } catch (_) { /* host not ready yet */ }
  }

  poll();
  setInterval(poll, pollMs);
})();
