# Masaedi — successor agent resume state (2026-11-22)

## Repos
- App: github.com/modyzix2-boop/masaedi — native Flutter app in flutter_app/, this file, production chat-sync blobs in sync/ (do NOT delete sync/, it's live user data).
- Backend: github.com/modyzix2-boop/freellm-router — shim.js (chat persistence + extra endpoints), ui/app.html (web client), Dockerfile.

## Production
- Live service: masaedi-web.onrender.com (Render srv-dc0o9tec6qcc73evceh0). Old service freellm-router.onrender.com (srv-dc0kciec6qcc73eks6pg) still exists; masaedi-web is production.
- User's unified API key doubles as app login + Bearer for all endpoints. Never print secrets in reports.
- Render free tier restarts both services irregularly (35-60 min). Chat persistence survives via shim -> GitHub sync/<sha256(key)>.json. Cold starts up to 60-90s.

## Build recipe (APK)
1. Edit flutter_app/lib/main.dart; bump version in flutter_app/pubspec.yaml (x.y.z+build).
2. .github/workflows/flutter-apk.yml: update tag + asset names (native-vX.Y.Z / masaedi-native-vX.Y.Z.apk). flutter create . preserves lib/+pubspec; sed adds label+INTERNET permission; flutter pub add flutter_markdown_plus; release build split-per-abi. ~4-6 min.
3. git pull --rebase ALWAYS before push (production sync commits land on main constantly).
4. Dispatch workflow_dispatch, poll /actions/runs, then verify: download the TAG-PINNED asset URL (never /releases/latest/download — serves stale CDN bytes) and check zip contents (libflutter.so, libapp.so arm64, Cairo fonts).
5. Release URL pattern: https://github.com/modyzix2-boop/masaedi/releases/download/native-vX.Y.Z/masaedi-native-vX.Y.Z.apk
- Cairo fonts live in flutter_app/assets/fonts/ (bundled).
- User device: Samsung Galaxy Tab A9+ (arm64 APK).

## Identity fix (v1.2.0, the trust layer — do not regress)
- FreeLLMAPI catalog labels are marketing aliases: claude-opus-4-5 actually served nvidia/nemotron-3.5-lightning; claude-sonnet-4-5 -> nemotron-3-nano-omni-30b-reasoning; claude-haiku-4-5 -> @cf/meta/llama-3.3-70b-fp8-fast. Full probe data (114 models): /tmp/identity-probe.json in the old agent sandbox (gone) — re-probe if needed: GET /v1/chat/completions per model, read the response SSE chunk `model` field. That field is the ONLY ground truth. /v1/usage byPlatform is provider ground truth.
- main.dart: hiddenIds (aliases + 404 phantoms, hidden from picker), verifiedIds (probe-confirmed, get موثّق badge), every reply stores msg['served'] from stream chunk model field, bubble prints 'الرد الفعلي: <actual>'.
- Never use "ask the model its name" as verification — self-identification is unreliable.

## Standing user rules
- No emojis as icons anywhere (SVG/Material icons only). Honest caveats always. Version-pinned release links only. Egyptian Arabic UI. User: Mode/محمد, no computer, no budget, Galaxy Tab A9+, WhatsApp.

## Remaining v1.2 backlog (priority order from parent)
1. Providers screen: 10 providers, live status, masked provider keys with show/copy (parent approved masked display of user's own Gmail-created keys; source: FREEAPI_CONFIG_JSON env on the old Render service, 6 provider keys known).
2. Model cards with use-case tags: كود/حديث/صور/مهام/توليد صور.
3. Compare mode: one message -> many models answer side by side.
4. Settings/stats entry: period + all-time tokens (dashboard exists at /v1/usage; make entry obvious — v1.2.0 added a text button already).
5. Image + voice input.
6. Skills system (system-prompt skill packs).
7. Search mode.
- Honest constraint already told to user: real agent execution is not feasible on the free stack; chat models only talk.

## API facts (masaedi-web.onrender.com)
- GET /v1/models (328 catalog, availability flag), GET /v1/usage (requests/tokens/byPlatform/byKey/resetsAt), /v1/client/chats CRUD (shim), POST /v1/chat/completions (SSE stream, stream_options include_usage accepted, response model field = actual served model).
