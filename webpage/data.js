// CivicBuddy "Download data" page: sign in with Google (Supabase, same
// account as the app) and download your own surveys as a ZIP.
//
// The publishable key is public by design (it is also inside the app);
// Supabase's row-level security only returns the signed-in user's surveys
// and photos.

const SUPABASE_URL = 'https://cloibccvjophbgybklut.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_2MGV36gT3YY6aLlnFpBqQA_oe6ZE2fJ';
const PHOTO_BUCKET = 'survey-photos';
const UNKNOWN_AREA = 'Unknown Area';

const client = supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);

const $ = (id) => document.getElementById(id);

// ------------------------------------------------------------
// Theme toggle (same as the home page, remembered per browser)
// ------------------------------------------------------------

const root = document.documentElement;
try {
  const saved = localStorage.getItem('civicbuddy-theme');
  if (saved === 'light' || saved === 'dark') root.dataset.theme = saved;
} catch {
  // Storage unavailable; the toggle still works for this visit.
}

document.querySelector('.theme-toggle').addEventListener('click', () => {
  const isDark =
    root.dataset.theme === 'dark' ||
    (!root.dataset.theme && matchMedia('(prefers-color-scheme: dark)').matches);
  root.dataset.theme = isDark ? 'light' : 'dark';
  try {
    localStorage.setItem('civicbuddy-theme', root.dataset.theme);
  } catch {
    // Not remembered; fine.
  }
});

// ------------------------------------------------------------
// Page states
// ------------------------------------------------------------

function showState(name) {
  for (const state of ['loading', 'signed-out', 'signed-in']) {
    $(`state-${state}`).hidden = state !== name;
  }
}

function showMessage(text, isError = false) {
  const el = $('message');
  el.textContent = text;
  el.classList.toggle('error', isError);
  el.hidden = !text;
}

function setProgress(text, fraction) {
  $('progress').hidden = false;
  $('progress-text').textContent = text;
  $('progress-fill').style.width = `${Math.round(Math.min(1, fraction) * 100)}%`;
}

// ------------------------------------------------------------
// Survey data helpers (format written by the app's SurveyUploader)
// ------------------------------------------------------------

let surveys = [];

function pointsOf(survey) {
  const points = survey.survey_data?.points;
  return Array.isArray(points) ? points : [];
}

function citizensOf(survey) {
  const data = survey.survey_data || {};
  if (Array.isArray(data.citizens)) return data.citizens;
  // App versions up to 1.7.4 saved a single interview.
  return data.citizen ? [data.citizen] : [];
}

function photosOf(point) {
  return Array.isArray(point.photos)
    ? point.photos.filter((p) => p && p.storage_path)
    : [];
}

function photoCount(survey) {
  return pointsOf(survey).reduce((sum, p) => sum + photosOf(p).length, 0);
}

function safeName(text) {
  return String(text).replace(/[^A-Za-z0-9_-]/g, '_');
}

function plural(count, word) {
  return `${count} ${word}${count === 1 ? '' : 's'}`;
}

function dateText(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return '';
  const two = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())} ` +
    `${two(date.getHours())}:${two(date.getMinutes())}`;
}

function mapsLink(lat, lng) {
  return lat == null || lng == null
    ? ''
    : `https://www.google.com/maps?q=${lat},${lng}`;
}

// ------------------------------------------------------------
// CSV (UTF-8 with BOM so Excel shows Bengali correctly)
// ------------------------------------------------------------

