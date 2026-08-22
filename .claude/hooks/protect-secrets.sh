#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(data.get("tool_input", {}).get("file_path", ""))' <<< "$INPUT")

if [[ "$FILE_PATH" == *".env"* ]]; then
  echo "차단: .env 파일은 Claude가 직접 수정할 수 없습니다." >&2
  exit 2
fi
exit 0
