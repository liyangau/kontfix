#!/usr/bin/env python3
"""
Generates a starter expected-results JSON from a built tf.json.
All resources start with count_only: true — edit to add specific property assertions.
"""
import json
import sys
from pathlib import Path


def generate_snapshot(config_name: str, test_dir: Path) -> dict:
    actual_file = test_dir / f"{config_name}.tf.json"

    try:
        with open(actual_file) as f:
            actual = json.load(f)
    except FileNotFoundError:
        print(f"❌ {actual_file} not found. Run nix run .#build-{config_name} first.")
        sys.exit(1)

    snapshot = {}

    # Providers
    raw_providers = actual.get("provider", {})
    provider_list = []
    for provider_type, instances in raw_providers.items():
        if isinstance(instances, list):
            for inst in instances:
                provider_list.append({"provider": provider_type, "alias": inst.get("alias", "")})
        elif isinstance(instances, dict):
            provider_list.append({"provider": provider_type, "alias": instances.get("alias", "")})
    if provider_list:
        snapshot["providers"] = provider_list

    # Control planes
    resources = actual.get("resource", {})
    cp_resources = resources.get("konnect_gateway_control_plane", {})
    if cp_resources:
        snapshot["control_planes"] = [
            {"resource_name": name, "count_only": True}
            for name in cp_resources
        ]

    # Generic resources (everything that isn't a control plane)
    generic = []
    for resource_type, instances in resources.items():
        if resource_type == "konnect_gateway_control_plane":
            continue
        for resource_name in instances:
            generic.append({
                "resource_type": resource_type,
                "resource_name": resource_name,
                "count_only": True,
            })
    if generic:
        snapshot["resources"] = generic

    # Variables
    variables = actual.get("variable", {})
    if variables:
        snapshot["variables"] = [
            {"variable_name": name}
            for name in variables
        ]

    return snapshot


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Generate starter expected-results JSON")
    parser.add_argument("config_name", help="Name of the config (without .tf.json)")
    parser.add_argument("--test-dir", type=Path, default=Path.cwd())
    parser.add_argument("--write", action="store_true",
                        help="Write to expected-results/<config_name>.json")
    args = parser.parse_args()

    snapshot = generate_snapshot(args.config_name, args.test_dir)
    output = json.dumps(snapshot, indent=2)

    if args.write:
        out_file = args.test_dir / "expected-results" / f"{args.config_name}.json"
        out_file.parent.mkdir(parents=True, exist_ok=True)
        out_file.write_text(output + "\n")
        print(f"✅ Written to {out_file}")
        print("   Review and replace count_only: true entries with specific property assertions.")
    else:
        print(output)


if __name__ == "__main__":
    main()