function csvCell(value) {
  if (value == null) return '';
  const text = typeof value === 'object' ? JSON.stringify(value) : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function toCsv(headers, rows) {
  const lines = [headers, ...rows].map((row) => row.map(csvCell).join(','));
  return '﻿' + lines.join('\r\n') + '\r\n';
}

/** Question texts in first-seen order across all [answerMaps]. */
function questionColumns(answerMaps) {
  const seen = new Set();
  for (const answers of answerMaps) {
    if (answers && typeof answers === 'object') {
      Object.keys(answers).forEach((q) => seen.add(q));
    }
  }
  return [...seen];
}

// ------------------------------------------------------------
// Survey list
// ------------------------------------------------------------

function renderSurveys() {
  const list = $('survey-list');
  list.replaceChildren();

  for (const survey of surveys) {
    const points = pointsOf(survey).length;
    const interviews = citizensOf(survey).length;

    const item = document.createElement('li');
    const label = document.createElement('label');
    const box = document.createElement('input');
    box.type = 'checkbox';
    box.checked = true;
    box.value = survey.id;
    box.addEventListener('change', updateSelection);

    const text = document.createElement('div');
    const title = document.createElement('b');
    title.textContent = survey.survey_id;
    const meta = document.createElement('small');
    meta.textContent =
      `Submitted ${dateText(survey.ended_at || survey.created_at)} · ` +
      `${plural(points, 'point')} · ${plural(photoCount(survey), 'photo')} · ` +
      `${plural(interviews, 'interview')}`;
    text.append(title, meta);

    label.append(box, text);
    item.append(label);
    list.append(item);
  }

  const any = surveys.length > 0;
  $('survey-area').hidden = !any;
  $('no-surveys').hidden = any;
  $('survey-count').textContent = `Your surveys (${surveys.length})`;
  updateSelection();
}

function selectedSurveys() {
  const ids = new Set(
    [...document.querySelectorAll('#survey-list input:checked')].map((b) => b.value),
  );
  return surveys.filter((s) => ids.has(String(s.id)));
}

function updateSelection() {
  const selected = selectedSurveys();
  const photos = selected.reduce((sum, s) => sum + photoCount(s), 0);
  $('photo-count').textContent = `(${plural(photos, 'photo')})`;
  $('download-label').textContent =
    selected.length === 0
      ? 'Select surveys to download'
      : `Download ZIP (${plural(selected.length, 'survey')})`;
  $('download').disabled = selected.length === 0;
  $('toggle-all').textContent =
    selected.length === surveys.length ? 'Select none' : 'Select all';
}

$('toggle-all').addEventListener('click', () => {
  const selectAll = selectedSurveys().length !== surveys.length;
  document.querySelectorAll('#survey-list input').forEach((b) => {
    b.checked = selectAll;
  });
  updateSelection();
});

async function loadSurveys(user) {
  const { data, error } = await client
    .from('surveys')
    .select('id, survey_id, status, started_at, ended_at, created_at, survey_data')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });

  if (error) throw error;
  surveys = data || [];
  renderSurveys();
}

// ------------------------------------------------------------
// ZIP
// ------------------------------------------------------------

/** Runs [task] over [items], a few at a time. */
async function inParallel(items, limit, task) {
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++;
      await task(items[index], index);
    }
  });
  await Promise.all(workers);
}

