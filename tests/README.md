# Container smoke test

`smoke.py` checks the built Docker image as a running Nginx/PHP-FPM service.
Use it when changing the base image, PHP packages or extensions, startup script, Nginx/FPM configuration, or bundled h5ai code.
These changes can build successfully while breaking file serving, authentication, media processing, or persisted settings.
Documentation-only changes, screenshots, and commit-message edits do not need an additional local container test run.

The [GitHub Actions workflow](../.github/workflows/buildx.yml) runs this script on pull requests targeting `master` and pushes to `master`.
It tests amd64 and ARM64 on their native Ubuntu runners, and ARMv7/ARMv6 with QEMU on amd64.
Every platform must pass before a `master` push can start the Docker Hub publish job.
Pull requests do not receive Docker Hub credentials or publish images.
On a `master` push, changes limited to `README.md`, `docs/**`, `tests/README.md`, or `.github/workflows/dockerhub-description.yml` skip container tests and image publishing.

The publish job builds the four-platform image from the tested source revision; it does not promote the exact image digests loaded by the test jobs.
Use the local commands below for focused feedback before pushing or to diagnose a CI failure.
A successful build alone is not evidence that the service works.

## What the test protects

| Contract | Observable check | Regression it catches |
| --- | --- | --- |
| Container startup and PHP routing | CLI starts without configuration warnings; Nginx serves h5ai and an FPM probe | Invalid INI, stopped FPM, or broken FastCGI routing |
| Runtime compatibility | CLI/FPM versions agree; FPM meets the security floor and loads required extensions | A stale FPM binary or omitted/misconfigured PHP extension |
| Configured acceleration | OPcache runs; JIT is on for amd64 and arm64 | Lost acceleration configuration on the supported 64-bit targets |
| File browsing and download | The listing includes the fixture's exact href; HTTP returns its original bytes | Missing files or incorrect document-root mapping |
| Image and video thumbnails | Every requested thumbnail returns HTTP 200 and a decodable 120×80 JPEG | Empty/partial responses, broken media tools, or failed resizing |
| Packaged download | PHP tar, shell tar, and shell zip contain the original fixture bytes | Broken archive generation or corrupted downloads |
| Authentication and sessions | Anonymous requests receive 401; credentials allow access; admin login persists into the next request | Missing Basic Auth or broken PHP session persistence |
| Configuration reuse | Customized options keep their hash after recreation; ownership matches PUID/PGID; FPM reads the new timezone | Overwritten settings, incorrect file ownership, or stale timezone configuration |
| Authentication removal | Recreating the container with authentication off restores anonymous downloads | A stale authentication patch in the persisted Nginx configuration |

The HTTP and process boundaries are intentional: mocks cannot detect a missing package or a service that fails to start.
The script uses Python's standard library and the image's existing PHP/GD and FFmpeg tools, with no separate test framework.
The PHP probe and media fixtures exist only in disposable test volumes; they are not shipped in the image.

## Run

Requirements: Python 3, Docker CLI, a running local Docker daemon, and a built image for the selected platform.
Use normal Python execution; `-O` and `PYTHONOPTIMIZE` are rejected because they remove assertions.
The script connects to Docker's loopback-published port, so a remote Docker context requires running the script on that Docker host.

From the repository root, for native amd64:

```bash
docker buildx build --pull --no-cache --platform linux/amd64 --load -t h5ai:test-amd64 .
python3 tests/smoke.py h5ai:test-amd64 linux/amd64
```

For native ARM64, run on an ARM64 Docker host:

```bash
docker buildx build --pull --no-cache --platform linux/arm64 --load -t h5ai:test-arm64 .
python3 tests/smoke.py h5ai:test-arm64 linux/arm64
```

Use `linux/arm/v7` or `linux/arm/v6` in both commands when validating those published variants.
Prefer native execution for platform-specific behavior; see the QEMU limitation below.
Testing one platform does not establish that another works.

