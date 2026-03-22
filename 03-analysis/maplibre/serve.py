#!/usr/bin/env python3
"""リポジトリルートを配信。PMTiles は Range 対応。

  cd 03-analysis/maplibre && python3 serve.py

ポート 8080 固定。起動したら README の URL をブラウザで開く。
"""
import http.server
import io
import os
import re
import sys

PORT = 8080


class RangeRequestHandler(http.server.SimpleHTTPRequestHandler):
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


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.normpath(os.path.join(here, "..", ".."))
    os.chdir(repo)
    http.server.HTTPServer(("", PORT), RangeRequestHandler).serve_forever()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        print("使い方: python3 serve.py", file=sys.stderr)
        sys.exit(2)
    try:
        print("http://localhost:{}/03-analysis/maplibre/index.html".format(PORT))
        print("Ctrl+C で停止")
        main()
    except OSError as e:
        if e.errno == 98:
            print("ポート {} は使用中です。".format(PORT), file=sys.stderr)
            sys.exit(1)
        raise
