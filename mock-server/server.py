"""
Mock server implementing the FrameGate upload contract. Multipart POST with a
manifest and a frame part, an Idempotency-Key header identical across retries.

The first shot follows the brief's suggested script: 503, 503, timeout, 500,
201. Everything after that — and every other key — succeeds immediately.
A timeout is simulated by sleeping past the client's timeout window rather
than by closing the socket, since the client cannot distinguish the two.
"""

import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCRIPT = ["503", "503", "timeout", "500", "201"]

# Attempts per idempotency key, so only the first shot exercises the script and
# later ones succeed at once — mirroring FakeTransport's design.
attempts_by_key = {}
script_key = None
stored_keys = set()


class Handler(BaseHTTPRequestHandler):

    def do_POST(self):
        if self.path != "/v1/captures":
            self.send_response(404)
            self.end_headers()
            return

        key = self.headers.get("Idempotency-Key")
        length = int(self.headers.get("Content-Length", 0))
        # The body must be drained regardless of outcome, or the connection
        # is left in a state the client cannot safely reuse.
        self.rfile.read(length)

        if not key:
            self._respond(422, b'{"error": "missing Idempotency-Key"}')
            return

        if key in stored_keys:
            self._respond(200, b'{"duplicate": true}')
            return

        attempt = attempts_by_key.get(key, 0)
        attempts_by_key[key] = attempt + 1

        global script_key
        if script_key is None:
            script_key = key

        if key == script_key and attempt < len(SCRIPT):
            outcome = SCRIPT[attempt]
        else:
            outcome = "201"

        print(f"capture key={key} attempt={attempt + 1} outcome={outcome}")

        if outcome == "timeout":
            # No close, no response: the client's own timeout fires first.
            time.sleep(30)
            return

        if outcome in ("503", "500"):
            self._respond(int(outcome), b'{"error": "try again"}')
            return

        stored_keys.add(key)
        self._respond(201, b'{"stored": true}')

    def log_message(self, format, *args):
        print(f"{self.address_string()} - {format % args}")

    def _respond(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print("FrameGate mock server listening on :8080")
    server.serve_forever()
