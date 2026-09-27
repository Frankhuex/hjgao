"""Run isolated Godot 4.7.2 chat parser and localhost multiplayer tests."""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
GODOT = "/Applications/Godot 4.7.2.app/Contents/MacOS/Godot"
COMMAND = [GODOT, "--headless", "--path", str(ROOT), "--script",
           "res://tests/chat_test.gd"]


def run(role):
    result = subprocess.run(COMMAND + ["--", role], cwd=ROOT,
                            capture_output=True, text=True, timeout=45)
    print(result.stdout, result.stderr, flush=True)
    assert result.returncode == 0, role
    assert role.upper() + "_OK" in result.stdout, role


run("parser")
host = subprocess.Popen(COMMAND + ["--", "host"], cwd=ROOT,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
host_output = []
try:
    for line in host.stdout:
        host_output.append(line)
        print(line, end="", flush=True)
        if "HOST_READY" in line:
            break
    else:
        raise RuntimeError("Host did not start")

    run("client")
    for line in host.stdout:
        host_output.append(line)
        print(line, end="", flush=True)
        if "HOST_CLIENT_LEFT" in line:
            break
    else:
        raise RuntimeError("Client did not leave")

    run("late")
    output, _ = host.communicate(timeout=30)
    host_output.append(output)
    print(output, flush=True)
    assert host.returncode == 0, "host"
    all_output = "".join(host_output)
    assert "HOST_CHAT_OK" in all_output, "host chat"
    assert "HOST_LATE_OK" in all_output, "host late"
finally:
    if host.poll() is None:
        host.terminate()
        host.wait(timeout=5)
