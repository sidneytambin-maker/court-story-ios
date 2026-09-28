"""Permit packaging-only reruns only when native-tested app sources are unchanged."""
import argparse
import json
import subprocess

PACKAGING_ONLY = {
    ".github/workflows/ios-free-build.yml", ".github/workflows/app-icon-validation.yml",
    "Scripts/verify_app_icons.py", "Scripts/test_app_icons.py",
    "Scripts/verify_native_test_evidence.py", "Scripts/test_native_test_evidence.py",
    "Branding/AppIcon.md",
}
REQUIRED = {"Run unit tests", "Run iPhone accessibility UI tests", "Run native Watch accessibility UI tests"}


def validate(run, changed_files, stage):
    if run.get("status") != "completed" or run.get("workflowName") != "iOS free development build":
        raise ValueError("Native evidence must be a completed full build workflow")
    if set(changed_files) - PACKAGING_ONLY:
        raise ValueError("App, artwork, test or build-source changes require fresh native tests")
    jobs = [job for job in run.get("jobs", []) if job.get("name") == "Build unsigned iOS IPA"]
    if len(jobs) != 1:
        raise ValueError("Expected one unambiguous native test job")
    required = REQUIRED | ({"Compile Watch complication"} if stage == "widgets" else set())
    for name in required:
        steps = [step for step in jobs[0].get("steps", []) if step.get("name") == name]
        if len(steps) != 1 or steps[0].get("conclusion") != "success":
            raise ValueError("Native evidence is missing or failed: " + name)
    return {"native_tests_reused": True, "tested_source": run["headSha"], "native_test_steps": sorted(required)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", required=True, type=int)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--stage", required=True, choices=("core", "health", "widgets"))
    args = parser.parse_args()
    run = json.loads(subprocess.check_output(["gh", "run", "view", str(args.run), "--repo", args.repo,
                    "--json", "status,workflowName,headSha,jobs"]))
    sha = run["headSha"]
    subprocess.run(["git", "merge-base", "--is-ancestor", sha, "HEAD"], check=True)
    changed = subprocess.check_output(["git", "diff", "--name-only", sha, "HEAD"]).decode().splitlines()
    report = validate(run, changed, args.stage)
    report.update({"run": args.run, "packaging_changes": changed})
    print(json.dumps(report, indent=2))
