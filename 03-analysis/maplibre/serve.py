#!/usr/bin/env python3
"""
PMTiles 用 HTTP（Content-Length / Range 対応）。
リポジトリルートをカレントにして起動し、/data 以下の PMTiles 等を配信する。

使い方（リポジトリルートがカレントになるよう、このファイルの場所から 2 つ上 = zure-map-pipeline ルート）:
  cd /path/to/zure-map-pipeline/03-analysis/maplibre && python3 serve.py
  python3 serve.py 8765   # 8080 が使用中のとき別ポート
"""
import http.server
import io
import os
import re
import sys


class RangeRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Content-Length を付与し、Range に 206 で応答する。"""

    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            return super().send_head()
        try:
            size = os.path.getsize(path)
        except OSError:
            self.send_error(404, "File not found")
            return None

        range_header = self.headers.get("Range")
        if range_header:
            m = re.match(r"bytes=(\d*)-(\d*)", range_header)
            if m:
                start = int(m.group(1)) if m.group(1) else 0
                end = int(m.group(2)) if m.group(2) else size - 1
                end = min(end, size - 1)
                if start <= end and start < size:
                    length = end - start + 1
                    with open(path, "rb") as f:
                        f.seek(start)
                        body = f.read(length)
                    self.send_response(206, "Partial Content")
                    self.send_header("Content-type", self.guess_type(path))
                    self.send_header("Content-Length", str(length))
                    self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
                    self.send_header("Accept-Ranges", "bytes")
                    self.end_headers()
                    return io.BytesIO(body)
            self.send_error(416, "Requested Range Not Satisfiable")
            return None

        try:
            f = open(path, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return None
        self.send_response(200)
        self.send_header("Content-type", self.guess_type(path))
        self.send_header("Content-Length", str(size))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        return f


def run(port=8080):
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.normpath(os.path.join(here, "..", ".."))
    os.chdir(repo_root)
    server = http.server.HTTPServer(("", port), RangeRequestHandler)
    print(f"PMTiles 対応サーバー（ルート={repo_root}）: http://localhost:{port}/03-analysis/maplibre/index.html")
    print("  系別 z0–11 検図: 上記に ?mode=z12 （互換 ?mode=z13。既定 05-pmtiles/09.pmtiles、?kei=09 または ?pmtiles=…）")
    print("Ctrl+C で停止")
    server.serve_forever()


if __name__ == "__main__":
    default_port = 8080
    if len(sys.argv) > 1:
        try:
            default_port = int(sys.argv[1])
        except ValueError:
            print("使い方: python3 serve.py [ポート番号]  例: python3 serve.py 8765", file=sys.stderr)
            sys.exit(2)
    try:
        run(default_port)
    except OSError as e:
        if e.errno == 98:  # Linux: EADDRINUSE
            print(
                f"Error: ポート {default_port} は既に使用中です（Address already in use）。\n"
                f"  別ポートで起動: python3 serve.py 8765\n"
                f"  占有プロセス確認: ss -tlnp | grep ':{default_port}'  または  lsof -i :{default_port}",
                file=sys.stderr,
            )
            sys.exit(1)
        raise
