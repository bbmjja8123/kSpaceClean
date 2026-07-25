const API_BASE = '/api';

async function fetchJSON(url) {
  const res = await fetch(url);
  return res.json();
}

async function triggerScan() {
  document.getElementById('scan-btn').disabled = true;
  document.getElementById('scan-progress').classList.remove('hidden');
  document.getElementById('status-badge').textContent = 'Scanning';
  document.getElementById('status-badge').className = 'status-scanning';

  // Poll for results
  setTimeout(() => loadResults(), 3000);
}

async function loadResults() {
  const data = await fetchJSON(`${API_BASE}/results`);
  const tbody = document.getElementById('results-body');
  const noResults = document.getElementById('no-results');

  if (data.results && data.results.length > 0) {
    noResults.classList.add('hidden');
    tbody.innerHTML = data.results.map(r =>
      `<tr><td>${r.category}</td><td>${r.count}</td><td>${formatBytes(r.size)}</td></tr>`
    ).join('');
  }

  document.getElementById('status-badge').textContent = 'Completed';
  document.getElementById('status-badge').className = 'status-completed';
  document.getElementById('scan-btn').disabled = false;
  document.getElementById('scan-progress').classList.add('hidden');
}

function formatBytes(bytes) {
  if (!bytes) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  let size = bytes;
  while (size >= 1024 && i < units.length - 1) { size /= 1024; i++; }
  return `${size.toFixed(1)} ${units[i]}`;
}

// Auto-refresh
setInterval(() => {
  fetchJSON(`${API_BASE}/status`).then(data => {
    document.getElementById('status-badge').textContent = data.status;
  });
}, 10000);

// Load on page load
loadResults();
