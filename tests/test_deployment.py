#!/usr/bin/env python3
import concurrent.futures
import json
import os
import sys
import time

import boto3
import requests

USER_POOL_ID      = os.environ.get("USER_POOL_ID", "")
CLIENT_ID         = os.environ.get("CLIENT_ID", "")
TEST_EMAIL        = os.environ.get("TEST_EMAIL", "aditisupekar2412@gmail.com")
TEST_PASSWORD     = os.environ.get("TEST_PASSWORD", "")
PRIMARY_API_URL   = os.environ.get("PRIMARY_API_URL", "")
SECONDARY_API_URL = os.environ.get("SECONDARY_API_URL", "")


def get_token():
    client = boto3.client("cognito-idp", region_name="us-east-1")
    res = client.initiate_auth(
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={"USERNAME": TEST_EMAIL, "PASSWORD": TEST_PASSWORD},
        ClientId=CLIENT_ID,
    )
    return res["AuthenticationResult"]["IdToken"]


def call(label, url, method, headers, region):
    start = time.perf_counter()
    r = requests.get(url, headers=headers, timeout=30) if method == "GET" \
        else requests.post(url, headers=headers, timeout=30)
    ms   = round((time.perf_counter() - start) * 1000, 2)
    body = r.json() if "application/json" in r.headers.get("content-type", "") else {"raw": r.text}
    return {"label": label, "status": r.status_code, "body": body,
            "ms": ms, "expected": region, "actual": body.get("region", "MISSING"),
            "ok": r.status_code in (200, 202)}


def run(tasks):
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(tasks)) as ex:
        results = list(ex.map(lambda t: call(*t), tasks))
    return sorted(results, key=lambda x: x["label"])


def print_results(results):
    passed = True
    for r in results:
        if not r["ok"]:
            print(f"    {r['body']}")
            passed = False
        else:
            match = r["actual"] == r["expected"]
            print(f"    body={json.dumps(r['body'])}")
            if not match:
                passed = False
    return passed


def main():
    missing = [n for v, n in [
        (USER_POOL_ID, "USER_POOL_ID"), (CLIENT_ID, "CLIENT_ID"),
        (TEST_PASSWORD, "TEST_PASSWORD"), (PRIMARY_API_URL, "PRIMARY_API_URL"),
        (SECONDARY_API_URL, "SECONDARY_API_URL"),
    ] if not v]
    if missing:
        print(f"Missing env vars: {', '.join(missing)}")
        sys.exit(1)

    print("\nUnleash live — Deployment Test\n")

    print(" Authenticating...")
    token   = get_token()
    headers = {"Authorization": f"Bearer {token}"}
    print(f"JWT obtained\n")

    print(" /greet — both regions")
    greet_ok = print_results(run([
        ("GREET us-east-1", f"{PRIMARY_API_URL}/greet",   "GET",  headers, "us-east-1"),
        ("GREET eu-west-1", f"{SECONDARY_API_URL}/greet", "GET",  headers, "eu-west-1"),
    ]))

    print("\n/dispatch — both regions")
    dispatch_ok = print_results(run([
        ("DISPATCH us-east-1", f"{PRIMARY_API_URL}/dispatch",   "POST", headers, "us-east-1"),
        ("DISPATCH eu-west-1", f"{SECONDARY_API_URL}/dispatch", "POST", headers, "eu-west-1"),
    ]))

    print("\n=== Result ===")
    if greet_ok and dispatch_ok:
        print("All tests passed\n")
        sys.exit(0)
    else:
        print("Some tests failed\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
