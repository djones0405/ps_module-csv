#!/usr/bin/env python3
"""
Download a full Hugging Face model repo to a local directory (including code files),
suitable for later mounting into an offline container.

Behavior:
- Attempts huggingface_hub.snapshot_download (recommended).
- If snapshot_download fails, by DEFAULT it will FALL BACK to an INSECURE git clone
  that disables SSL verification for git (GIT_SSL_NO_VERIFY + http.sslVerify=false).
  This is unsafe and should be used only with explicit authorization.

CLI:
  --repo / -r          Hugging Face repo id (default: nomic-ai/nomic-embed-text-v2-moe)
  --out  / -o          Output directory (default: ./nomic-embed-text-v2-moe)
  --token / -t         HF token for private repos (or use HF_TOKEN env var)
  --no-symlinks        Do not use symlinks when downloading (recommended)
  --force / -f         Remove existing output directory before downloading
  --no-insecure        DO NOT run the insecure git fallback if snapshot_download fails
"""

import argparse
import os
import sys
import shutil
import subprocess
from huggingface_hub import snapshot_download
from pathlib import Path

def check_required_files(out_dir: Path):
    missing = []
    if not (out_dir / "config.json").exists():
        missing.append("config.json")
    if not ((out_dir / "model.safetensors").exists() or (out_dir / "pytorch_model.bin").exists()):
        missing.append("model.safetensors or pytorch_model.bin")
    if not any((out_dir / f).exists() for f in ["tokenizer.json", "tokenizer_config.json", "sentencepiece.bpe.model", "vocab.txt"]):
        missing.append("tokenizer.json or tokenizer_config.json or sentencepiece.bpe.model or vocab.txt")
    if not (out_dir / "modules.json").exists():
        print("warning: modules.json not found (may be fine); if model uses dynamic modules this file should be present.")
    return missing

def print_summary(out_dir: Path, max_files=40):
    print(f"\nDownloaded files in {out_dir}:")
    count = 0
    for root, dirs, files in os.walk(out_dir):
        for name in files:
            path = Path(root) / name
            rel = path.relative_to(out_dir)
            try:
                size = path.stat().st_size
            except Exception:
                size = 0
            print(f" - {rel}  ({size:,} bytes)")
            count += 1
            if count >= max_files:
                print(f" ... (listing truncated after {max_files} files)")
                return

def parse_args():
    p = argparse.ArgumentParser(description="Download a HF model repo snapshot for offline use")
    p.add_argument("--repo", "-r", required=False, default="nomic-ai/nomic-embed-text-v2-moe",
                   help="Hugging Face repo id, e.g. 'nomic-ai/nomic-embed-text-v2-moe'")
    p.add_argument("--out", "-o", required=False, default="./nomic-embed-text-v2-moe",
                   help="Output directory to write the model files")
    p.add_argument("--token", "-t", required=False, default=None,
                   help="Hugging Face token if required (private repo). If not set, will use HF_TOKEN env var if present.")
    p.add_argument("--no-symlinks", dest="no_symlinks", action="store_true",
                   help="Do not use symlinks when downloading (recommended for copying to offline hosts).")
    p.add_argument("--force", "-f", dest="force", action="store_true",
                   help="Remove existing output directory before downloading.")
    p.add_argument("--no-insecure", dest="no_insecure", action="store_true",
                   help="Do NOT run the INSECURE git fallback if snapshot_download fails.")
    return p.parse_args()

def run_snapshot_download(repo_id: str, out_dir: Path, token: str, use_symlinks: bool):
    print(f"Attempting snapshot_download for '{repo_id}' into {out_dir} ...")
    out_path = snapshot_download(
        repo_id=repo_id,
        local_dir=str(out_dir),
        local_dir_use_symlinks=use_symlinks,
        allow_patterns=None,
        use_auth_token=token,
    )
    return out_path

