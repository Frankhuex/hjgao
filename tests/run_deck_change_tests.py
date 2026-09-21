"""Run isolated Godot 4.7.2 parser and localhost deck-change regression tests."""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
GODOT = "/Applications/Godot 4.7.2.app/Contents/MacOS/Godot"
COMMAND = [GODOT, "--headless", "--path", str(ROOT), "--script",
           "res://tests/deck_change_test.gd"]


def run(role):
    result = subprocess.run(COMMAND + ["--", role], cwd=ROOT,
                            capture_output=True, text=True, timeout=40)
    print(result.stdout, result.stderr, flush=True)
    assert result.returncode == 0, role
    assert role.upper() + "_OK" in result.stdout, role


run("parser")
host = subprocess.Popen(COMMAND + ["--", "host"], cwd=ROOT,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
watch = None
try:
    for line in host.stdout:
        print(line, end="", flush=True)
        if "HOST_READY" in line:
            break
    else:
        raise RuntimeError("Host did not start")
    watch = subprocess.Popen(COMMAND + ["--", "watch"], cwd=ROOT,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in watch.stdout:
        print(line, end="", flush=True)
        if "WATCH_CONNECTED" in line:
            break
    else:
        raise RuntimeError("Observer did not connect")
    run("upload")
    output, _ = watch.communicate(timeout=20)
    print(output, flush=True)
    assert watch.returncode == 0 and "WATCH_OK" in output
    run("late")
    output, _ = host.communicate(timeout=30)
    print(output, flush=True)
    assert host.returncode == 0 and "HOST_CHANGE_OK" in output
finally:
    if watch is not None and watch.poll() is None:
        watch.terminate()
        watch.wait(timeout=5)
    if host.poll() is None:
        host.terminate()
        host.wait(timeout=5)
