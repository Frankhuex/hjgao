"""Exercise pending-card classification into synchronized new piles in real localhost peers."""
import pathlib
import subprocess
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
COMMAND = ["/Applications/Godot 4.7.2.app/Contents/MacOS/Godot", "--headless",
           "--path", str(ROOT), "--script", "res://tests/pile_classify_test.gd"]


def run(role):
    result = subprocess.run(COMMAND + ["--", role], cwd=ROOT, capture_output=True,
                            text=True, timeout=50)
    print(result.stdout, result.stderr, flush=True)
    assert result.returncode == 0 and role.upper() + "_OK" in result.stdout, role
    assert "SCRIPT ERROR" not in result.stdout + result.stderr, role


run("parser")
host = subprocess.Popen(COMMAND + ["--", "host"], cwd=ROOT,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
ready = threading.Event()
phase = threading.Event()
output = []


def read_host():
    for line in host.stdout:
        output.append(line)
        print(line, end="", flush=True)
        if "HOST_READY" in line:
            ready.set()
        if "HOST_PHASE_OK" in line:
            phase.set()


reader = threading.Thread(target=read_host, daemon=True)
reader.start()
try:
    assert ready.wait(15), "host startup"
    run("client")
    assert phase.wait(15), "host client phase"
    run("late_join")
    host.wait(timeout=15)
    reader.join(timeout=5)
    assert host.returncode == 0 and "HOST_OK" in "".join(output), "host completion"
    assert "SCRIPT ERROR" not in "".join(output), "host script errors"
finally:
    if host.poll() is None:
        host.terminate()
        host.wait(timeout=5)
