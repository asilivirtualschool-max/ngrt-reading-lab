#!/bin/bash
# Deploys NGRT Reading Lab to Firebase Hosting with a shared Firestore database.
# Run from Google Cloud Shell:  bash deploy.sh
set -e
P=ngrt-reading-lab
cd "$(dirname "$0")"
gcloud config set project "$P" >/dev/null
echo "== Enabling APIs"
gcloud services enable firestore.googleapis.com firebasehosting.googleapis.com
echo "== Firestore database"
if ! gcloud firestore databases describe --database="(default)" >/dev/null 2>&1; then
  gcloud firestore databases create --database="(default)" --location=me-central1 --type=firestore-native
fi
echo "== Web app"
if ! firebase apps:list WEB --project "$P" | grep -q "NGRT Reading Lab"; then
  firebase apps:create WEB "NGRT Reading Lab" --project "$P"
fi
firebase apps:sdkconfig WEB --project "$P" --json > /tmp/sdk.json
mkdir -p public
node -e '
const fs=require("fs"); const j=JSON.parse(fs.readFileSync("/tmp/sdk.json","utf8")); const r=j.result||j;
let c=r.sdkConfig; if(!c){const m=(r.fileContents||"").match(/\{[\s\S]*\}/); c=JSON.parse(m[0]);}
const cfg={apiKey:c.apiKey,authDomain:c.authDomain,projectId:c.projectId,storageBucket:c.storageBucket,messagingSenderId:c.messagingSenderId,appId:c.appId};
let h=fs.readFileSync("index.html","utf8");
h=h.replace(/const FIREBASE_CONFIG = (null|\{[^\n]*?\});/, "const FIREBASE_CONFIG = "+JSON.stringify(cfg)+";");
fs.writeFileSync("public/index.html",h); fs.writeFileSync("public/config.json",JSON.stringify(cfg));
console.log("CONFIG "+JSON.stringify(cfg));'
cat > firebase.json <<'EOF'
{ "hosting": { "public": "public", "ignore": ["**/.*"], "headers": [{ "source": "**/*.html", "headers": [{ "key": "Cache-Control", "value": "no-cache" }] }] },
  "firestore": { "rules": "firestore.rules" } }
EOF
cat > firestore.rules <<'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Open access for the NGRT Reading Lab collections only (no sign-in in the app).
    match /{col}/{doc} {
      allow read, write: if col.matches('ngrt_.*');
    }
  }
}
EOF
echo "== Deploying"
firebase deploy --only hosting,firestore:rules --project "$P" --non-interactive
echo "== DONE: https://$P.web.app"
