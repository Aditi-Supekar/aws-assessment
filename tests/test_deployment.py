#!/usr/bin/env python3
"""
test_deployment.py — Unleash live AWS Assessment Test Script

1. Authenticate with Cognito (us-east-1) to get a JWT
2. Concurrently call /greet on both regions
3. Concurrently call /dispatch on both regions
4. Assert region in response matches expected region
5. Print latency to show geographic performance difference
"""

import json
import os
import sys
import time
import concurrent.futures

import boto3
import requests

# ============================================================================
# CONFIGURATION — set these as environment variables before running
# ============================================================================

USER_POOL_ID      = os.environ.get("USER_POOL_ID", "")
CLIENT_ID         = os.environ.get("CLIENT_ID", "")
TEST_EMAIL        = os.environ.get("TEST_EMAIL", "aditisupekar2412@gmail.com")
TEST_PASSWORD     = os.environ.get("TEST_PASSWORD", "")
PRIMARY_API_URL   = os.environ.get("PRIMARY_API_URL", "")
SECONDARY_API_URL = os.environ.get("SECONDARY_API_URL", "")

# ============================================================================
# STEP 1 — Authenticate with Cognito and get JWT
# ============================================================================

def get_jwt_token():
    print("\n[1] Authenticating with Cognito...")
    client = boto3.client("cognito-idp", region_name="us-east-1")

    try:
        response = client.initiate_auth(
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": TEST_EMAIL,
                "PASSWORD": TEST_PASSWORD,
            },
            ClientId=CLIENT_ID,
        )
        token = response["AuthenticationResult"]["IdToken"]
        print(f"    ✓ JWT obtained for {TEST_EMAIL}")
        return token

    except client.exceptions.NotAuthorizedException:
        print("    ✗ Wrong username or password")
        sys.exit(1)
    except client.exceptions.UserNotFoundException:
        print(f"    ✗ User {TEST_EMAIL} not found")
        sys.exit(1)
    except Exception as e:
        print(f"    ✗ Auth error: {e}")
        sys.exit(1)

# ============================================================================
# STEP 2 & 3 — Call endpoint and measure latency
# ============================================================================

def call_endpoint(label, url, method, headers, expected_region):
    start = time.perf_counter()
    try:
        if method == "GET":
            resp = requests.get(url, headers=headers, timeout=30)
        else:
            resp = requests.post(url, headers=headers, timeout=30)

        latency_ms = round((time.perf_counter() - start) * 1000, 2)

        try:
            body = resp.json()
        except Exception:
            body = {"raw": resp.text}

        return {
            "label":           label,
            "status_code":     resp.status_code,
            "body":            body,
            "latency_ms":      latency_ms,
            "expected_region": expected_region,
            "actual_region":   body.get("region", "MISSING"),
            "success":         resp.status_code in (200, 202),
        }

    except Exception as e:
        latency_ms = round((time.perf_counter() - start) * 1000, 2)
        return {
            "label":           label,
            "status_code":     None,
            "body":            {"error": str(e)},
            "latency_ms":      latency_ms,
            "expected_region": expected_region,
            "actual_region":   "ERROR",
            "success":         False,
        }


def run_concurrent(tasks):
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(tasks)) as executor:
        futures = {
            executor.submit(call_endpoint, *task): task[0]
            for task in tasks
        }
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())
    # Sort by label for consistent output
    return sorted(results, key=lambda x: x["label"])

# ============================================================================
# MAIN
# ============================================================================

