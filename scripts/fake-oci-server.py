#!/usr/bin/env python3
"""Tiny stand-in for an OCI bucket, for scripts/test-oci-upload.sh only (never deployed): PUT stores a file under
the directory, GET/HEAD read it. Both the "write" address (/par/...) and the "public" address (/pub/...) map to
the same directory, like a real bucket with a write PAR and public reads."""
import http.server, os, sys, urllib.parse
ROOT = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def _path(self):
        p = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
        for pre in ("/par/", "/pub/"):
            if p.startswith(pre): return os.path.join(ROOT, p[len(pre):]), pre
        return None, None
    def do_PUT(self):
        f, pre = self._path()
        if f is None or pre != "/par/": return self.send_error(403)
        os.makedirs(os.path.dirname(f), exist_ok=True)
        n = int(self.headers.get("Content-Length", 0)); open(f, "wb").write(self.rfile.read(n))
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()
    def _get(self, body):
        f, pre = self._path()
        if f is None or pre != "/pub/" or not os.path.isfile(f): return self.send_error(404)
        data = open(f, "rb").read()
        self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers()
        if body: self.wfile.write(data)
    def do_GET(self): self._get(True)
    def do_HEAD(self): self._get(False)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
