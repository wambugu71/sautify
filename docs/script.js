document.addEventListener('DOMContentLoaded', () => {
    // Scroll Animations
    const observerOptions = {
        threshold: 0.1,
        rootMargin: "0px 0px -50px 0px"
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
            }
        });
    }, observerOptions);

    const fadeElements = document.querySelectorAll('.fade-in');
    fadeElements.forEach(el => observer.observe(el));

    // Navbar Background on Scroll
    const header = document.querySelector('header');
    window.addEventListener('scroll', () => {
        if (window.scrollY > 50) {
            header.style.background = 'rgba(12, 11, 11, 0.95)';
            header.style.boxShadow = '0 2px 10px rgba(0,0,0,0.3)';
        } else {
            header.style.background = 'rgba(12, 11, 11, 0.8)';
            header.style.boxShadow = 'none';
        }
    });

    // Smooth Scroll for Anchor Links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth'
                });
            }
        });
    });

    // Carousel Logic
    const gallery = document.getElementById('gallery');
    const items = document.querySelectorAll('.gallery-item');
    let currentIndex = 0;
    const totalItems = items.length;

    function updateCarousel() {
        items.forEach((item, index) => {
            item.className = 'gallery-item'; // Reset classes

            // Calculate relative position
            let diff = index - currentIndex;

            // Handle wrap-around for infinite feel (optional, but simple logic first)
            if (diff > totalItems / 2) diff -= totalItems;
            if (diff < -totalItems / 2) diff += totalItems;

            if (diff === 0) {
                item.classList.add('active');
            } else if (diff === 1 || (currentIndex === totalItems - 1 && index === 0)) {
                item.classList.add('next');
            } else if (diff === -1 || (currentIndex === 0 && index === totalItems - 1)) {
                item.classList.add('prev');
            } else {
                // Hide others or stack them behind
                item.style.opacity = '0';
                item.style.transform = 'scale(0.5)';
            }

            // Clean up inline styles for active/prev/next
            if (diff === 0 || diff === 1 || diff === -1 || (currentIndex === totalItems - 1 && index === 0) || (currentIndex === 0 && index === totalItems - 1)) {
                item.style.opacity = '';
                item.style.transform = '';
            }
        });
    }

    // Initialize
    updateCarousel();

    // Auto-rotate
    setInterval(() => {
        currentIndex = (currentIndex + 1) % totalItems;
        updateCarousel();
    }, 3000);

    // Fetch Latest Release from GitHub
    const repoOwner = 'wambugu71';
    const repoName = 'sautify';
    const downloadContainer = document.getElementById('download-buttons');

    fetch(`https://api.github.com/repos/${repoOwner}/${repoName}/releases/latest`)
        .then(response => response.json())
        .then(data => {
            downloadContainer.innerHTML = ''; // Clear loading text

            if (data.assets && data.assets.length > 0) {
                // Filter for APKs
                const apks = data.assets.filter(asset => asset.name.endsWith('.apk'));

                if (apks.length > 0) {
                    apks.forEach(apk => {
                        // Parse ABI from filename (e.g., app-arm64-v8a-release.apk -> arm64-v8a)
                        let abi = 'Universal';
                        if (apk.name.includes('arm64-v8a')) abi = 'arm64-v8a';
                        else if (apk.name.includes('armeabi-v7a')) abi = 'armeabi-v7a';
                        else if (apk.name.includes('x86_64')) abi = 'x86_64';
                        else if (apk.name.includes('universal')) abi = 'Universal';

                        const btn = document.createElement('a');
                        btn.href = apk.browser_download_url;
                        btn.className = 'cta-button download-btn';
                        btn.innerHTML = `<i class="fab fa-android"></i> Download ${abi}`;
                        downloadContainer.appendChild(btn);
                    });
                } else {
                    // Fallback button
                    const btn = document.createElement('a');
                    btn.href = data.html_url;
                    btn.className = 'cta-button download-btn';
                    btn.textContent = 'Download from GitHub';
                    downloadContainer.appendChild(btn);
                }
            } else {
                const btn = document.createElement('a');
                btn.href = `https://github.com/${repoOwner}/${repoName}/releases`;
                btn.className = 'cta-button download-btn';
                btn.textContent = 'Go to Releases';
                downloadContainer.appendChild(btn);
            }
        })
        .catch(error => {
            console.error('Error fetching release:', error);
            downloadContainer.innerHTML = `<a href="https://github.com/${repoOwner}/${repoName}/releases" class="cta-button download-btn">Download from GitHub</a>`;
        });
});
