# CivicBuddy

A Flutter app for field surveys of garbage hotspots. Surveyors sign in with
Google, record survey points (GPS location, timestamp and up to 10 photos per
point), answer a surveyor questionnaire for each point, and run a citizen
interview. Completed surveys are saved to Supabase and can be reviewed later
under Previous Surveys.

## Setup

1. Copy `.env.example` to `.env` and fill in your Supabase project URL and
   publishable key.
2. `flutter pub get`
3. `flutter run`

## Releasing an update

Bump `version:` in `pubspec.yaml` (e.g. `1.7.1+7` to `1.7.2+8`) and push to
`main`. When the tests pass, GitHub Actions builds a signed APK and publishes
release `v<version>` with `garbage_detection_v<version>.apk`; installed apps
then show the "New Update Available" prompt on their next start. Pushes that
do not change the version only run the tests.

The release job needs these repository secrets (Settings > Secrets and
variables > Actions): `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.

## Backend (Supabase)

- Auth: Google OAuth, redirect URL `io.supabase.flutter://login-callback/`
- Table `surveys` (unique on `user_id, survey_id`; survey answers stored in
  the `survey_data` JSON column)
- Private storage bucket `survey-photos`, with photos stored under
  `<user_id>/<survey_id>/point_<n>/photo_<n>.jpg`