async function buildZip(selected, includePhotos, userEmail) {
  const zip = new JSZip();
  const stamp = new Date().toISOString().slice(0, 10);
  const top = zip.folder(`CivicBuddy_surveys_${stamp}`);

  // Photos to fetch: storage path -> path inside the ZIP.
  const photoJobs = [];
  const photoFiles = new Map();
  for (const survey of selected) {
    const folder = `surveys/${safeName(survey.survey_id)}`;
    for (const point of pointsOf(survey)) {
      photosOf(point).forEach((photo, i) => {
        const name = `${folder}/point_${point.point_number}/photo_${photo.photo_number ?? i + 1}.jpg`;
        photoFiles.set(photo.storage_path, name);
        photoJobs.push({ path: photo.storage_path, name });
      });
    }
  }

  // 1. Photos.
  const missing = [];
  if (includePhotos && photoJobs.length > 0) {
    let done = 0;
    setProgress(`Downloading photos: 0 of ${photoJobs.length}`, 0);
    await inParallel(photoJobs, 4, async (job) => {
      const { data, error } = await client.storage.from(PHOTO_BUCKET).download(job.path);
      if (error || !data) {
        missing.push(job.name);
      } else {
        top.file(job.name, data, { binary: true, compression: 'STORE' });
      }
      done++;
      setProgress(
        `Downloading photos: ${done} of ${photoJobs.length}`,
        (done / photoJobs.length) * 0.9,
      );
    });
  }

  setProgress('Writing data files…', 0.92);

  // 2. surveys.csv
  top.file(
    'surveys.csv',
    toCsv(
      ['survey_id', 'status', 'started_at', 'ended_at', 'submitted_at',
        'duration_minutes', 'points', 'photos', 'citizen_interviews', 'surveyor_email'],
      selected.map((s) => {
        const start = new Date(s.started_at);
        const end = new Date(s.ended_at);
        const minutes = Number.isNaN(end - start) ? '' : Math.round((end - start) / 60000);
        return [s.survey_id, s.status, s.started_at, s.ended_at, s.created_at, minutes,
          pointsOf(s).length, photoCount(s), citizensOf(s).length, userEmail];
      }),
    ),
  );

  // 3. points.csv: fixed columns, then one column per surveyor question.
  const allPoints = selected.flatMap((s) => pointsOf(s).map((p) => ({ survey: s, point: p })));
  const pointQuestions = questionColumns(allPoints.map((x) => x.point.surveyor_answers));
  top.file(
    'points.csv',
    toCsv(
      ['survey_id', 'point_number', 'latitude', 'longitude', 'gps_accuracy_m', 'area',
        'captured_at', 'google_maps', 'photo_count', 'photo_files',
        ...pointQuestions.map((q, i) => `Q${i + 1}: ${q}`)],
      allPoints.map(({ survey, point }) => {
        const photos = photosOf(point);
        return [
          survey.survey_id, point.point_number, point.latitude, point.longitude,
          point.accuracy_m == null ? '' : Math.round(point.accuracy_m),
          point.area || UNKNOWN_AREA, point.captured_at,
          mapsLink(point.latitude, point.longitude), photos.length,
          photos.map((p) => photoFiles.get(p.storage_path)).join(' | '),
          ...pointQuestions.map((q) => point.surveyor_answers?.[q] ?? ''),
        ];
      }),
    ),
  );

  // 4. citizen_interviews.csv: fixed columns, then one per citizen question.
  const allCitizens = selected.flatMap((s) =>
    citizensOf(s).map((c, i) => ({ survey: s, citizen: c, number: c.interview_number ?? i + 1 })),
  );
  const citizenQuestions = questionColumns(allCitizens.map((x) => x.citizen.answers));
  top.file(
    'citizen_interviews.csv',
    toCsv(
      ['survey_id', 'interview_number', 'occupation', 'gender', 'age', 'latitude',
        'longitude', 'gps_accuracy_m', 'area', 'location_captured_at', 'google_maps',
        ...citizenQuestions.map((q, i) => `Q${i + 1}: ${q}`)],
      allCitizens.map(({ survey, citizen, number }) => [
        survey.survey_id, number, citizen.occupation, citizen.gender, citizen.age,
        citizen.latitude, citizen.longitude,
        citizen.accuracy_m == null ? '' : Math.round(citizen.accuracy_m),
        citizen.area || '', citizen.location_captured_at,
        mapsLink(citizen.latitude, citizen.longitude),
        ...citizenQuestions.map((q) => citizen.answers?.[q] ?? ''),
      ]),
    ),
  );

  // 5. Full JSON, per survey and all together.
  for (const survey of selected) {
    top.file(
      `surveys/${safeName(survey.survey_id)}/survey.json`,
      JSON.stringify(survey, null, 2),
    );
  }
  top.file('all_surveys.json', JSON.stringify(selected, null, 2));

  // 6. README
  top.file(
    'README.txt',
    [
      'CivicBuddy survey data',
      `Downloaded ${new Date().toISOString()} by ${userEmail}`,
      `${plural(selected.length, 'survey')}, ${plural(allPoints.length, 'point')}, ` +
        `${plural(allCitizens.length, 'citizen interview')}.`,
      '',
      'surveys.csv              One row per survey.',
      'points.csv               One row per survey point, with every surveyor question as a column.',
      'citizen_interviews.csv   One row per citizen interview, with every citizen question as a column.',
      'surveys/<survey ID>/     survey.json (full data) and photos (point_N/photo_N.jpg).',
      'all_surveys.json         All data exactly as stored in the database.',
      '',
      'Times are UTC (ISO 8601). gps_accuracy_m is the GPS accuracy in metres (blank for',
      'surveys from app versions before 1.8.15).',
      includePhotos ? '' : 'Photos were not included in this download.',
      missing.length ? `\nPhotos that could not be downloaded (${missing.length}):\n${missing.join('\n')}` : '',
    ].join('\n'),
  );

  setProgress('Creating ZIP file…', 0.95);
  const blob = await zip.generateAsync(
    { type: 'blob', compression: 'DEFLATE', compressionOptions: { level: 6 } },
    (meta) => setProgress('Creating ZIP file…', 0.95 + (meta.percent / 100) * 0.05),
  );

  return { blob, name: `CivicBuddy_surveys_${stamp}.zip`, missing };
}

