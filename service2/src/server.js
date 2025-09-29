/*
    This module hosts service2. It has two endpoints:
        1. /
            - HTTP/GET
            - A basic get alive status request.
        2. /status
            - HTTP/GET
            - Returns status of service2 and logs it to both storages.
    This service acts as a forwarding port to storage.
*/

const express = require("express");
const fs = require("node:fs/promises");
const path = require("node:path");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const sh = promisify(execFile);

const app = express();
app.use(express.text({ type: "*/*" }));

const PORT = process.env.PORT || 8081;

// Good storage
const STORAGE_URL = process.env.STORAGE_URL || "http://storage:8080";

// Bad storage
const VSTORAGE_DIR = process.env.VSTORAGE_DIR || "/data/vstorage";
const VSTORAGE_FILE = path.join(VSTORAGE_DIR, "log.txt");

app.get("/", (req, res) => {
    /*
        This endpoint is just a basic healthcheck that was used in setting up the services.
    */
    res.type("text").send("service2: alive");
});

app.get("/status", async (req, res) => {
    /*
        This endpoint creates a status recird of service2 and logs it to both storages.
    */
    const service2Record = await returnService2Record();
    await Promise.allSettled([ postToStorage(service2Record), postToVstorage(service2Record) ]);
    return res.type("text").send(service2Record);
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`service2 listening on ${PORT}`);
});

async function returnUptimeHours() {
    /*
        This function returns the amount of time the service has been up.
    */
    try {
        const txt = await fs.readFile("/proc/uptime", "utf8");
        const secs = parseFloat(txt.split(/\s+/)[0]);
        return secs / 3600;
    } catch { return -1; }
}

async function returnFreeRootMB() {
    /*
        This function returns the amount of free disk space.
    */
    try {
        const { stdout } = await sh("df", ["-k", "/"]);
        const line = stdout.trim().split("\n").at(-1);
        const parts = line.trim().split(/\s+/);
        const availKB = parseInt(parts[3], 10);
        return availKB / 1024;
    } catch { return -1; }
}

async function returnService2Record() {
    /*
        This function creates a status record of service2 and returns it.
    */
    const iso = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const up = await returnUptimeHours();
    const free = await returnFreeRootMB();
    return `Timestamp2: ${iso}, uptime ${up.toFixed(2)} hours, free disk in root: ${Math.round(free)} MBytes`;
}

async function postToStorage(line) {
    /*
        This function sends a POST request to storage to log the line given.
    */
    const r = await fetch(`${STORAGE_URL}/log`, {
        method: "POST",
        headers: { "content-type": "text/plain" },
        body: line
    });
    if (!r.ok) throw new Error(String(r.status));
}

async function postToVstorage(line) {
    /*
        This function appends given line to vstorage.
    */
    // If vstorage does not exist, create one.
    await fs.mkdir(VSTORAGE_DIR, { recursive: true });
    await fs.appendFile(VSTORAGE_FILE, line.replace(/\n+$/, "") + "\n", "utf8");
}
