// Minimal JS: optional architecture hint based on userAgent heuristics.
// Note: UA-based detection is not reliable; buttons remain visible for both APKs.
(function () {
    const hint = document.getElementById('arch-hint');
    if (!hint) return;
    try {
        const ua = navigator.userAgent || '';
        // Very rough heuristic: modern Android versions are almost always 64-bit capable.
        const isAndroid = /Android/i.test(ua);
        const versionMatch = ua.match(/Android\s([\d.]+)/i);
        const androidVersion = versionMatch ? parseFloat(versionMatch[1]) : undefined;
        if (isAndroid && androidVersion && androidVersion >= 10) {
            hint.textContent = 'Tip: Your device likely supports ARM64 (64‑bit).';
        }
    } catch (e) {/* ignore */ }
})();
