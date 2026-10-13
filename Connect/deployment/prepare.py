"""Stage the reviewed Supabase sources; never deploy, overwrite or copy credentials.
Usage: python prepare.py PATH_TO_NEW_STAGING_DIRECTORY
Then use authenticated Supabase tooling with the generated supabase directory.
"""
from pathlib import Path
import hashlib
import json
import shutil
import sys

PROJECT_REF = "vfgxingpburwhrjbibvf"
source = Path(__file__).resolve().parents[1]
if len(sys.argv) != 2:
    raise SystemExit("Supply a new staging directory.")
target = Path(sys.argv[1]).resolve()
target.mkdir(parents=True, exist_ok=False)
staged = target / "supabase"
staged.mkdir()
shutil.copyfile(source / "deployment/config.toml", staged / "config.toml")
(staged / "migrations").mkdir()
for migration in sorted((source / "migrations").glob("*.sql")):
    shutil.copyfile(migration, staged / "migrations" / migration.name)
for name in ("delete-account", "dispatch-notifications"):
    directory = staged / "functions" / name
    directory.mkdir(parents=True)
    shutil.copyfile(source / "functions" / name / "index.ts", directory / "index.ts")
files = {str(path.relative_to(staged)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest()
         for path in sorted(staged.rglob("*")) if path.is_file()}
(target / "source-manifest.json").write_text(json.dumps({"project_ref": PROJECT_REF, "files": files}, indent=2), encoding="utf-8")
print("Prepared reviewed sources for project " + PROJECT_REF + ". No deployment or credentials included.")
