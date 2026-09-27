"""Run isolated Godot 4.7.2 player-name parser and localhost multiplayer tests."""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
GODOT = "/Applications/Godot 4.7.2.app/Contents/MacOS/Godot"
COMMAND = [GODOT, "--headless", "--path", str(ROOT), "--script",
           "res://tests/player_name_test.gd"]


def run(role):
    result = subprocess.run(COMMAND + ["--", role], cwd=ROOT,
                            capture_output=True, text=True, timeout=30)
    print(result.stdout, result.stderr, flush=True)
    assert result.returncode == 0, role
    assert role.upper() + "_OK" in result.stdout, role
    return result.stdout


run("parser")
host = subprocess.Popen(COMMAND + ["--", "host"], cwd=ROOT,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
try:
    for line in host.stdout:
        print(line, end="", flush=True)
        if "HOST_READY" in line:
            break
    else:
        raise RuntimeError("Host did not start")

    run("client")
    output, _ = host.communicate(timeout=30)
    print(output, flush=True)
    assert host.returncode == 0, "host"
    assert "HOST_JOIN_OK" in output, "host join"
    assert "HOST_DISCONNECT_OK" in output, "host disconnect"
finally:
    if host.poll() is None:
        host.terminate()
        host.wait(timeout=5)
