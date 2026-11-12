#!/usr/bin/env python3
"""Compare the failures in an .xcresult with ci/known-ios-test-failures.txt.

Exit 1 when:
  - a test fails that is not on the known list (a new failure), or
  - the result bundle holds no tests at all (the build or the test runner broke).
Known failures that now pass are reported as notices, so the list can be trimmed.

Usage: check-ios-test-results.py <path.xcresult> [known-failures.txt]
"""

import fnmatch
import json
import os
import subprocess
import sys


def load_known(path):
    patterns = []
    with open(path) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                patterns.append(line)
    return patterns


def load_tests(xcresult):
    out = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresult],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)


def walk(node, suite, results):
    kind = node.get("nodeType")
    if kind == "Test Suite":
        suite = node.get("name", suite)
    if kind == "Test Case":
        name = node.get("name", "").removesuffix("()")
        # A test case node may carry its own "Suite/test()" identifier; prefer it.
        ident = node.get("nodeIdentifier", "")
        if "/" in ident:
            ident = ident.removesuffix("()")
            suite_name, name = ident.split("/", 1)
        else:
            suite_name = suite
        results.append((f"{suite_name}/{name}", node.get("result", "")))
        return
    for child in node.get("children", []):
        walk(child, suite, results)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    xcresult = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    known_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "..", "ci", "known-ios-test-failures.txt")
    known = load_known(known_path)

    results = []
    for node in load_tests(xcresult).get("testNodes", []):
        walk(node, None, results)

    if not results:
        print("::error::The result bundle has no tests. The build or the test runner failed.")
        return 1

    failed = sorted({t for t, r in results if r == "Failed"})
    passed = {t for t, r in results if r == "Passed"}
    is_known = lambda t: any(fnmatch.fnmatchcase(t, p) for p in known)

    new = [t for t in failed if not is_known(t)]
    expected = [t for t in failed if is_known(t)]
    # Exact entries (no wildcard) that passed this time.
    fixed = [p for p in known if "*" not in p and p in passed]

    print(f"{len(results)} tests: {len(passed)} passed, {len(failed)} failed "
          f"({len(expected)} known, {len(new)} new)")
    for t in expected:
        print(f"  known failure: {t}")
    for t in fixed:
        print(f"::notice::{t} passes now. Remove it from ci/known-ios-test-failures.txt.")
    for t in new:
        print(f"::error::New test failure: {t}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(f"### iOS unit tests\n\n{len(results)} tests, {len(failed)} failed "
                    f"({len(expected)} known, **{len(new)} new**)\n\n")
            for t in new:
                f.write(f"- NEW: `{t}`\n")
            for t in fixed:
                f.write(f"- now passing (remove from known list): `{t}`\n")

    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())
