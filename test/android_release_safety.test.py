import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "android" / "android" / "app"
GRADLE = (APP / "build.gradle.kts").read_text(encoding="utf-8")
FIREBASE = json.loads((APP / "google-services.json").read_text(encoding="utf-8"))

application_id = re.search(r'applicationId\s*=\s*"([^"]+)"', GRADLE)
namespace = re.search(r'namespace\s*=\s*"([^"]+)"', GRADLE)
assert application_id, "Android applicationId is missing."
assert namespace, "Android namespace is missing."
assert application_id.group(1) == "com.barq.app"
assert namespace.group(1) == application_id.group(1)

firebase_packages = {
    client["client_info"]["android_client_info"]["package_name"]
    for client in FIREBASE.get("client", [])
}
assert application_id.group(1) in firebase_packages, (
    "Firebase google-services.json does not contain the Android applicationId."
)

for path in ROOT.rglob("*"):
    if not path.is_file():
        continue
    if any(part in {".git", "node_modules", "build", ".dart_tool"} for part in path.parts):
        continue
    assert path.suffix.lower() not in {".jks", ".keystore", ".p12", ".pfx"}, (
        f"Signing credential file must not be committed: {path.relative_to(ROOT)}"
    )

print("Android applicationId, namespace, and Firebase package match; no signing keystore files are tracked.")
