"""Local TLS regression: no network access or preexisting certificate needed."""
from pathlib import Path
import http.server
import os
import ssl
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"TLS_OK"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass

def main():
    with tempfile.TemporaryDirectory(prefix="kine-tls-") as directory:
        tmp = Path(directory)
        cert, key, exe = tmp / "cert.pem", tmp / "key.pem", tmp / "tls-smoke"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-days", "1", "-subj", "/CN=localhost", "-addext",
            "subjectAltName=DNS:localhost", "-keyout", str(key), "-out", str(cert)
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["odin", "build", "tests/security_tls_smoke.odin", "-file",
                        f"-out:{exe}"], cwd=ROOT, check=True)
        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert, key)
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            port = server.server_address[1]
            env = os.environ.copy()
            env["SSL_CERT_FILE"] = str(cert)
            subprocess.run([str(exe), f"https://localhost:{port}/", "accept"],
                           env=env, check=True, timeout=20)
            subprocess.run([str(exe), f"https://127.0.0.1:{port}/", "reject"],
                           env=env, check=True, timeout=20)
            env.pop("SSL_CERT_FILE", None)
            subprocess.run([str(exe), f"https://localhost:{port}/", "reject"],
                           env=env, check=True, timeout=20)
        finally:
            server.shutdown()
            server.server_close()
            worker.join()
    print("SECURITY_TLS_CERTIFICATE_TESTS_PASSED")

if __name__ == "__main__":
    main()
