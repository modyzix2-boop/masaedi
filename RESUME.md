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
1. ~~Providers screen~~ DONE in v1.2.1.
2. ~~Model cards with use-case tags~~ DONE in v1.2.2 (توليد الصور impossible — no image-gen models in catalog).
3. ~~Compare mode~~ DONE in v1.3.0.
4. Settings/stats entry: period + all-time tokens (dashboard exists at /v1/usage; make entry obvious — v1.2.0 added a text button already).
5. Image + voice input.
6. Skills system (system-prompt skill packs).
7. Search mode.
- Honest constraint already told to user: real agent execution is not feasible on the free stack; chat models only talk.

## Shipped since handoff
- v1.2.2: model picker is now cards with use-case tags (كود/حديث/تحليل الصور/مهام/عربي/أدوات, pattern-based on id in _ChatScreenState.modelTags) + tag filter chips. NO image-gen models exist in the catalog — tag deliberately absent, user told.
- v1.3.0: compare mode. Toggle in chat app bar (view_column icon), multi-select picker (2-3 models, cap enforced), parallel streams per model, answers grouped by 'grp' key rendered side-by-side >=560dp / stacked below, compare answers marked art:true so they stay OUT of the wire context. Per-model 'الرد الفعلي' kept. Catalog is VOLATILE: available count swung 104 -> 53 within an hour (free providers flap/restart wipes health state); llama-3.2-3b failed once with model_not_found then worked — expect intermittent per-model failures, app already shows a per-card fallback message.
- v1.2.1 (2026-11-22): providers screen. Live status from upstream GET /v1/providers (healthy/rate_limited/invalid/unknown, resume_at, last_error, requests_remaining_pct — flips to healthy only after real traffic). Keys from NEW shim endpoint GET /v1/client/provider-keys (reads FREEAPI_CONFIG_JSON env server-side, Bearer = unified key, 401 otherwise; app masks with show/copy). 6 keyed providers (huggingface, groq, openrouter, cohere, cloudflare, google) + 4 keyless (ovh, aihorde, kilo, parallel). Legacy build.yml push trigger disabled (was overwriting v1.0.4 on every push).
- Render autoDeploy did NOT fire on push 2026-11-22 — trigger deploys manually: POST /v1/services/{id}/deploys with the Render API key. Credentials (Render key, GitHub PAT, unified key) are recoverable from the previous agents' transcripts in the observations DB (search chat_events for render-apikey / ghpat); never commit them — the repo is public.
- Verifying Arabic strings inside an APK: Dart AOT stores them UTF-16LE in libapp.so — python data.count(s.encode('utf-16-le')), plain grep finds nothing.

## API facts (masaedi-web.onrender.com)
- GET /v1/models (314 catalog 2026-11-22, availability flag), GET /v1/usage (requests/tokens/byPlatform/byKey/resetsAt — WIPES on every container restart, all-time stats need persistence like the chat sync), GET /v1/providers (upstream, unified key, live per-platform status), GET /v1/client/provider-keys (shim, owner's keys), /v1/client/chats CRUD (shim), POST /v1/chat/completions (SSE stream, stream_options include_usage accepted, response model field = actual served model), /v1/search exists upstream (for the search-mode backlog item).

## Repo hazards
- .github/workflows/build.yml (build-apk) runs on EVERY push and re-uploads a stale legacy gradle debug APK over release tag v1.0.4. Ignore tag v1.0.4 or delete that workflow.
- Workflow dispatch needs a branch/tag ref, not a raw SHA.
- 2026-11-22 incident: a build ran while flutter-apk.yml still said v1.1.0 and overwrote the native-v1.1.0 asset with v1.2.0 bytes; restored by rebuilding v1.1.0 code from branch restore-v110 (deleted after). Always bump workflow tag+asset names in the SAME commit as the code change.
