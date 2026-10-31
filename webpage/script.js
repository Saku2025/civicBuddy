// CivicBuddy landing page behaviour.

const RELEASES_API =
  'https://api.github.com/repos/Saku2025/civicBuddy/releases/latest';
// Permanent direct download of the newest APK (every release attaches a
// CivicBuddy.apk). Used by the buttons and the QR code; needs no API call,
// so it works even when GitHub's API rate limit is hit.
const LATEST_APK_URL =
  'https://github.com/Saku2025/civicBuddy/releases/latest/download/CivicBuddy.apk';

const root = document.documentElement;
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// ------------------------------------------------------------
// Theme toggle (remembered per browser)
// ------------------------------------------------------------

function readSavedTheme() {
  try {
    return localStorage.getItem('civicbuddy-theme');
  } catch {
    return null;
  }
}

function saveTheme(theme) {
  try {
    localStorage.setItem('civicbuddy-theme', theme);
  } catch {
    // Storage unavailable (private mode); the toggle still works for this visit.
  }
}

const savedTheme = readSavedTheme();
if (savedTheme === 'light' || savedTheme === 'dark') {
  root.dataset.theme = savedTheme;
}

document.querySelector('.theme-toggle').addEventListener('click', () => {
  const isDark =
    root.dataset.theme === 'dark' ||
    (!root.dataset.theme && window.matchMedia('(prefers-color-scheme: dark)').matches);
  root.dataset.theme = isDark ? 'light' : 'dark';
  saveTheme(root.dataset.theme);
});

// ------------------------------------------------------------
// Scroll reveal + count-up stats
// ------------------------------------------------------------

document.querySelectorAll('.steps .reveal, .features .reveal').forEach((el, i) => {
  el.style.setProperty('--delay', `${(i % 4) * 0.1}s`);
});

function countUp(el) {
  const target = Number(el.dataset.count);
  if (reduceMotion) {
    el.textContent = target;
    return;
  }
  const start = performance.now();
  const duration = 1200;
  const tick = (now) => {
    const t = Math.min((now - start) / duration, 1);
    el.textContent = Math.round(target * (1 - Math.pow(1 - t, 3)));
    if (t < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

const observer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('visible');
      entry.target.querySelectorAll('[data-count]').forEach(countUp);
      observer.unobserve(entry.target);
    }
  },
  { threshold: 0.15 },
);

document.querySelectorAll('.reveal').forEach((el) => observer.observe(el));

// ------------------------------------------------------------
// Rotating bilingual questions (from the app's questionnaires)
// ------------------------------------------------------------

const questions = [
  {
    en: 'Type of Waste: What is the primary type of garbage dumped here?',
    bn: 'বর্জ্যের ধরন: এখানে প্রধানত কোন ধরনের আবর্জনা ফেলা হয়েছে?',
    options: ['Plastic waste', 'Organic/Food', 'Clean'],
    picked: 1,
  },
  {
    en: 'Dustbin Status: Is there a designated public dustbin available, and what is its condition?',
    bn: 'ডাস্টবিনের অবস্থা: এখানে কি নির্দিষ্ট সরকারি ডাস্টবিন আছে, এবং সেটির অবস্থা কেমন?',
    options: ['Not Available', 'Available & Clean', 'Available but Overflowing/Broken'],
    picked: 2,
  },
  {
    en: 'Sweeper Regularity: Do the municipal sweepers come to collect the garbage regularly?',
    bn: 'সাফাইকর্মীদের নিয়মিততা: পৌরসভার সাফাইকর্মীরা কি নিয়মিত আবর্জনা সংগ্রহ করতে আসেন?',
    options: ['Yes', 'No'],
    picked: 0,
  },
];

const qBody = document.querySelector('.q-body');
const qDots = document.querySelectorAll('.q-dots span');
let qIndex = 0;

