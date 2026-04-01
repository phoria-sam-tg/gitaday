"""
Quick practical eval: 10 tool-calling tests against a local OpenAI-compatible model.
Tests tool selection, argument accuracy, multi-tool, refusal, and format compliance.
"""
import argparse
import json
import os
import time
from pathlib import Path

import httpx

BASE_URL = os.environ.get("OPENAI_BASE_URL", "http://localhost:8000/v1")
API_KEY = os.environ.get("OPENAI_API_KEY", "local")

# ---------------------------------------------------------------------------
# Tool schemas (realistic samcloud-style tools)
# ---------------------------------------------------------------------------
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "register_service",
            "description": "Register a new service in the samcloud registry",
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Service name"},
                    "port": {"type": "integer", "description": "Port number"},
                    "host": {"type": "string", "description": "Hostname or IP"},
                    "protocol": {"type": "string", "enum": ["http", "https", "tcp"]},
                },
                "required": ["name", "port", "host"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_service_status",
            "description": "Check the health status of a registered service",
            "parameters": {
                "type": "object",
                "properties": {
                    "service_id": {"type": "string", "description": "Service ID"},
                },
                "required": ["service_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_services",
            "description": "List all registered services, optionally filtered by host",
            "parameters": {
                "type": "object",
                "properties": {
                    "host": {"type": "string", "description": "Filter by hostname"},
                    "status": {"type": "string", "enum": ["online", "offline", "degraded"]},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "create_dns_record",
            "description": "Create a DNS A or CNAME record",
            "parameters": {
                "type": "object",
                "properties": {
                    "subdomain": {"type": "string", "description": "Subdomain to create"},
                    "target": {"type": "string", "description": "Target IP or hostname"},
                    "type": {"type": "string", "enum": ["A", "CNAME"]},
                    "ttl": {"type": "integer", "description": "TTL in seconds"},
                },
                "required": ["subdomain", "target", "type"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_command",
            "description": "Execute a shell command on a remote host",
            "parameters": {
                "type": "object",
                "properties": {
                    "host": {"type": "string", "description": "Target host"},
                    "command": {"type": "string", "description": "Command to execute"},
                    "timeout": {"type": "integer", "description": "Timeout in seconds"},
                },
                "required": ["host", "command"],
            },
        },
    },
]

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------
TESTS = [
    {
        "id": "simple_single",
        "name": "Simple single tool call",
        "prompt": "Check the status of service 'jellyfin-prod'",
        "expect_tools": ["get_service_status"],
        "expect_args": {"service_id": "jellyfin-prod"},
        "category": "simple",
    },
    {
        "id": "correct_selection",
        "name": "Select correct tool from 5 options",
        "prompt": "Show me all services running on tesseract",
        "expect_tools": ["list_services"],
        "expect_args": {"host": "tesseract"},
        "category": "simple",
    },
    {
        "id": "multi_param",
        "name": "Multiple required + optional params",
        "prompt": "Register a new service called 'comfyui' on port 8188, host 192.168.1.45, using http",
        "expect_tools": ["register_service"],
        "expect_args": {"name": "comfyui", "port": 8188, "host": "192.168.1.45", "protocol": "http"},
        "category": "simple",
    },
    {
        "id": "enum_constraint",
        "name": "Respect enum constraints",
        "prompt": "Create a CNAME record for 'api' pointing to 'gateway.example.com' with TTL 300",
        "expect_tools": ["create_dns_record"],
        "expect_args": {"subdomain": "api", "target": "gateway.example.com", "type": "CNAME", "ttl": 300},
        "category": "simple",
    },
    {
        "id": "parallel_calls",
        "name": "Parallel tool calls",
        "prompt": "Check the status of both 'jellyfin-prod' and 'comfyui-dev' services",
        "expect_tools": ["get_service_status", "get_service_status"],
        "category": "parallel",
    },
    {
        "id": "multi_step",
        "name": "Multi-step: register then check",
        "prompt": "Register 'nginx' on port 80, host slice, protocol http — then check its status",
        "expect_tools": ["register_service"],
        "expect_min_tools": 1,
        "category": "multi",
    },
    {
        "id": "irrelevance",
        "name": "No tool needed — general question",
        "prompt": "What is the capital of France?",
        "expect_tools": [],
        "category": "relevance",
    },
    {
        "id": "refusal",
        "name": "No matching tool — should not hallucinate",
        "prompt": "Send an email notification to the admin about the outage",
        "expect_tools": [],
        "category": "relevance",
    },
    {
        "id": "type_coercion",
        "name": "Numeric string to integer",
        "prompt": "Register service 'redis' on port 6379 at host db-server",
        "expect_tools": ["register_service"],
        "expect_args": {"port": 6379},
        "category": "format",
    },
    {
        "id": "ambiguity",
        "name": "Ambiguous but resolvable",
        "prompt": "List offline services",
        "expect_tools": ["list_services"],
        "expect_args": {"status": "offline"},
        "category": "simple",
    },
]


def call_model(prompt: str) -> dict:
    """Call the local model with tools."""
    resp = httpx.post(
        f"{BASE_URL}/chat/completions",
        json={
            "model": "local",
            "messages": [
                {"role": "system", "content": "You are a helpful infrastructure assistant. Use the provided tools when appropriate. If no tool matches the request, respond normally without calling any tool."},
                {"role": "user", "content": prompt},
            ],
            "tools": TOOLS,
            "tool_choice": "auto",
            "max_tokens": 512,
        },
        headers={"Authorization": f"Bearer {API_KEY}"},
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()


def evaluate_test(test: dict) -> dict:
    """Run a single test and score it."""
    start = time.time()
    try:
        result = call_model(test["prompt"])
    except Exception as e:
        return {"id": test["id"], "name": test["name"], "category": test["category"], "pass": False, "score": 0, "error": str(e), "duration": time.time() - start}

    duration = time.time() - start
    choice = result["choices"][0]
    message = choice["message"]
    tool_calls = message.get("tool_calls") or []

    called_tools = [tc["function"]["name"] for tc in tool_calls]
    called_args = {}
    for tc in tool_calls:
        try:
            called_args.update(json.loads(tc["function"]["arguments"]))
        except (json.JSONDecodeError, KeyError):
            pass

    score = 0
    reasons = []
    expected = test["expect_tools"]

    # Tool selection scoring (50 points)
    if not expected and not called_tools:
        score += 50
        reasons.append("Correctly avoided tool calls")
    elif not expected and called_tools:
        reasons.append(f"Should not have called tools, but called: {called_tools}")
    elif expected and not called_tools:
        reasons.append(f"Expected {expected} but no tools called")
    else:
        expected_set = set(expected)
        called_set = set(called_tools)
        if expected_set == called_set or (test.get("expect_min_tools") and len(called_tools) >= test["expect_min_tools"]):
            score += 50
            reasons.append("Correct tool(s) selected")
        elif expected_set & called_set:
            score += 25
            reasons.append(f"Partial match: expected {expected}, got {called_tools}")
        else:
            reasons.append(f"Wrong tool(s): expected {expected}, got {called_tools}")

    # Argument accuracy scoring (50 points)
    expect_args = test.get("expect_args", {})
    if expect_args and called_args:
        matched = 0
        total = len(expect_args)
        for k, v in expect_args.items():
            actual = called_args.get(k)
            if actual == v:
                matched += 1
            elif str(actual).lower() == str(v).lower():
                matched += 0.8
            else:
                reasons.append(f"Arg mismatch: {k}={actual} (expected {v})")
        arg_score = int(50 * matched / total) if total > 0 else 50
        score += arg_score
        if matched == total:
            reasons.append("All arguments correct")
    elif not expect_args:
        score += 50  # No args to check

    passed = score >= 75

    return {
        "id": test["id"],
        "name": test["name"],
        "category": test["category"],
        "pass": passed,
        "score": score,
        "reasons": reasons,
        "called_tools": called_tools,
        "called_args": called_args,
        "duration": round(duration, 2),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="local")
    parser.add_argument("--output", default="results.json")
    args = parser.parse_args()

    print(f"Running {len(TESTS)} tests against {BASE_URL}...\n")

    results = []
    passed = 0
    total_score = 0

    for test in TESTS:
        r = evaluate_test(test)
        results.append(r)
        status = "PASS" if r["pass"] else "FAIL"
        icon = "+" if r["pass"] else "x"
        print(f"  [{icon}] {status} {r['id']:20s} score={r['score']:3d}  ({r['duration']:.1f}s)  {', '.join(r.get('reasons', []))}")
        if r["pass"]:
            passed += 1
        total_score += r["score"]

    avg_score = total_score / len(TESTS)
    print(f"\n{'='*60}")
    print(f"  Model: {args.model}")
    print(f"  Pass:  {passed}/{len(TESTS)} ({100*passed/len(TESTS):.0f}%)")
    print(f"  Score: {avg_score:.0f}/100 avg")
    print(f"{'='*60}")

    # Category breakdown
    cats = {}
    for r in results:
        c = r["category"]
        if c not in cats:
            cats[c] = {"pass": 0, "total": 0, "score": 0}
        cats[c]["total"] += 1
        cats[c]["score"] += r["score"]
        if r["pass"]:
            cats[c]["pass"] += 1

    print("\n  Category breakdown:")
    for cat, data in sorted(cats.items()):
        print(f"    {cat:12s}  {data['pass']}/{data['total']} pass  avg={data['score']/data['total']:.0f}")

    # Save results
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps({
        "model": args.model,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "summary": {"passed": passed, "total": len(TESTS), "avg_score": round(avg_score, 1)},
        "categories": cats,
        "results": results,
    }, indent=2))
    print(f"\n  Results saved to {args.output}")


if __name__ == "__main__":
    main()
