#!/usr/bin/env python3
"""
Partial JSON validator with detailed diagnostics.
Validates that expected config is a subset of actual config.
"""

import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum

try:
    from deepdiff import DeepDiff
    from colorama import Fore, Style, init as colorama_init
    ENHANCED_MODE = True
    colorama_init(autoreset=True)
except ImportError:
    ENHANCED_MODE = False


class ValidationStatus(Enum):
    PASSED = "✅"
    FAILED = "❌"


def colorize(text: str, color: str) -> str:
    """Colorize text if enhanced mode is available"""
    if not ENHANCED_MODE:
        return text
    
    colors = {
        'green': Fore.GREEN,
        'red': Fore.RED,
        'yellow': Fore.YELLOW,
        'blue': Fore.BLUE,
        'cyan': Fore.CYAN,
    }
    return f"{colors.get(color, '')}{text}{Style.RESET_ALL}"


@dataclass
class ValidationResult:
    """Result of a single validation check"""
    found: bool
    message: str
    detail: Optional[str] = None
    expected: Optional[Any] = None
    actual: Optional[Any] = None


@dataclass
class SectionValidation:
    """Results for a validation section (providers, resources, etc.)"""
    all_found: bool
    results: List[ValidationResult]
    summary: str


def is_subset(expected: Any, actual: Any) -> bool:
    """Check if expected is a subset of actual (recursive)"""
    if expected is None or actual is None:
        return expected == actual
    
    if isinstance(expected, dict) and isinstance(actual, dict):
        return all(
            key in actual and is_subset(expected[key], actual[key])
            for key in expected
        )
    
    if isinstance(expected, list) and isinstance(actual, list):
        # For lists: each expected item must match at least one actual item
        return all(
            any(is_subset(exp_item, act_item) for act_item in actual)
            for exp_item in expected
        )
    
    return expected == actual


def get_mismatch_reason(expected: Any, actual: Any,
                        path: str = "") -> Optional[str]:
    """Return human-readable reason for mismatch (None if matches)"""
    if expected == actual:
        return None

    # Use DeepDiff for enhanced mode
    if ENHANCED_MODE:
        diff = DeepDiff(expected, actual, ignore_order=False, view='tree')
        if not diff:
            return None

        reasons = []
        if 'dictionary_item_added' in diff:
            added = [str(item) for item in diff['dictionary_item_added']]
            reasons.append(f"extra keys in actual: {', '.join(added)}")

        if 'dictionary_item_removed' in diff:
            removed = [str(item)
                       for item in diff['dictionary_item_removed']]
            reasons.append(f"missing keys: {', '.join(removed)}")

        if 'values_changed' in diff:
            for item in diff['values_changed']:
                old_val = item.t1
                new_val = item.t2
                reasons.append(
                    f"at {item.path()}: expected {old_val!r}, got {new_val!r}"
                )

        if 'type_changes' in diff:
            for item in diff['type_changes']:
                reasons.append(f"at {item.path()}: type mismatch")

        return "; ".join(reasons) if reasons else "structures differ"

    # Fallback to basic comparison
    if isinstance(expected, dict) and isinstance(actual, dict):
        mismatched = []
        for key in expected:
            key_path = f"{path}.{key}" if path else key
            if key not in actual:
                mismatched.append(f"'{key_path}' missing")
            elif (reason := get_mismatch_reason(expected[key],
                                                actual[key], key_path)):
                mismatched.append(reason)

        return "; ".join(mismatched) if mismatched else None

    if isinstance(expected, list) and isinstance(actual, list):
        return (f"list content mismatch at {path}" if path
                else "list content mismatch")

    exp_str = (json.dumps(expected) if not isinstance(expected, str)
               else f"'{expected}'")
    act_str = (json.dumps(actual) if not isinstance(actual, str)
               else f"'{actual}'")
    location = f" at {path}" if path else ""
    return f"expected {exp_str}, got {act_str}{location}"


def format_json_compact(obj: Any, indent: int = 2) -> str:
    """Format JSON in a compact, readable way"""
    return json.dumps(obj, indent=indent, sort_keys=True)


