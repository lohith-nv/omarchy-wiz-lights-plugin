import concurrent.futures as futures
import json
import os
import socket
import sys
import tempfile
import time

PORT = 38899
STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "wiz-lights",
)
STATE_FILE = os.path.join(STATE_DIR, "lights.json")

MAX_LIGHTS = 64
MAX_STATE_BYTES = 1 << 20
MAX_FIELD_LEN = 128


def udp_call(ip, payload, timeout=1.0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(json.dumps(payload).encode(), (ip, PORT))
        data, _ = sock.recvfrom(4096)
        return json.loads(data.decode())
    finally:
        sock.close()


def pilot(ip, retries=1):
    for attempt in range(retries + 1):
        try:
            resp = udp_call(ip, {"method": "getPilot", "params": {}}, timeout=1.0)
            return resp.get("result")
        except (OSError, ValueError):
            continue
    return None


def clean_entry(entry):
    if not isinstance(entry, dict):
        return None
    mac = entry.get("mac")
    ip = entry.get("ip")
    if not isinstance(mac, str) or not isinstance(ip, str) or not mac or not ip:
        return None
    mac = mac[:MAX_FIELD_LEN]
    ip = ip[:MAX_FIELD_LEN]
    name = entry.get("name")
    name = name[:MAX_FIELD_LEN] if isinstance(name, str) else ""
    module = entry.get("moduleName")
    module = module[:MAX_FIELD_LEN] if isinstance(module, str) else ""
    return {"mac": mac, "ip": ip, "name": name, "moduleName": module}


def load_state():
    try:
        fd = os.open(STATE_FILE, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return []
    try:
        with os.fdopen(fd, "rb") as fh:
            raw = fh.read(MAX_STATE_BYTES + 1)
    except OSError:
        return []
    if len(raw) > MAX_STATE_BYTES:
        return []
    try:
        data = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return []
    if not isinstance(data, dict) or not isinstance(data.get("lights"), list):
        return []
    entries = []
    for entry in data["lights"][:MAX_LIGHTS]:
        cleaned = clean_entry(entry)
        if cleaned:
            entries.append(cleaned)
    return entries


def save_state(lights):
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    bounded = [clean_entry(entry) for entry in lights[:MAX_LIGHTS]]
    bounded = [entry for entry in bounded if entry]
    fd, tmp = tempfile.mkstemp(prefix="lights.", suffix=".tmp", dir=STATE_DIR)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"lights": bounded}, fh, indent=2)
            fh.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, STATE_FILE)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def default_name(entry):
    module = str(entry.get("moduleName") or "").upper()
    mac = str(entry.get("mac") or "")
    suffix = mac[-4:].upper() if len(mac) >= 4 else ""
    base = "Color Light" if "RGB" in module else "WiZ Light"
    return (base + " " + suffix).strip()


def merge_discovered(saved, found):
    by_mac = {}
    for entry in saved[:MAX_LIGHTS]:
        by_mac[entry["mac"]] = dict(entry)
    for item in found[:MAX_LIGHTS]:
        existing = by_mac.get(item["mac"], {})
        by_mac[item["mac"]] = {
            "mac": item["mac"],
            "ip": item["ip"],
            "name": existing.get("name") or default_name(item),
            "moduleName": item.get("moduleName") or existing.get("moduleName") or "",
        }
    return [by_mac[key] for key in sorted(by_mac)][:MAX_LIGHTS]


def local_ipv4():
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        return probe.getsockname()[0]
    except OSError:
        return None
    finally:
        probe.close()


def broadcast_targets():
    targets = ["255.255.255.255"]
    local = local_ipv4()
    if local and not local.startswith("127."):
        parts = local.split(".")
        if len(parts) == 4:
            directed = ".".join(parts[:3]) + ".255"
            if directed not in targets:
                targets.insert(0, directed)
    return targets


def discover(timeout=1.5, rounds=3):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", PORT))
    except OSError:
        sock.bind(("0.0.0.0", 0))
    found = {}
    payload = json.dumps({"method": "getSystemConfig", "params": {}}).encode()
    try:
        for _ in range(rounds):
            for target in broadcast_targets():
                try:
                    sock.sendto(payload, (target, PORT))
                except OSError:
                    pass
            deadline = time.time() + timeout
            while True:
                remaining = deadline - time.time()
                if remaining <= 0:
                    break
                sock.settimeout(remaining)
                try:
                    data, addr = sock.recvfrom(4096)
                except socket.timeout:
                    break
                except OSError:
                    continue
                try:
                    resp = json.loads(data.decode())
                except ValueError:
                    continue
                result = resp.get("result")
                if not isinstance(result, dict) or not result.get("mac"):
                    continue
                mac = result["mac"]
                if mac not in found and len(found) < MAX_LIGHTS:
                    found[mac] = {
                        "mac": mac,
                        "ip": addr[0],
                        "moduleName": result.get("moduleName", ""),
                    }
    finally:
        sock.close()
    return list(found.values())


def status_snapshot(entries):
    bounded = entries[:MAX_LIGHTS]

    def query(entry):
        result = pilot(entry["ip"])
        out = dict(entry)
        out["reachable"] = bool(result)
        if result:
            rgb = None
            if "r" in result and "g" in result and "b" in result:
                rgb = [result["r"], result["g"], result["b"]]
            out.update(
                {
                    "state": bool(result.get("state")),
                    "dimming": result.get("dimming"),
                    "temp": result.get("temp"),
                    "rgb": rgb,
                    "mode": "color" if rgb is not None else (
                        "temp" if result.get("temp") else None
                    ),
                    "rssi": result.get("rssi"),
                    "sceneId": result.get("sceneId"),
                }
            )
        else:
            out.update({"state": False})
        return out

    with futures.ThreadPoolExecutor(max_workers=8) as pool:
        return list(pool.map(query, bounded))