function showQuestion(index) {
  const q = questions[index];
  qBody.querySelector('.q-en').textContent = q.en;
  qBody.querySelector('.q-bn').textContent = q.bn;
  const options = qBody.querySelector('.q-options');
  options.replaceChildren(
    ...q.options.map((text, i) => {
      const chip = document.createElement('span');
      chip.textContent = text;
      if (i === q.picked) chip.className = 'picked';
      return chip;
    }),
  );
  qDots.forEach((dot, i) => dot.classList.toggle('active', i === index));
}

if (!reduceMotion) {
  setInterval(() => {
    qBody.classList.add('swap');
    setTimeout(() => {
      qIndex = (qIndex + 1) % questions.length;
      showQuestion(qIndex);
      qBody.classList.remove('swap');
    }, 400);
  }, 4500);
}

// ------------------------------------------------------------
// Latest release: version and size text (download links never depend on it)
// ------------------------------------------------------------

async function loadLatestRelease() {
  try {
    const response = await fetch(RELEASES_API, {
      headers: { Accept: 'application/vnd.github+json' },
    });
    if (!response.ok) return;

    const release = await response.json();
    const version = String(release.tag_name || '').replace(/^v/i, '');
    const apk = (release.assets || []).find((asset) =>
      String(asset.name).toLowerCase().endsWith('.apk'),
    );

    if (version) {
      document.querySelectorAll('[data-version]').forEach((el) => {
        el.textContent = `Version ${version}`;
      });
    }

    if (apk) {
      document.querySelectorAll('[data-size]').forEach((el) => {
        el.textContent = ` · ${(apk.size / 1e6).toFixed(1)} MB`;
      });
    }
  } catch {
    // Offline or rate-limited: the page just shows "Latest version".
  }
}

loadLatestRelease();

// ------------------------------------------------------------
// QR code (rounded, in the app's green)
// ------------------------------------------------------------

function renderQr() {
  const container = document.getElementById('qr');

  if (typeof window.qrcode !== 'function') {
    const fallback = document.createElement('a');
    fallback.className = 'qr-fallback';
    fallback.href = LATEST_APK_URL;
    fallback.textContent = 'Download the app';
    container.append(fallback);
    return;
  }

  const qr = window.qrcode(0, 'M');
  qr.addData(LATEST_APK_URL);
  qr.make();

  const count = qr.getModuleCount();
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', `0 0 ${count} ${count}`);
  svg.setAttribute('shape-rendering', 'geometricPrecision');

  for (let row = 0; row < count; row++) {
    for (let col = 0; col < count; col++) {
      if (!qr.isDark(row, col)) continue;
      const cell = document.createElementNS(ns, 'rect');
      cell.setAttribute('x', col + 0.06);
      cell.setAttribute('y', row + 0.06);
      cell.setAttribute('width', 0.88);
      cell.setAttribute('height', 0.88);
      cell.setAttribute('rx', 0.3);
      cell.setAttribute('fill', '#183c28');
      svg.append(cell);
    }
  }

  container.prepend(svg);
}

renderQr();

// ------------------------------------------------------------
// Install guide tabs
// ------------------------------------------------------------

const guideTabs = document.querySelectorAll('.guide-tab');

function showGuide(tab) {
  guideTabs.forEach((t) => {
    const selected = t === tab;
    t.classList.toggle('active', selected);
    t.setAttribute('aria-selected', String(selected));
    const panel = document.getElementById(t.getAttribute('aria-controls'));
    panel.hidden = !selected;
    if (selected) {
      // Restart the staggered pop-in for the newly shown steps.
      panel.querySelectorAll('.guide-step').forEach((step, i) => {
        step.style.setProperty('--i', i);
        step.style.animation = 'none';
        void step.offsetWidth;
        step.style.animation = '';
      });
      panel.scrollLeft = 0;
    }
  });
}

guideTabs.forEach((tab) => tab.addEventListener('click', () => showGuide(tab)));
showGuide(document.querySelector('.guide-tab.active'));
