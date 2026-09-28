"""Run isolated Godot 4.7.2 counter parser and localhost multiplayer tests."""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
GODOT = "/Applications/Godot 4.7.2.app/Contents/MacOS/Godot"
COMMAND = [GODOT, "--headless", "--path", str(ROOT), "--script",
           "res://tests/counter_test.gd"]


def run(role, marker=None):
    result = subprocess.run(COMMAND + ["--", role], cwd=ROOT,
                            capture_output=True, text=True, timeout=90)
    print(result.stdout, result.stderr, flush=True)
    assert result.returncode == 0, role
    assert (marker or role.upper() + "_OK") in result.stdout, role


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

    run("client")  # 玩家二：3D 按钮/拖动/查看器全流程
    for line in host.stdout:
        host_output.append(line)
        print(line, end="", flush=True)
        if "HOST_PHASE1_OK" in line:
            break
    else:
        raise RuntimeError("Phase 1 did not finish")

    run("late_join", marker="CLIENT_OK")  # 玩家三：晚加入状态补齐
    for line in host.stdout:
        host_output.append(line)
        print(line, end="", flush=True)
        if "HOST_COUNTERS_OK" in line:
            break
    else:
        raise RuntimeError("Clear counters did not finish")

    # 注意：不要用 communicate()——for 行迭代器的预读缓冲区里可能还压着
    # HOST_ALL_OK 等已读走的行，communicate 读底层 fd 会把它们丢掉；
    # 用同一个文件对象 read() 排空即可。
    rest = host.stdout.read()
    host_output.append(rest)
    print(rest, flush=True)
    host.wait(timeout=30)
    assert host.returncode == 0, "host"
    all_output = "".join(host_output)
    assert "HOST_MUTEX_OK" in all_output, "host mutex"
    assert "HOST_ALL_OK" in all_output, "host all"
finally:
    if host.poll() is None:
        host.terminate()
        host.wait(timeout=5)