def validate_variables(expected_vars: List[Dict],
                       actual_config: Dict) -> SectionValidation:
    """Validate variables section"""
    actual_vars = actual_config.get("variable", {})
    results = []
    
    for expected in expected_vars:
        # Validate required fields in expected config
        if "variable_name" not in expected:
            results.append(ValidationResult(
                found=False,
                message=("❌ Invalid test configuration: "
                        "missing 'variable_name'"),
                detail=(f"Expected variable config: "
                       f"{format_json_compact(expected)}")
            ))
            continue
        
        var_name = expected["variable_name"]
        count_only = expected.get("count_only", False)
        should_not_exist = expected.get("should_not_exist", False)
        actual_var = actual_vars.get(var_name)
        
        expected_props = {
            k: v for k, v in expected.items()
            if k not in ["variable_name", "count_only", "should_not_exist"]
        }
        
        if should_not_exist:
            found = actual_var is None
            message = (
                f"✅ Variable {var_name} does not exist as expected"
                if found else
                f"❌ Variable {var_name} exists but should not"
            )
            detail = (None if found
                      else f"Variable found: {format_json_compact(actual_var)}")
        elif actual_var is None:
            found = False
            message = f"❌ Variable {var_name} missing (variable not found)"
            detail = "Variable not found in actual config"
        elif count_only:
            found = True
            message = f"✅ Variable {var_name} exists"
            detail = None
        else:
            found = is_subset(expected_props, actual_var)
            if found:
                message = (f"✅ Variable {var_name} found with matching "
                           "properties")
                detail = None
            else:
                message = (f"❌ Variable {var_name} missing "
                           "(properties don't match)")
                reason = get_mismatch_reason(expected_props, actual_var)
                detail = (
                    f"Expected:\n{format_json_compact(expected_props)}\n"
                    f"Actual:\n{format_json_compact(actual_var)}\n"
                    f"Reason: {reason}"
                )

        results.append(ValidationResult(
            found=found,
            message=message,
            detail=detail,
            expected=(expected_props if not should_not_exist
                      and not count_only else None),
            actual=actual_var
        ))
    
    found_count = sum(1 for r in results if r.found)
    return SectionValidation(
        all_found=all(r.found for r in results),
        results=results,
        summary=f"{found_count}/{len(results)} expected variables found"
    )


def validate_providers(expected_providers: List[Dict],
                       actual_config: Dict) -> SectionValidation:
    """Validate providers section with alias-aware matching"""
    supported_providers = ["konnect", "aws", "vault"]
    actual_providers = actual_config.get("provider", {})
    results = []
    
    for expected in expected_providers:
        # Validate required fields in expected config
        if "provider" not in expected:
            results.append(ValidationResult(
                found=False,
                message=("❌ Invalid test configuration: "
                        "missing 'provider'"),
                detail=(f"Expected provider config: "
                       f"{format_json_compact(expected)}")
            ))
            continue
        
        provider_name = expected["provider"]
        
        if provider_name not in supported_providers:
            results.append(ValidationResult(
                found=False,
                message=(f"❌ Unsupported provider '{provider_name}'. "
                         f"Supported: {', '.join(supported_providers)}"),
                detail=None
            ))
            continue
        
        actual_provider_config = actual_providers.get(provider_name)
        
        if actual_provider_config is None:
            results.append(ValidationResult(
                found=False,
                message=f"❌ Provider '{provider_name}' not found",
                detail=(f"No provider block for '{provider_name}' "
                        "in actual config")
            ))
            continue

        # Normalize to list
        provider_configs = (
            actual_provider_config
            if isinstance(actual_provider_config, list)
            else [actual_provider_config]
        )
        
        expected_props = {k: v for k, v in expected.items() if k != "provider"}
        expected_alias = expected_props.get("alias")
        
        # Prefer matching by alias if expected has one
        if expected_alias:
            candidates = [p for p in provider_configs
                          if p.get("alias") == expected_alias]
        else:
            candidates = provider_configs

        if not candidates:
            alias_msg = (f" (alias: {expected_alias})" if expected_alias
                         else "")
            results.append(ValidationResult(
                found=False,
                message=(f"❌ Provider '{provider_name}' with expected "
                         "configuration missing"),
                detail=(f"No matching provider instance found{alias_msg}"
                        if expected_alias else "No provider instances found")
            ))
            continue
        
        best_match = candidates[0]
        found = is_subset(expected_props, best_match)
        
        if found:
            results.append(ValidationResult(
                found=True,
                message=(f"✅ Provider '{provider_name}' with expected "
                        "configuration found"),
                detail=None
            ))
        else:
            reason = get_mismatch_reason(expected_props, best_match)
            results.append(ValidationResult(
                found=False,
                message=(f"❌ Provider '{provider_name}' with expected "
                        "configuration missing"),
                detail=(
                    f"Expected:\n{format_json_compact(expected_props)}\n"
                    f"Actual:\n{format_json_compact(best_match)}\n"
                    f"Reason: {reason}"
                )
            ))
    
    found_count = sum(1 for r in results if r.found)
    return SectionValidation(
        all_found=all(r.found for r in results),
        results=results,
        summary=f"{found_count}/{len(results)} expected providers found"
    )


