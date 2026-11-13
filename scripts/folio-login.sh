#!/usr/bin/env bash
# Run on the Ubuntu VM host. Prints a short-lived administrator sign-in URL.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
email=${1:-admin@example.com}
[[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+$ ]] || { echo 'Invalid administrator email.' >&2; exit 2; }
bash "$repo/scripts/vm.sh" ssh sudo python3 - "$email" <<'PY'
import json,sys,urllib.request
from pathlib import Path
email=sys.argv[1]
origin=Path('/etc/folio/origin').read_text().strip()
request=urllib.request.Request('http://127.0.0.1:18081/api/auth/sign-in/magic-link',
 data=json.dumps({'email':email,'callbackURL':'/'}).encode(),
 headers={'Content-Type':'application/json','Origin':origin},method='POST')
with urllib.request.urlopen(request,timeout=30) as response:
 if response.status!=200: raise SystemExit('Unable to start sign-in')
with urllib.request.urlopen('http://127.0.0.1:18081/api/local/mail',timeout=30) as response:
 mails=json.load(response)
match=next((m for m in mails if m['recipient']==email),None)
if match is None: raise SystemExit('No sign-in email found. Check the configured administrator allowlist.')
print('Open this private sign-in link within five minutes:')
print(match['url'])
PY
