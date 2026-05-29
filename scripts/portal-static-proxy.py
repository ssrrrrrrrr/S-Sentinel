#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.client
import mimetypes
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

class PortalStaticProxyHandler(BaseHTTPRequestHandler):
    dist_dir: Path
    api_host: str
    api_port: int

    def log_message(self, fmt: str, *args: object) -> None:
        print("[%s] %s" % (self.log_date_time_string(), fmt % args))

    def do_GET(self) -> None:
        if self.path.startswith("/api/") or self.path == "/healthz":
            self.proxy_to_api()
            return

        self.serve_static()

    def do_POST(self) -> None:
        if self.path.startswith("/api/"):
            self.proxy_to_api()
            return

        self.send_error(405, "method not allowed")

    def proxy_to_api(self) -> None:
        body = None
        length = self.headers.get("content-length")
        if length:
            body = self.rfile.read(int(length))

        conn = http.client.HTTPConnection(self.api_host, self.api_port, timeout=30)
        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in {"host", "connection", "content-length"}
        }

        try:
            conn.request(self.command, self.path, body=body, headers=headers)
            response = conn.getresponse()
            data = response.read()

            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in {"connection", "transfer-encoding"}:
                    self.send_header(key, value)
            self.end_headers()
            self.wfile.write(data)
        except Exception as exc:
            self.send_error(502, f"api proxy failed: {exc}")
        finally:
            conn.close()

    def serve_static(self) -> None:
        request_path = urlsplit(self.path).path
        relative = request_path.lstrip("/") or "index.html"
        candidate = (self.dist_dir / relative).resolve()

        try:
            candidate.relative_to(self.dist_dir.resolve())
        except ValueError:
            self.send_error(403, "forbidden")
            return

        if candidate.is_dir():
            candidate = candidate / "index.html"

        if not candidate.exists():
            candidate = self.dist_dir / "index.html"

        content_type = mimetypes.guess_type(str(candidate))[0] or "application/octet-stream"
        data = candidate.read_bytes()

        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        if candidate.name == "config.json":
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=18081)
    parser.add_argument("--dist-dir", default="web/dist")
    parser.add_argument("--api-host", default="127.0.0.1")
    parser.add_argument("--api-port", type=int, default=18090)
    args = parser.parse_args()

    dist_dir = Path(args.dist_dir)
    if not (dist_dir / "index.html").exists():
        raise SystemExit(f"dist index.html not found: {dist_dir / 'index.html'}")

    PortalStaticProxyHandler.dist_dir = dist_dir
    PortalStaticProxyHandler.api_host = args.api_host
    PortalStaticProxyHandler.api_port = args.api_port

    server = ThreadingHTTPServer((args.host, args.port), PortalStaticProxyHandler)
    print(f"serving Portal dist={dist_dir} on {args.host}:{args.port}, proxy /api -> {args.api_host}:{args.api_port}")
    server.serve_forever()

if __name__ == "__main__":
    main()