def validate_control_planes(expected_cps: List[Dict],
                            actual_config: Dict) -> SectionValidation:
    """Validate control planes section"""
    actual_cps = actual_config.get("resource", {}).get(
        "konnect_gateway_control_plane", {}
    )
    results = []
    
    for expected in expected_cps:
        # Validate required fields in expected config
        if "resource_name" not in expected:
            results.append(ValidationResult(
                found=False,
                message=("❌ Invalid test configuration: "
                        "missing 'resource_name'"),
                detail=(f"Expected control plane config: "
                       f"{format_json_compact(expected)}")
            ))
            continue
        
        resource_name = expected["resource_name"]
        count_only = expected.get("count_only", False)
        actual_cp = actual_cps.get(resource_name)
        
        expected_props = {
            k: v for k, v in expected.items()
            if k not in ["resource_name", "resource_type", "count_only"]
        }
        
        if actual_cp is None:
            found = False
            message = (f"❌ Control plane {resource_name} missing "
                      "(resource not found)")
            detail = (f"Control plane resource '{resource_name}' "
                     "not found in actual config")
        elif count_only:
            found = True
            message = f"✅ Control plane {resource_name} exists"
            detail = None
        else:
            found = is_subset(expected_props, actual_cp)
            if found:
                message = (f"✅ Control plane {resource_name} found with "
                          "matching properties")
                detail = None
            else:
                message = (f"❌ Control plane {resource_name} missing "
                          "(properties don't match)")
                reason = get_mismatch_reason(expected_props, actual_cp)
                detail = (
                    f"Expected:\n{format_json_compact(expected_props)}\n"
                    f"Actual:\n{format_json_compact(actual_cp)}\n"
                    f"Reason: {reason}"
                )
        
        results.append(ValidationResult(
            found=found,
            message=message,
            detail=detail
        ))
    
    found_count = sum(1 for r in results if r.found)
    return SectionValidation(
        all_found=all(r.found for r in results),
        results=results,
        summary=f"{found_count}/{len(results)} expected control planes found"
    )


def validate_generic_resources(expected_resources: List[Dict],
                               actual_config: Dict) -> SectionValidation:
    """Validate generic resources section"""
    results = []
    
    for expected in expected_resources:
        # Validate required fields in expected config
        if "resource_type" not in expected:
            results.append(ValidationResult(
                found=False,
                message=("❌ Invalid test configuration: "
                        "missing 'resource_type'"),
                detail=(f"Expected resource config: "
                       f"{format_json_compact(expected)}")
            ))
            continue
        
        if "resource_name" not in expected:
            results.append(ValidationResult(
                found=False,
                message=("❌ Invalid test configuration: "
                        "missing 'resource_name'"),
                detail=(f"Expected resource config: "
                       f"{format_json_compact(expected)}")
            ))
            continue
        
        resource_type = expected["resource_type"]
        resource_name = expected["resource_name"]
        count_only = expected.get("count_only", False)
        
        actual_resources = actual_config.get("resource", {}).get(
            resource_type, {}
        )
        actual_resource = actual_resources.get(resource_name)
        
        expected_props = {
            k: v for k, v in expected.items()
            if k not in ["resource_name", "resource_type", "count_only"]
        }
        
        if actual_resource is None:
            found = False
            message = (f"❌ {resource_type}.{resource_name} missing "
                      "(resource not found)")
            detail = (f"Resource {resource_type}.{resource_name} "
                     "not found in actual config")
        elif count_only:
            found = True
            message = f"✅ {resource_type}.{resource_name} exists"
            detail = None
        else:
            found = is_subset(expected_props, actual_resource)
            if found:
                message = (f"✅ {resource_type}.{resource_name} found with "
                          "matching properties")
                detail = None
            else:
                message = (f"❌ {resource_type}.{resource_name} missing "
                          "(properties don't match)")
                reason = get_mismatch_reason(expected_props, actual_resource)
                detail = (
                    f"Expected:\n{format_json_compact(expected_props)}\n"
                    f"Actual:\n{format_json_compact(actual_resource)}\n"
                    f"Reason: {reason}"
                )
        
        results.append(ValidationResult(
            found=found,
            message=message,
            detail=detail
        ))
    
    found_count = sum(1 for r in results if r.found)
    return SectionValidation(
        all_found=all(r.found for r in results),
        results=results,
        summary=f"{found_count}/{len(results)} expected resources found"
    )


