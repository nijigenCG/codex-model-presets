"""Exercise the actual patched app with a separate Electron profile."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

app = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="codex-preset-startup-") as directory:
    profile = Path(directory) / "profile"
    log_path = Path(directory) / "startup.log"
    env = dict(os.environ, CODEX_ELECTRON_USER_DATA_PATH=str(profile))
    with log_path.open("wb") as log:
        process = subprocess.Popen(
            [str(app / "Contents/MacOS/ChatGPT"), "--user-data-dir=" + str(profile)],
            env=env, stdout=log, stderr=log, start_new_session=True,
        )
        try:
            try:
                code = process.wait(timeout=15)
                raise RuntimeError(f"补丁应用提前退出：{code}")
            except subprocess.TimeoutExpired:
                output = log_path.read_text(errors="replace")
                for evidence in ["window main frame finished load", "window ready-to-show", "React root render requested"]:
                    if evidence not in output:
                        raise RuntimeError(f"缺少启动证据：{evidence}")
                for failure in ["FATAL:", "different Team IDs", "main_window_load_failed", "render-process-gone"]:
                    if failure in output:
                        raise RuntimeError(f"启动日志包含故障：{failure}")
        except Exception:
            print(log_path.read_text(errors="replace")[-8000:], file=sys.stderr)
            raise
        finally:
            # Only stop this test's process group; leave the official app running.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            if process.poll() is None:
                process.wait(timeout=5)
            # Crashpad detaches into its own group. Stop only this copy's helpers.
            processes = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
            for line in processes.splitlines():
                pid, command = line.strip().split(None, 1)
                if command.startswith(str(app) + "/Contents/"):
                    try:
                        os.kill(int(pid), signal.SIGTERM)
                    except ProcessLookupError:
                        pass
    print("隔离副本运行 15 秒，主窗口加载、ready-to-show 和 React 渲染启动验证通过。")
