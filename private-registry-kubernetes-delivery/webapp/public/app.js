const startTime = Date.now();

function updateStats() {
    document.getElementById('hostname').textContent =
        window.location.hostname || 'localhost';

    document.getElementById('currentTime').textContent =
        new Date().toLocaleString();

    const uptime =
        Math.floor((Date.now() - startTime) / 1000);

    document.getElementById('uptime').textContent =
        uptime + ' seconds';
}

document.addEventListener(
    'DOMContentLoaded',
    function () {
        updateStats();
        setInterval(updateStats, 30000);
    }
);

console.log('Application loaded successfully.');
