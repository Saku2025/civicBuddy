# CivicBuddy

A Flutter app for field surveys of garbage hotspots. Surveyors sign in with
Google, record survey points (GPS location, timestamp and up to 5 photos per
point), answer a surveyor questionnaire for each point, and run a citizen
interview. Completed surveys are saved to Supabase and can be reviewed later
under Previous Surveys.

## Setup

1. Copy `.env.example` to `.env` and fill in your Supabase project URL and
   publishable key.
2. `flutter pub get`
3. `flutter run`

## Backend (Supabase)

- Auth: Google OAuth, redirect URL `io.supabase.flutter://login-callback/`
- Table `surveys` (unique on `user_id, survey_id`; survey answers stored in
  the `survey_data` JSON column)
- Private storage bucket `survey-photos`, with photos stored under
  `<user_id>/<survey_id>/point_<n>/photo_<n>.jpg`