def main():
    # Validate env vars are set
    missing = [n for v, n in [
        (USER_POOL_ID,      "USER_POOL_ID"),
        (CLIENT_ID,         "CLIENT_ID"),
        (TEST_PASSWORD,     "TEST_PASSWORD"),
        (PRIMARY_API_URL,   "PRIMARY_API_URL"),
        (SECONDARY_API_URL, "SECONDARY_API_URL"),
    ] if not v]

    if missing:
        print("✗ Missing environment variables:")
        for m in missing:
            print(f"    export {m}=<value>")
        sys.exit(1)

    print("=" * 55)
    print("  Unleash live — AWS Assessment Test")
    print("=" * 55)

    # ── Step 1: Get JWT ──────────────────────────────────────
    token   = get_jwt_token()
    headers = {"Authorization": f"Bearer {token}"}

    # ── Step 2: Concurrent /greet both regions ───────────────
    print("\n[2] Calling /greet concurrently on both regions...")
    greet_results = run_concurrent([
        ("GREET us-east-1", f"{PRIMARY_API_URL}/greet",   "GET", headers, "us-east-1"),
        ("GREET eu-west-1", f"{SECONDARY_API_URL}/greet", "GET", headers, "eu-west-1"),
    ])

    greet_passed = True
    for r in greet_results:
        status  = r["status_code"]
        latency = r["latency_ms"]
        actual  = r["actual_region"]
        expected = r["expected_region"]

        if not r["success"]:
            print(f"    ✗ {r['label']} — HTTP {status} ({latency}ms)")
            print(f"      Body: {json.dumps(r['body'], indent=6)}")
            greet_passed = False
        else:
            region_ok = actual == expected
            symbol    = "✓" if region_ok else "✗"
            print(f"    {symbol} {r['label']} — HTTP {status} ({latency}ms)")
            print(f"      Region expected : {expected}")
            print(f"      Region received : {actual}")
            print(f"      Response        : {json.dumps(r['body'])}")
            if not region_ok:
                greet_passed = False

    # ── Step 3: Concurrent /dispatch both regions ────────────
    print("\n[3] Calling /dispatch concurrently on both regions...")
    dispatch_results = run_concurrent([
        ("DISPATCH us-east-1", f"{PRIMARY_API_URL}/dispatch",   "POST", headers, "us-east-1"),
        ("DISPATCH eu-west-1", f"{SECONDARY_API_URL}/dispatch", "POST", headers, "eu-west-1"),
    ])

    dispatch_passed = True
    for r in dispatch_results:
        status  = r["status_code"]
        latency = r["latency_ms"]
        actual  = r["actual_region"]
        expected = r["expected_region"]

        if not r["success"]:
            print(f"    ✗ {r['label']} — HTTP {status} ({latency}ms)")
            print(f"      Body: {json.dumps(r['body'], indent=6)}")
            dispatch_passed = False
        else:
            region_ok = actual == expected
            symbol    = "✓" if region_ok else "✗"
            print(f"    {symbol} {r['label']} — HTTP {status} ({latency}ms)")
            print(f"      Region expected : {expected}")
            print(f"      Region received : {actual}")
            print(f"      Response        : {json.dumps(r['body'])}")
            if not region_ok:
                dispatch_passed = False

    # ── Step 4: Latency summary ──────────────────────────────
    print("\n[4] Latency Summary:")
    print(f"    {'Endpoint':<25} {'Region':<12} {'Latency':>10}")
    print(f"    {'-'*50}")
    for r in greet_results + dispatch_results:
        print(f"    {r['label']:<25} {r['expected_region']:<12} {r['latency_ms']:>8.2f} ms")

    # Geographic latency difference
    g1 = next((r for r in greet_results if "us-east-1" in r["label"]), None)
    g2 = next((r for r in greet_results if "eu-west-1" in r["label"]), None)
    if g1 and g2:
        diff = abs(g1["latency_ms"] - g2["latency_ms"])
        print(f"\n    Geographic latency difference: {diff:.2f} ms")
        print(f"    (us-east-1: {g1['latency_ms']}ms vs eu-west-1: {g2['latency_ms']}ms)")

    # ── Final result ─────────────────────────────────────────
    print("\n" + "=" * 55)
    if greet_passed and dispatch_passed:
        print("  ✓ ALL TESTS PASSED — Deployment is healthy!")
        print("  ✓ SNS messages sent to Unleash live topic")
        print("=" * 55)
        sys.exit(0)
    else:
        print("  ✗ SOME TESTS FAILED — Check output above")
        print("=" * 55)
        sys.exit(1)


if __name__ == "__main__":
    main()