def validate_config(config_name: str, test_dir: Path) -> Tuple[bool, str]:
    """Main validation function"""
    actual_file = test_dir / f"{config_name}.tf.json"
    expected_file = test_dir / "expected-results" / f"{config_name}.json"
    
    # Load configs
    try:
        with open(actual_file) as f:
            actual_config = json.load(f)
    except FileNotFoundError:
        return False, f"❌ Actual config not found: {actual_file}"
    except json.JSONDecodeError as e:
        return False, f"❌ Invalid JSON in actual config: {e}"
    
    try:
        with open(expected_file) as f:
            expected_config = json.load(f)
    except FileNotFoundError:
        return False, f"❌ Expected config not found: {expected_file}"
    except json.JSONDecodeError as e:
        return False, f"❌ Invalid JSON in expected config: {e}"
    
    # Run validations
    provider_validation = validate_providers(
        expected_config.get("providers", []),
        actual_config
    )
    
    control_plane_validation = validate_control_planes(
        expected_config.get("control_planes", []),
        actual_config
    )
    
    resource_validation = validate_generic_resources(
        expected_config.get("resources", []),
        actual_config
    )
    
    variable_validation = validate_variables(
        expected_config.get("variables", []),
        actual_config
    )
    
    all_passed = (
        provider_validation.all_found
        and control_plane_validation.all_found
        and resource_validation.all_found
        and variable_validation.all_found
    )
    
    # Format output
    header = f"🧪 Partial Validation: {config_name}"
    separator = "=" * len(header)
    
    lines = [
        colorize(header, 'cyan'),
        colorize(separator, 'cyan'),
        ""
    ]
    
    # Summaries with colors
    lines.extend([
        colorize(provider_validation.summary, 'blue'),
        colorize(control_plane_validation.summary, 'blue'),
        colorize(resource_validation.summary, 'blue'),
        colorize(variable_validation.summary, 'blue'),
        ""
    ])
    
    # Detailed results
    for validation in [provider_validation, control_plane_validation,
                       resource_validation, variable_validation]:
        for result in validation.results:
            # Colorize messages
            if result.found:
                lines.append(colorize(result.message, 'green'))
            else:
                lines.append(colorize(result.message, 'red'))
            
            if result.detail and not result.found:
                detail_lines = result.detail.split('\n')
                for detail_line in detail_lines:
                    lines.append(colorize(f"    → {detail_line}", 'yellow'))
    
    lines.append("")
    if all_passed:
        lines.append(colorize("✅ PASSED", 'green'))
    else:
        lines.append(colorize("❌ FAILED", 'red'))
    
    lines.append("")
    
    # Add enhanced mode indicator
    if ENHANCED_MODE:
        lines.append(colorize("ℹ️  Enhanced mode: DeepDiff and colors enabled",
                             'cyan'))
        lines.append("")
    
    return all_passed, "\n".join(lines)


def main():
    """CLI entry point"""
    import argparse

    parser = argparse.ArgumentParser(
        description="Validate Terraform JSON configs"
    )
    parser.add_argument(
        "config_name",
        help="Name of the config to validate (without .tf.json)"
    )
    parser.add_argument(
        "--test-dir",
        type=Path,
        default=Path.cwd(),
        help="Directory containing test configs (default: current directory)"
    )

    args = parser.parse_args()

    passed, output = validate_config(args.config_name, args.test_dir)
    print(output)

    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()