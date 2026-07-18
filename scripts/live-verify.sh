#!/bin/bash
# Opt-in provider smoke check. Never used by routine CI.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${OPENAI_API_KEY:?Set OPENAI_API_KEY to run live verification}"
: "${OPENROUTER_API_KEY:?Set OPENROUTER_API_KEY to run live verification}"
: "${TALKIE_LIVE_AUDIO:?Set TALKIE_LIVE_AUDIO to a short, non-sensitive m4a fixture}"

if [ ! -f "$TALKIE_LIVE_AUDIO" ]; then
  echo "error: TALKIE_LIVE_AUDIO does not exist" >&2
  exit 1
fi

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT

curl --fail --silent --show-error https://api.openai.com/v1/audio/transcriptions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F model=gpt-4o-mini-transcribe \
  -F response_format=json \
  -F "file=@$TALKIE_LIVE_AUDIO;type=audio/mp4" > "$VERIFY_DIR/openai.json"

python3 - "$TALKIE_LIVE_AUDIO" "$VERIFY_DIR/openrouter-request.json" <<'PY'
import base64, json, pathlib, sys
audio = base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode()
pathlib.Path(sys.argv[2]).write_text(json.dumps({
    "model": "mistralai/voxtral-mini-transcribe",
    "input_audio": {"data": audio, "format": "m4a"},
}))
PY

curl --fail --silent --show-error https://openrouter.ai/api/v1/audio/transcriptions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  --data-binary "@$VERIFY_DIR/openrouter-request.json" > "$VERIFY_DIR/openrouter.json"

python3 - "$VERIFY_DIR/openai.json" "$VERIFY_DIR/openrouter.json" <<'PY'
import json, pathlib, sys
for path in sys.argv[1:]:
    payload = json.loads(pathlib.Path(path).read_text())
    if not isinstance(payload.get("text"), str) or not payload["text"].strip():
        raise SystemExit(f"invalid or empty transcription response: {path}")
print("Live provider verification passed (OpenAI + OpenRouter).")
PY
