#!/usr/bin/env python3
"""
PMTiles 用 HTTP（Content-Length / Range 対応）。
リポジトリルートをカレントにして起動し、/data 以下の PMTiles 等を配信する。

使い方（リポジトリルートがカレントになるよう、このファイルの場所から 3 つ上をルートに設定）:
  cd /path/to/zure-map-pipeline/03-analysis/maplibre && python3 serve.py
"""
import http.server
import io
import os
import re


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
    repo_root = os.path.normpath(os.path.join(here, "..", "..", ".."))
    os.chdir(repo_root)
    server = http.server.HTTPServer(("", port), RangeRequestHandler)
    print(f"PMTiles 対応サーバー（ルート={repo_root}）: http://localhost:{port}/03-analysis/maplibre/index.html")
    print(f"  系9・z13 検図: http://localhost:{port}/03-analysis/maplibre/index-z13-09kei.html")
    print("Ctrl+C で停止")
    server.serve_forever()


if __name__ == "__main__":
    run(8080)
