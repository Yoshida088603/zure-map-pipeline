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
import subprocess
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


def _first_lan_ipv4():
    """WSL 等で Windows ブラウザから繋ぐときの候補（127 以外の最初の IPv4）。"""
    try:
        r = subprocess.run(
            ["hostname", "-I"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        if r.returncode != 0 or not r.stdout:
            return None
        for part in r.stdout.split():
            if part.startswith("127."):
                continue
            if "." in part and ":" not in part:
                return part
    except (OSError, subprocess.TimeoutExpired):
        pass
    return None


def run(port=8080):
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.normpath(os.path.join(here, "..", ".."))
    os.chdir(repo_root)
    server = http.server.HTTPServer(("", port), RangeRequestHandler)
    path = "/03-analysis/maplibre/index.html"
    lan = _first_lan_ipv4()
    print(f"PMTiles 対応サーバー（ルート={repo_root}）")
    print(f"  次をコピーしてブラウザのアドレス欄に貼り付け:")
    print(f"    http://127.0.0.1:{port}{path}")
    if lan:
        print(f"  WSL のとき Windows 側ブラウザで繋がらなければ:")
        print(f"    http://{lan}:{port}{path}")
    print("")
    print("  全系重畳: 上に ?mode=all-kei を付ける")
    print("  1 系のみ: ?mode=z12 （互換 ?mode=z13。?kei=09 や ?pmtiles=…）")
    print("")
    print(
        "  【Cursor の Simple Browser / 組み込みプレビューで開けないとき】\n"
        "    サーバは WSL 上で動いています。内蔵ブラウザは別環境のことがあり localhost に届きません。\n"
        "    → Windows の Chrome / Edge / Firefox で http://127.0.0.1:ポート/... を開いてください。"
    )
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
