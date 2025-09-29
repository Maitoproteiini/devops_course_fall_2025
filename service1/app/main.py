#!/usr/bin/env python3

"""
This module hosts the service1. It has three endpoints:
    1. /
        - HTTP/GET
        - A basic get alive status request.
    2. /status
        - HTTP/GET
        - Returns statuses of both services and records service1 status record to both storages.
    3. /log
        - HTTP/GET
        - Forwards GET request to storage/log that returns the stored log.
This service acts as a forwarding port to service2 and storage.
Service2 and Storage are accessible only inside the Docker network.
This service is the sole public entrypoint.
"""

import os, shutil
import urllib.request as ureq
from fastapi import FastAPI, Response
from datetime import datetime, timezone
from urllib.request import urlopen
from urllib.error import URLError, HTTPError


app = FastAPI()

SERVICE2_URL = os.getenv("SERVICE2_URL", "http://service2:8081")
TIMEOUT = float(os.getenv("HTTP_TIMEOUT", "2.0"))

# Good storage
STORAGE_URL  = os.getenv("STORAGE_URL",  "http://storage:8080")

# Bad storage
VSTORAGE_DIR  = os.getenv("VSTORAGE_DIR", "/data/vstorage")
VSTORAGE_FILE = os.path.join(VSTORAGE_DIR, "log.txt")


# ENDPOINTS:

@app.get("/", response_class=Response)
def root():
    """
    This is just a basic endpoint to verify that the service is alive.
    It was not specified in the exercise requirements, but I found it useful for testing.
    The endpoint just returns an alive message.
    """
    return Response(content="service1: alive", media_type="text/plain")

@app.get("/status", response_class=Response)
def status():
    """
    This endpoint forwards requests to service2/status and storage/log.
    First, a status record of service1 is created and sent to storage and vstorage
    via post requests. Second, the status request is forwarded to service2,
    that sends back the status record of service2.
    Finally, both service records are sent back to user.
    """
    service1_record = return_service1_record()
    # Log service1 record to both storages.
    # Function returns back a dictionary with booleans expressing
    # whether or not the logging worked for each storage
    service1_logged_dict = log_to_both_storages(service1_record)
    response = ""
    if service1_logged_dict["storage"] is False:
        response = "Failed to log record to storage."
    if service1_logged_dict["vstorage"] is False:
        response += " Failed to log record to vstorage."
    if len(response) > 0:
        return Response(content=response, media_type="text/plain")
    service2_record = get_service2_status()
    response_body = service1_record
    if service2_record is not None:
        response_body = f"{service1_record}\n{service2_record}"
    return Response(content=response_body, media_type="text/plain")

@app.get("/log", response_class=Response)
def get_log():
    """
    This endpoint forwards a log GET request to storage and returns the response.
    If an exception occurs, this endpoint sends an error message.
    """
    try:
        with ureq.urlopen(f"{STORAGE_URL}/log", timeout=TIMEOUT) as r:
            return Response(content=r.read().decode("utf-8"), media_type="text/plain")
    except Exception as e:
        response = f"Failed to forward request to storage. Got exception: {e}"
        return Response(content=response, media_type="text/plain")

# HELPER FUNCTIONS:

def iso_utc_now() -> str:
    """
    Returns the current time in the following format: ISO 8601 UTC, seconds, trailing Z (no milliseconds)
    """
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

def uptime_hours() -> float:
    """
    Returns the amount of time the service has been up in hours.
    """
    try:
        with open("/proc/uptime", "r") as f:
            sec = float(f.read().split()[0])
        return sec / 3600.0
    except Exception:
        return -1.0

def free_root_mb() -> float:
    """
    Returns the amount of free disk space.
    """
    try:
        _, _, free = shutil.disk_usage("/")
        return free / (1024 * 1024)
    except Exception:
        return -1.0

def return_service1_record() -> str:
    """
    Returns a record of service1.
    """
    ts = iso_utc_now()
    up = uptime_hours()
    free_mb = free_root_mb()
    return f"Timestamp1: {ts}, uptime {up:.2f} hours, free disk in root: {free_mb:.0f} MBytes"

def log_to_both_storages(line: str) -> dict:
    """
    This function logs the given line to both storage and vstorage.
    Returns a dictionary with booleans indicating whether or not the logging succeeded or failed.
    The dict is of the following format:
    {
        [storage]: Boolean,
        [vstorage]: Boolean
    }
    """
    line = line.rstrip("\n")
    results = {"storage": False, "vstorage": False}

    # 1) Log to good storage (storage)
    try:
        import urllib.request as ureq
        req = ureq.Request(
            f"{STORAGE_URL}/log",
            data=(line).encode("utf-8"),
            method="POST",
            headers={"content-type": "text/plain"},
        )
        with ureq.urlopen(req, timeout=TIMEOUT):
            pass
        results["storage"] = True
    except Exception:
        pass

    # 2) Log to bad storage (vstorage)
    try:
        os.makedirs(VSTORAGE_DIR, exist_ok=True)
        with open(VSTORAGE_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        results["vstorage"] = True
    except Exception:
        pass

    return results

def get_service2_status() -> str | None:
    """
    This function returns the status record of service2 by making a GET request to service2/status endpoint.
    """
    try:
        with urlopen(f"{SERVICE2_URL}/status", timeout=TIMEOUT) as r:
            return r.read().decode().strip()
    except (URLError, HTTPError):
        return None