Exit status `0` and a final `"result": "PASS"` mean all checks completed.
Any assertion, verification command failure, or HTTP timeout fails the run and prints diagnostics.
The script creates uniquely named `h5ai-smoke-*` containers and volumes, binds HTTP only to `127.0.0.1`, and attempts to clean up its resources on exit.
Diagnostic or cleanup errors are printed without replacing the original test failure or preventing the remaining cleanup commands.
It does not mount existing user data or configuration.
If the process is forcibly killed or the Docker daemon becomes unavailable, remove only the test resources named in that failed run after restoring Docker access.

## Runtime version policy

The test deliberately does not pin an exact Alpine, Nginx, or h5ai release, and uses the image's `php` command instead of a version-suffixed executable.
Compatible runtime updates should pass without changing functional assertions.
Published API routes, fixture contents, requested thumbnail dimensions, and environment-variable effects remain explicit expectations because those are the behavior being checked.

`MIN_PHP_VERSION_ID = 80512` is a security requirement, not a snapshot of the installed patch release.
PHP 8.5.12 fixes the two vulnerabilities in the [2026-10-21 security release](https://www.php.net/archive/2026.php#2026-10-21-5).
The Dockerfile enforces the package minimum; this test independently verifies the PHP actually serving HTTP.
Raise the floor when the project's security requirement changes, not merely to match the newest installed patch.
The check is not a vulnerability scanner and does not certify future security advisories.

The [2026-10-23 session upload progress advisory](https://www.php.net/archive/2026.php) applies when all three conditions hold:

- Configuration initially selects `php_binary` or `php_serialize` as `session.serialize_handler`.
- Application code changes it to `php` with `ini_set()` before `session_start()`.
- Session upload progress is enabled.

Bundled h5ai does not switch the serializer at runtime, so the image leaves the upstream upload-progress setting unchanged.
The reusable test verifies session behavior through login; it does not freeze PHP's upstream defaults as application requirements.
Assess custom PHP pages separately and follow the advisory's startup-configuration mitigation if they meet its conditions.
PHP and Imagick use Alpine's community repository, whose regular support lasts until the next stable Alpine release; track the [Alpine support policy](https://alpinelinux.org/releases/) during future upgrades.

## Known limitations

- **ARM64 under QEMU:** the 2026-10-26 investigation reproduced a tracing-JIT stall with the default multi-worker FPM pool on QEMU 10.2.3. Single-worker FPM and function-JIT controls passed. A separate C experiment reproduced stale shared executable code without PHP, supporting an emulator cache-invalidation diagnosis. That one-off emulator diagnostic is not part of the maintained application suite. The smoke test retains the actual JIT and archive checks and does not skip or relabel this failure; the workflow uses a native ARM64 runner for that check. A configured CI job is not evidence that it has already run successfully.
- **Data migration:** recreation uses synthetic customized configuration from the same image. It does not test arbitrary older installations or real production volumes. Back up `/config` and validate a copy for a deployment-specific migration.
- **Media scope:** PNG and MP4 fixtures exercise image and video thumbnails. PDF/PostScript rendering, every media format, and ImageMagick policy compatibility are not covered. A green h5ai info-page dependency check is not a PDF-rendering test.
- **UI and deployment:** HTTP success does not verify browser layout, TLS/reverse-proxy configuration, published registry images, or production rollout.

## Maintaining the test

Keep a check only if it catches a realistic failure in a contract above.
Do not copy new Dockerfile version strings into assertions, add checks of QEMU internals, or introduce a test framework just to split this scenario.
When h5ai intentionally changes its API or the image's supported features change, update the affected assertion and this contract table together.
Never weaken a feature assertion solely to make an emulated run pass.

For assertion changes, prove that a broken response is rejected before accepting a passing run.
For example, a thumbnail response of `[]` or one thumbnail for two requests must fail before any download loop can report success.
After the script stabilizes, run the full scenario on each affected, available platform and report unavailable native hardware separately.