def run_insecure_git_clone(repo_id: str, out_dir: Path):
    """
    Insecure fallback: run git clone with SSL verification disabled.
    WARNING: This is insecure and allows MITM. Use only with explicit authorization.
    """
    repo_url = f"https://huggingface.co/{repo_id}"
    env = os.environ.copy()
    env["GIT_SSL_NO_VERIFY"] = "true"
    out_dir_parent = out_dir.parent
    out_dir_parent.mkdir(parents=True, exist_ok=True)
    cmd = ["git", "-c", "http.sslVerify=false", "clone", repo_url, str(out_dir)]
    print("\n*** INSECURE FALLBACK: about to run git clone with SSL verification DISABLED ***", file=sys.stderr)
    print("If you do not have explicit authorization to bypass TLS verification, abort now.", file=sys.stderr)
    print("Command:", " ".join(cmd), file=sys.stderr)
    try:
        subprocess.run(cmd, check=True, env=env)
    except subprocess.CalledProcessError as e:
        print("ERROR: insecure git clone failed:", e, file=sys.stderr)
        return False

    # Try git-lfs pull if available
    try:
        subprocess.run(["git", "lfs", "install"], check=False, cwd=str(out_dir))
        print("Attempting 'git lfs pull' to fetch LFS objects (if any)...")
        subprocess.run(["git", "lfs", "pull"], check=False, cwd=str(out_dir))
    except FileNotFoundError:
        print("git-lfs not installed or not found; if large files are missing, install git-lfs and run 'git lfs pull' in the repo.", file=sys.stderr)
    return True

def main():
    args = parse_args()
    repo_id = args.repo
    out_dir = Path(args.out).expanduser().resolve()
    token = args.token or os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")
    use_symlinks = not args.no_symlinks

    if out_dir.exists():
        if args.force:
            print(f"Removing existing directory {out_dir} (because --force set)")
            shutil.rmtree(out_dir)
        else:
            print(f"Output directory {out_dir} already exists. Use --force to replace it or choose another path.")

    # Try recommended snapshot_download first
    try:
        out_path = run_snapshot_download(repo_id, out_dir, token, use_symlinks)
        print("Download finished. Snapshot saved to:", out_path)
    except Exception as e:
        print("WARNING: snapshot_download failed:", e, file=sys.stderr)
        if args.no_insecure:
            print("\nNo insecure fallback requested (--no-insecure set). Aborting.", file=sys.stderr)
            sys.exit(2)
        # Default behavior: run the insecure fallback automatically
        print("\nDefault behavior is to attempt an INSECURE git clone as a fallback (DISABLES TLS verification).", file=sys.stderr)
        print("Proceeding with insecure fallback. If you do not want this, re-run with --no-insecure.", file=sys.stderr)
        success = run_insecure_git_clone(repo_id, out_dir)
        if not success:
            print("ERROR: insecure git clone also failed. Aborting.", file=sys.stderr)
            sys.exit(3)
        print("Insecure git clone completed. Please verify files and run 'git lfs pull' if needed.")

    # Basic checks
    missing = check_required_files(out_dir)
    if missing:
        print("\nERROR: The following required items appear to be missing from the downloaded model:")
        for m in missing:
            print(" -", m)
        print("\nIf files are missing (weights/LFS objects), ensure git-lfs fetched them or re-run snapshot_download on a machine with working TLS.", file=sys.stderr)
    else:
        print("\nAll basic required files found: config + weights + tokenizer (or equivalents).")

    print_summary(out_dir)
    print("\nNext steps (host):")
    print(f" - Copy or rsync {out_dir} to your Docker host path where you'll mount it into the container.")
    print(" - Ensure file permissions are readable by the container process, e.g.:")
    print(f"     sudo chmod -R a+rX {out_dir}")
    print(" - In your docker-compose, set MODEL_NAME to the container path where you will mount this directory.")
    print(" - Set HF_HUB_OFFLINE=1 and TRANSFORMERS_OFFLINE=1 inside the container environment to enforce offline mode.")
    return 0

if __name__ == "__main__":
    sys.exit(main())