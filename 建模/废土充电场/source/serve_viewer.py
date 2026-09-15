"""Open the fully offline model viewer on http://127.0.0.1:8766/viewer/."""
from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import threading
import webbrowser

ROOT = Path(__file__).resolve().parents[1]
HOST = "127.0.0.1"
PORT = 8766
URL = f"http://{HOST}:{PORT}/viewer/"


class ViewerHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript; charset=utf-8",
        ".css": "text/css; charset=utf-8",
        ".glb": "model/gltf-binary",
        ".gltf": "model/gltf+json",
    }

    def end_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def list_directory(self, path):
        self.send_error(403, "Directory listing is disabled. Open /viewer/.")
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description="在本机浏览器打开废土充电场三维查看器。")
    parser.add_argument("--no-browser", action="store_true", help="仅启动本地服务，不自动打开浏览器")
    args = parser.parse_args()
    if not (ROOT / "viewer" / "index.html").is_file():
        print("未找到 viewer/index.html，请保留完整项目目录。", file=sys.stderr)
        return 1

    handler = partial(ViewerHandler, directory=str(ROOT))
    try:
        server = ThreadingHTTPServer((HOST, PORT), handler)
    except OSError as exc:
        print(f"无法启动本地查看器：{exc}\n请关闭占用 {HOST}:{PORT} 的程序后重试。", file=sys.stderr)
        return 1
    server.daemon_threads = True
    worker = threading.Thread(target=server.serve_forever, name="local-model-viewer", daemon=True)
    worker.start()
    print(f"废土充电场三维查看器：{URL}", flush=True)
    print("服务仅供本机访问；按 Ctrl+C 关闭。", flush=True)
    if not (ROOT / "exports" / "废土充电场.glb").is_file():
        print("提示：GLB 尚未生成；导出后在页面中重新载入即可。", flush=True)

    try:
        if not args.no_browser:
            try:
                if not webbrowser.open(URL, new=2):
                    print("请手动在浏览器中打开上方地址。", flush=True)
            except webbrowser.Error:
                print("请手动在浏览器中打开上方地址。", flush=True)
        while worker.is_alive():
            worker.join(timeout=.5)
    except KeyboardInterrupt:
        print("\n正在关闭本地查看器。", flush=True)
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
