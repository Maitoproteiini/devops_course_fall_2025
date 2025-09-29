"""
This module hosts the persisten storage service.
It has three endpoints:
    1. /
        - HTTP/GET
        - A basic get alive status request.
    2. /log
        - HTTP/POST
        - Logs the given text to storage.
    3. /log
        - HTTP/GET
        - Returns the logs that have been stored.
"""

from fastapi import FastAPI, Response, Request
import os

app = FastAPI()

DATA_DIR = os.getenv("DATA_DIR", "/data")
LOG_PATH = os.path.join(DATA_DIR, "log.txt")

@app.get("/", response_class=Response)
def root():
    """
    This endpoint is just a basic healthcheck that was used in setting up the services.
    """
    return Response(content="storage: alive", media_type="text/plain")

@app.post("/log", response_class=Response)
async def add_log(request: Request):
    """
    This endpoint logs the text that is given in the POST request to the storage.
    """
    os.makedirs(DATA_DIR, exist_ok=True)
    body = (await request.body()).decode("utf-8").rstrip("\n")
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(body + "\n")
    return Response(content="ok", media_type="text/plain")

@app.get("/log", response_class=Response)
def get_log():
    """
    This endpoint returns the logs in the storage.
    """
    try:
        with open(LOG_PATH, "r", encoding="utf-8") as f:
            return Response(content=f.read(), media_type="text/plain")
    except FileNotFoundError:
        return Response(content="", media_type="text/plain")
