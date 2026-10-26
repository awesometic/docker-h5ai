#!/usr/bin/env python3
"""Exercise a built image through Nginx/FPM using disposable Docker volumes."""
import base64
import http.cookiejar
import io
import json
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request
import uuid
import zipfile


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True, timeout=60).strip()


def best_effort_docker(*args, quiet=False):
    try:
        subprocess.run(["docker", *args], check=True, timeout=30,
                       stdout=subprocess.DEVNULL if quiet else None)
    except (OSError, subprocess.SubprocessError) as error:
        print(f"Docker diagnostics/cleanup failed: {error}", file=sys.stderr)


if not __debug__:
    raise SystemExit("Run without -O or PYTHONOPTIMIZE; this test requires assertions")
if len(sys.argv) != 3:
    raise SystemExit("Usage: python3 tests/smoke.py IMAGE PLATFORM")
image, platform = sys.argv[1:]
MIN_PHP_VERSION_ID = 80512  # Minimum patched runtime for the October 21, 2026 release.
name = "h5ai-smoke-" + uuid.uuid4().hex[:10]
volumes = [name + "-config", name + "-files"]
opener = urllib.request.build_opener(
    urllib.request.ProxyHandler({}),
    urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
)


def request(path="/", data=None, auth=False):
    headers = {"User-Agent": "h5ai-smoke"}
    if auth:
        headers["Authorization"] = "Basic " + base64.b64encode(b"smoke:test-password").decode()
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url + path, json.dumps(data).encode() if data is not None else None, headers)
    try:
        with opener.open(req, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def api(data, auth=False):
    status, body = request("/_h5ai/public/index.php", data, auth)
    assert status == 200, (status, body[:300])
    result = json.loads(body)
    assert "err" not in result, result
    return result


def start(auth=False, timezone="Asia/Seoul"):
    global url
    docker("run", "-d", "--platform", platform, "--name", name,
           "-p", "127.0.0.1::80", "-v", volumes[0] + ":/config",
           "-v", volumes[1] + ":/h5ai", "-e", "PUID=1234", "-e", "PGID=2345",
           "-e", "TZ=" + timezone, "-e", "HTPASSWD=" + str(auth).lower(),
           "-e", "HTPASSWD_USER=smoke", "-e", "HTPASSWD_PW=test-password", image)
    url = "http://" + docker("port", name, "80/tcp")
    deadline = time.monotonic() + 45
    while True:
        try:
            status, body = request(auth=auth)
            if status == 200 and b"powered by h5ai" in body:
                return
        except (OSError, urllib.error.URLError):
            pass
        assert time.monotonic() < deadline, "Nginx/FPM did not become ready"
        time.sleep(0.5)


try:
    startup = subprocess.run(["docker", "run", "--rm", "--platform", platform,
                              "--entrypoint", "php", image, "-v"],
                             capture_output=True, text=True, timeout=60)
    assert startup.returncode == 0 and not startup.stderr, startup.stderr
    for volume in volumes:
        docker("volume", "create", volume)
    start()
    docker("exec", name, "nginx", "-t")
    cli = docker("exec", name, "php", "-r", "echo PHP_VERSION;")

    probe = '''<?php
    echo json_encode([
        'version' => PHP_VERSION, 'version_id' => PHP_VERSION_ID, 'sapi' => PHP_SAPI,
        'timezone' => date_default_timezone_get(),
        'extensions' => array_map('extension_loaded', ['session', 'json', 'xml',
            'mbstring', 'exif', 'intl', 'gd', 'imagick', 'zip', 'Zend OPcache']),
        'opcache' => opcache_get_status(false),
    ]);
    '''
    subprocess.run(["docker", "exec", "-i", name, "sh", "-c", "cat > /h5ai/runtime.php"],
                   input=probe, text=True, check=True, timeout=60)
    docker("exec", name, "php", "-r",
           'file_put_contents("/h5ai/sample.txt", "h5ai smoke\\n");'
           '$im=imagecreatetruecolor(320,180); imagepng($im,"/h5ai/image.png");')
    docker("exec", name, "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
           "color=c=blue:s=320x180:r=1:d=12", "-c:v", "mpeg4", "/h5ai/movie.mp4")
    status, body = request("/runtime.php")
    assert status == 200, ("FPM runtime probe", status)
    runtime = json.loads(body)
    assert runtime["version"] == cli and runtime["sapi"] == "fpm-fcgi", runtime
    assert runtime["version_id"] >= MIN_PHP_VERSION_ID, ("PHP security baseline", runtime)
    assert runtime["timezone"] == "Asia/Seoul" and all(runtime["extensions"]), runtime
    assert runtime["opcache"]["opcache_enabled"], runtime
    if platform in ("linux/amd64", "linux/arm64"):
        assert runtime["opcache"]["jit"]["on"], runtime
    assert request("/sample.txt") == (200, b"h5ai smoke\n")
    listing = api({"action": "get", "items": {"href": "/", "what": 1}})
    assert "/sample.txt" in {item["href"] for item in listing["items"]}, listing
    requested_thumbs = [
        {"type": kind, "href": href, "width": 120, "height": 80}
        for kind, href in [("img", "/image.png"), ("mov", "/movie.mp4")]
    ]
    thumbs = api({"action": "get", "thumbs": requested_thumbs})["thumbs"]
    assert isinstance(thumbs, list) and len(thumbs) == len(requested_thumbs), ("Missing thumbnails", thumbs)
    for thumb in thumbs:
        assert isinstance(thumb, str) and thumb.startswith("/_h5ai/"), thumbs
        status, body = request(thumb)
        assert status == 200 and body.startswith(b"\xff\xd8"), ("Thumbnail download", thumb, status)
        dimensions = subprocess.check_output(
            ["docker", "exec", "-i", name, "php", "-r",
             "$image = imagecreatefromstring(stream_get_contents(STDIN));"
             "if ($image === false) exit(1);"
             "echo json_encode([imagesx($image), imagesy($image)]);"],
            input=body, timeout=60,
        )
        assert json.loads(dimensions) == [120, 80], ("Thumbnail dimensions", thumb, dimensions)
    for kind in ("php-tar", "shell-tar", "shell-zip"):
        print("Checking " + kind, flush=True)
        status, body = request("/_h5ai/public/index.php", {
            "action": "download", "type": kind, "as": "sample", "baseHref": "/",
            "hrefs": ["/sample.txt"],
        })
        assert status == 200, status
        archive = zipfile.ZipFile(io.BytesIO(body)) if kind == "shell-zip" else tarfile.open(fileobj=io.BytesIO(body))
        with archive:
            content = archive.read("sample.txt") if kind == "shell-zip" else archive.extractfile("sample.txt").read()
            assert content == b"h5ai smoke\n", kind

    options = "/config/h5ai/_h5ai/private/conf/options.json"
    docker("exec", name, "sh", "-c", "printf '\\n// smoke: preserve custom config\\n' >> " + options)
    before = docker("exec", name, "sha256sum", options)
    docker("rm", "-f", name)
    start(auth=True, timezone="UTC")
    assert request()[0] == 401 and request("/sample.txt")[0] == 401
    assert request("/sample.txt", auth=True) == (200, b"h5ai smoke\n")
    assert api({"action": "login", "pass": ""}, auth=True)["asAdmin"]
    setup = api({"action": "get", "setup": True, "refresh": True}, auth=True)["setup"]
    assert setup["AS_ADMIN"] and setup["PHP_VERSION"] == cli, ("Persisted login session", setup)
    assert docker("exec", name, "sha256sum", options) == before
    assert docker("exec", name, "stat", "-c", "%u:%g", options) == "1234:2345"
    assert json.loads(request("/runtime.php", auth=True)[1])["timezone"] == "UTC"
    docker("rm", "-f", name)
    start()
    assert request("/sample.txt") == (200, b"h5ai smoke\n")
    print(json.dumps({"image": image, "platform": platform, "php": cli,
                      "jit": runtime["opcache"].get("jit"), "result": "PASS"}))
except BaseException:
    best_effort_docker("logs", "--tail", "100", name)
    best_effort_docker("exec", name, "sh", "-c", "cat /var/log/php*/error.log 2>/dev/null; ps")
    raise
finally:
    best_effort_docker("rm", "-fv", name, quiet=True)
    for volume in volumes:
        best_effort_docker("volume", "rm", volume, quiet=True)
