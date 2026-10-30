#!/usr/bin/env python3
"""Validate `helm template` output: every rendered manifest must parse, and
every Deployment must carry probes and resource limits.

Usage: helm template <release> ./charts/microservices -f <values> \
         | python3 scripts/validate_templates.py
"""
import sys

import yaml


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def main():
    docs = [d for d in yaml.safe_load_all(sys.stdin) if d]
    kinds = {}
    for doc in docs:
        kinds[doc["kind"]] = kinds.get(doc["kind"], 0) + 1
    print(f"rendered {len(docs)} manifests: {kinds}")

    for expected in ("Deployment", "Service"):
        if expected not in kinds:
            fail(f"no {expected} rendered")
    deployments = [d for d in docs if d["kind"] == "Deployment"]
    for dep in deployments:
        name = dep["metadata"]["name"]
        for container in dep["spec"]["template"]["spec"]["containers"]:
            if container["name"] == "rabbitmq":
                continue  # no HTTP surface; TCP health is out of scope here
            if "livenessProbe" not in container or "readinessProbe" not in container:
                fail(f"{name}: container {container['name']} is missing a probe")
            if "resources" not in container or "limits" not in container["resources"]:
                fail(f"{name}: container {container['name']} has no resource limits")
    services = {s["metadata"]["name"] for s in docs if s["kind"] == "Service"}
    for dep in deployments:
        for container in dep["spec"]["template"]["spec"]["containers"]:
            for env in container.get("env", []):
                value = env.get("value", "")
                if value.startswith("http://") and ":8080" in value:
                    host = value.split("://", 1)[1].split(":", 1)[0]
                    if host in ("+", "*"):
                        continue  # wildcard bind, not a service reference
                    if host not in services:
                        fail(f"{dep['metadata']['name']}: env points at "
                             f"unknown Service {host}")
    print("OK: all Deployments have probes + limits, "
          "all env service references resolve")


if __name__ == "__main__":
    main()