def emit(payload):
    sys.stdout.write(json.dumps(payload) + "\n")


def send_color(ip, r, g, b):
    try:
        resp = udp_call(
            ip,
            {"method": "setPilot", "params": {"r": r, "g": g, "b": b}},
            timeout=1.5,
        )
        ok = isinstance(resp.get("result"), dict) and (
            resp["result"].get("success") is True
        )
        hex_value = "#{:02x}{:02x}{:02x}".format(r, g, b)
        emit({"ok": ok, "hex": hex_value} if ok else {"ok": False, "error": "bulb rejected command"})
        return 0 if ok else 1
    except (OSError, ValueError) as exc:
        emit({"ok": False, "error": str(exc)})
        return 1


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"

    if cmd == "status":
        entries = load_state()
        emit({"ok": True, "lights": status_snapshot(entries)})
        return 0

    if cmd == "discover":
        found = discover()
        merged = merge_discovered(load_state(), found)
        save_state(merged)
        snapshot = status_snapshot(merged)
        emit(
            {
                "ok": True,
                "discovered": len(found),
                "total": len(merged),
                "lights": snapshot,
            }
        )
        return 0

    if cmd == "set":
        if len(argv) < 4 or argv[3] not in ("on", "off"):
            emit({"ok": False, "error": "usage: set <ip> <on|off>"})
            return 1
        want_on = argv[3] == "on"
        try:
            resp = udp_call(
                argv[2],
                {"method": "setPilot", "params": {"state": want_on}},
                timeout=1.5,
            )
            ok = isinstance(resp.get("result"), dict) and (
                resp["result"].get("success") is True
            )
            emit({"ok": ok, "state": want_on} if ok else {"ok": False, "error": "bulb rejected command"})
            return 0 if ok else 1
        except (OSError, ValueError) as exc:
            emit({"ok": False, "error": str(exc)})
            return 1

    if cmd == "bright":
        if len(argv) < 3 or argv[2] in ("-h", "--help"):
            emit({"ok": False, "error": "usage: bright <ip> <0-100>"})
            return 1
        try:
            level = max(0, min(100, int(float(argv[3]))))
        except (ValueError, IndexError):
            emit({"ok": False, "error": "invalid brightness"})
            return 1
        try:
            resp = udp_call(
                argv[2],
                {"method": "setPilot", "params": {"dimming": level}},
                timeout=1.5,
            )
            ok = isinstance(resp.get("result"), dict) and (
                resp["result"].get("success") is True
            )
            emit({"ok": ok, "dimming": level} if ok else {"ok": False, "error": "bulb rejected command"})
            return 0 if ok else 1
        except (OSError, ValueError) as exc:
            emit({"ok": False, "error": str(exc)})
            return 1

    if cmd == "temp":
        if len(argv) < 4 or argv[2] in ("-h", "--help"):
            emit({"ok": False, "error": "usage: temp <ip> <2200-6500>"})
            return 1
        try:
            kelvin = int(round(float(argv[3]) / 100.0)) * 100
            kelvin = max(2200, min(6500, kelvin))
        except (ValueError, IndexError):
            emit({"ok": False, "error": "invalid temperature"})
            return 1
        try:
            resp = udp_call(
                argv[2],
                {"method": "setPilot", "params": {"temp": kelvin}},
                timeout=1.5,
            )
            ok = isinstance(resp.get("result"), dict) and (
                resp["result"].get("success") is True
            )
            emit({"ok": ok, "temp": kelvin} if ok else {"ok": False, "error": "bulb rejected command"})
            return 0 if ok else 1
        except (OSError, ValueError) as exc:
            emit({"ok": False, "error": str(exc)})
            return 1

    if cmd == "rgb":
        if len(argv) < 6:
            emit({"ok": False, "error": "usage: rgb <ip> <r> <g> <b>"})
            return 1
        try:
            r, g, b = (max(0, min(255, int(float(v)))) for v in argv[3:6])
        except ValueError:
            emit({"ok": False, "error": "invalid rgb values"})
            return 1
        return send_color(argv[2], r, g, b)

    if cmd == "color":
        if len(argv) < 4:
            emit({"ok": False, "error": "usage: color <ip> <#rrggbb>"})
            return 1
        raw = argv[3].lstrip("#")
        if len(raw) == 3:
            raw = "".join(ch * 2 for ch in raw)
        if len(raw) != 6 or any(ch not in "0123456789abcdefABCDEF" for ch in raw):
            emit({"ok": False, "error": "invalid hex color"})
            return 1
        r = int(raw[0:2], 16)
        g = int(raw[2:4], 16)
        b = int(raw[4:6], 16)
        return send_color(argv[2], r, g, b)

    if cmd == "rename":
        if len(argv) < 4:
            emit({"ok": False, "error": "usage: rename <mac> <name...>"})
            return 1
        mac = argv[2]
        name = " ".join(argv[3:]).strip()[:MAX_FIELD_LEN]
        if not name:
            emit({"ok": False, "error": "empty name"})
            return 1
        entries = load_state()
        for entry in entries:
            if entry.get("mac") == mac:
                entry["name"] = name
        save_state(entries)
        emit({"ok": True})
        return 0

    if cmd == "forget":
        if len(argv) < 3:
            emit({"ok": False, "error": "usage: forget <mac>"})
            return 1
        remaining = [e for e in load_state() if e.get("mac") != argv[2]]
        save_state(remaining)
        emit({"ok": True})
        return 0

    emit({"ok": False, "error": "unknown command: " + cmd})
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
