#!/usr/bin/env python3
import argparse
import os
import tempfile
from pathlib import Path

import yaml


def fail(message):
    raise SystemExit(f"bazarr-configure: {message}")


def read_required_file(path, label):
    if not path:
        fail(f"{label} credential file is not configured")
    value = Path(path).read_text(encoding="utf-8").rstrip("\n")
    if not value:
        fail(f"{label} credential file is empty")
    return value


def load_yaml_config(path):
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle)
    if loaded is None:
        return {}
    if not isinstance(loaded, dict):
        fail(f"{path} must contain a YAML object")
    return loaded


def merge_owned_values(base, owned):
    for key, value in owned.items():
        if isinstance(value, dict):
            child = base.setdefault(key, {})
            if not isinstance(child, dict):
                fail(f"cannot merge object into non-object key {key}")
            merge_owned_values(child, value)
        else:
            base[key] = value


def ensure_provider(config, provider):
    general = config.setdefault("general", {})
    providers = general.setdefault("enabled_providers", [])
    if providers is None:
        providers = []
        general["enabled_providers"] = providers
    if not isinstance(providers, list):
        fail("general.enabled_providers must be a list")
    if provider not in providers:
        providers.append(provider)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--policy", required=True)
    args = parser.parse_args()

    state_dir = Path(args.state_dir)
    config_dir = state_dir / "config"
    config_dir.mkdir(parents=True, exist_ok=True)
    config_path = config_dir / "config.yaml"

    policy = load_yaml_config(Path(args.policy))
    owned_values = policy.get("ownedValues", {})
    required_providers = policy.get("requiredProviders", [])

    if not isinstance(owned_values, dict):
        fail("policy ownedValues must be an object")
    if not isinstance(required_providers, list):
        fail("policy requiredProviders must be a list")

    config = load_yaml_config(config_path)
    merge_owned_values(config, owned_values)

    config.setdefault("sonarr", {})["apikey"] = read_required_file(
        os.environ.get("BAZARR_SONARR_API_KEY_FILE"),
        "Sonarr API key",
    )
    config.setdefault("radarr", {})["apikey"] = read_required_file(
        os.environ.get("BAZARR_RADARR_API_KEY_FILE"),
        "Radarr API key",
    )

    if os.environ.get("BAZARR_REQUIRE_OPENSUBTITLES") == "1":
        config.setdefault("opensubtitlescom", {})["username"] = read_required_file(
            os.environ.get("BAZARR_OPENSUBTITLES_USERNAME_FILE"),
            "OpenSubtitlesCom username",
        )
        config.setdefault("opensubtitlescom", {})["password"] = read_required_file(
            os.environ.get("BAZARR_OPENSUBTITLES_PASSWORD_FILE"),
            "OpenSubtitlesCom password",
        )
        ensure_provider(config, "opensubtitlescom")

    for provider in required_providers:
        ensure_provider(config, provider)

    fd, tmp_name = tempfile.mkstemp(prefix=".config.", suffix=".yaml", dir=config_dir)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        yaml.safe_dump(config, handle, default_flow_style=False, sort_keys=True)
    os.replace(tmp_name, config_path)


if __name__ == "__main__":
    main()