function saveBlob(blob, name) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

$('download').addEventListener('click', async () => {
  const selected = selectedSurveys();
  if (selected.length === 0) return;

  const button = $('download');
  button.disabled = true;
  showMessage('');

  try {
    const { data } = await client.auth.getUser();
    const email = data.user?.email || '';
    const { blob, name, missing } = await buildZip(
      selected,
      $('include-photos').checked,
      email,
    );
    saveBlob(blob, name);
    setProgress('Done', 1);
    showMessage(
      missing.length
        ? `Downloaded ${name}. ${plural(missing.length, 'photo')} could not be downloaded; see README.txt in the ZIP.`
        : `Downloaded ${name} (${(blob.size / (1024 * 1024)).toFixed(1)} MB).`,
      missing.length > 0,
    );
  } catch (e) {
    $('progress').hidden = true;
    showMessage(`Download failed: ${e.message || e}`, true);
  } finally {
    updateSelection();
  }
});

// ------------------------------------------------------------
// Sign in / out
// ------------------------------------------------------------

$('sign-in').addEventListener('click', async () => {
  const { error } = await client.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: `${location.origin}${location.pathname}` },
  });
  if (error) showMessage(`Sign-in failed: ${error.message}`, true);
});

$('sign-out').addEventListener('click', async () => {
  await client.auth.signOut();
  surveys = [];
  showMessage('');
  showState('signed-out');
});

async function showSignedIn(user) {
  const meta = user.user_metadata || {};
  $('account-name').textContent = meta.full_name || meta.name || 'Signed in';
  $('account-email').textContent = user.email || '';
  const photo = meta.avatar_url || meta.picture;
  if (photo) {
    $('account-photo').src = photo;
    $('account-photo').hidden = false;
  }

  showState('signed-in');
  $('survey-area').hidden = true;
  $('no-surveys').hidden = true;
  showMessage('Loading your surveys…');

  try {
    await loadSurveys(user);
    showMessage('');
  } catch (e) {
    showMessage(`Could not load your surveys: ${e.message || e}`, true);
  }
}

let shownUserId = null;

async function refresh(session) {
  const user = session?.user;
  if (!user) {
    shownUserId = null;
    showState('signed-out');
    return;
  }
  if (user.id === shownUserId) return;
  shownUserId = user.id;
  await showSignedIn(user);
}

// Handles the return from Google sign-in too (tokens in the URL).
client.auth.onAuthStateChange((_event, session) => {
  // Run outside the auth callback, as Supabase recommends.
  setTimeout(() => refresh(session), 0);
});

client.auth.getSession().then(({ data }) => refresh(data.session));
