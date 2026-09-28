"""Reuse native evidence only when every app, resource and project file is identical."""
import argparse
import json
import os
import subprocess

REPO = "sidneytambin-maker/court-story-ios"
BRANCH = "codex/testflight-beta"
ALLOWED_REPAIR_FILES = {
    "Scripts/upload_testflight.py", "Scripts/test_testflight_upload.py",
    "Scripts/verify_testflight_signing.py", "Scripts/test_testflight_signing.py",
    "Scripts/verify_testflight_recovery.py", "Scripts/test_testflight_recovery.py",
    ".github/workflows/testflight-signing-recovery.yml",
}


def verify_evidence(evidence, changed_files):
    if evidence.get("headBranch") != BRANCH or evidence.get("workflowName") != "TestFlight beta validation":
        raise ValueError("Native evidence must come from this beta's full validation workflow")
    jobs = {job["name"]: job for job in evidence.get("jobs", [])}
    if any(jobs.get(name, {}).get("conclusion") != "success" for name in ("iphone-tests", "watch-tests", "release-privacy")):
        raise ValueError("All three native validation gates must have passed")
    unexpected = set(changed_files) - ALLOWED_REPAIR_FILES
    if unexpected:
        raise ValueError("App or build inputs changed; full native validation is required: " + ", ".join(sorted(unexpected)))


def main(run):
    if os.environ.get("GITHUB_REPOSITORY") != REPO or os.environ.get("GITHUB_REF") != "refs/heads/" + BRANCH:
        raise ValueError("Recovery is restricted to the original beta repository and branch")
    evidence = json.loads(subprocess.check_output(["gh", "run", "view", run, "--repo", REPO,
        "--json", "headSha,headBranch,workflowName,jobs"], text=True))
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if head != os.environ.get("GITHUB_SHA"):
        raise ValueError("Checked out source differs from the requested recovery revision")
    base = evidence["headSha"]
    subprocess.run(["git", "merge-base", "--is-ancestor", base, head], check=True)
    changed = subprocess.check_output(["git", "diff", "--name-only", "--no-renames", base, head], text=True).splitlines()
    verify_evidence(evidence, changed)
    print(json.dumps({"native_validated_sha": base, "recovery_sha": head,
        "app_source_resources_and_project_identical": True, "repair_files": changed}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--validated-run", required=True)
    main(parser.parse_args().validated_run)
