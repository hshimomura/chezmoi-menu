#!/usr/bin/env python3
"""Notarize with only the explicitly named App Store Connect variables; never source .env."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time

NAMES = {"ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_FILEPATH"}


def credentials(env_file):
    values = {name: os.environ[name] for name in NAMES if name in os.environ}
    if env_file.is_file():
        with env_file.open(encoding="utf-8") as stream:
            for line in stream:
                line = line.strip()
                if line.startswith("export "):
                    line = line[7:].lstrip()
                name, separator, raw = line.partition("=")
                name = name.strip()
                if not separator or name not in NAMES:
                    continue
                try:
                    parts = shlex.split(raw, comments=True, posix=True)
                except ValueError:
                    raise RuntimeError("App Store Connect 設定の引用符を確認してください。") from None
                if len(parts) > 1:
                    raise RuntimeError("App Store Connect 設定の値は引用符で囲んでください。")
                values[name] = parts[0] if parts else ""
    if not values.get("ASC_KEY_ID") or not values.get("ASC_KEY_FILEPATH"):
        raise RuntimeError("ASC_KEY_ID と ASC_KEY_FILEPATH を設定してください。")
    key_file = Path(os.path.expandvars(values["ASC_KEY_FILEPATH"])).expanduser()
    if not key_file.is_file():
        raise RuntimeError("ASC_KEY_FILEPATH が指す秘密鍵ファイルを確認してください。")
    values["ASC_KEY_FILEPATH"] = str(key_file)
    return values


def run_notary(arguments, values):
    auth = ["--key", values["ASC_KEY_FILEPATH"], "--key-id", values["ASC_KEY_ID"]]
    if values.get("ASC_ISSUER_ID"):
        auth += ["--issuer", values["ASC_ISSUER_ID"]]
    result = subprocess.run(["xcrun", "notarytool"] + arguments + auth + ["--output-format", "json"],
                            capture_output=True, text=True, timeout=180)
    if result.returncode:
        # Raw errors can contain authentication identifiers or file paths.
        raise RuntimeError("Apple 公証サービスへの操作に失敗しました。認証情報・チーム・ネットワークを確認してください。")
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--env-file", type=Path, default=Path.home() / ".env")
    parser.add_argument("--resume", help="Resume polling an existing submission; do not upload again")
    options = parser.parse_args()
    values = credentials(options.env_file)
    if not options.app.is_dir() or not options.archive.is_file():
        raise RuntimeError("公証するアプリと ZIP を確認してください。")
    print("Apple 公証サービスに接続しています…", flush=True)
    submission = options.resume
    if not submission:
        submission = run_notary(["submit", str(options.archive)], values)["id"]
    print("公証の提出 ID: " + submission, flush=True)
    report = options.archive.parent / "notarization.json"
    deadline = time.monotonic() + 1800
    previous = None
    while True:
        info = run_notary(["info", submission], values)
        with os.fdopen(os.open(report, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as stream:
            json.dump(info, stream, ensure_ascii=False, indent=2)
        status = info.get("status")
        if status != previous:
            print("Apple 公証: " + str(status), flush=True)
            previous = status
        if status == "Accepted":
            break
        if status != "In Progress":
            log = run_notary(["log", submission], values)
            log_path = options.archive.parent / "notarization-log.json"
            with os.fdopen(os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as stream:
                json.dump(log, stream, ensure_ascii=False, indent=2)
            raise RuntimeError("公証が承認されませんでした。dist/notarization-log.json を確認してください。")
        if time.monotonic() >= deadline:
            raise RuntimeError("公証は処理中です。提出 ID を指定して --resume で再開できます。")
        time.sleep(20)
    subprocess.run(["xcrun", "stapler", "staple", str(options.app)], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(options.app)], check=True)
    print("公証済みチケットを添付・検証しました。", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        # No traceback or command argv: keep credential identifiers out of logs.
        message = str(error) if isinstance(error, RuntimeError) else "公証処理に失敗しました。設定と実行環境を確認してください。"
        print(message, file=sys.stderr)
        sys.exit(1)
