"""Client for the in-game AgentHarness (scripts/test/AgentHarness.gd).

Launch the game with the harness armed, then drive it from here:

    godot --path . res://scenes/main/Main.tscn --agent-harness &
    python scripts/test/agent_client.py wait-up
    python scripts/test/agent_client.py labels
    python scripts/test/agent_client.py click --text "Tech Tree..."
    python scripts/test/agent_client.py wheel in --steps 30
    python scripts/test/agent_client.py shot out.png --rect 0 0 1920 110
    python scripts/test/agent_client.py shot map.png --world

INPUT coordinates (click/hover/drag/wheel) are VIEWPORT space (1280x720),
matching the rects that `labels` and `buttons` report. Screenshots come back
in WINDOW pixels (1920x1080), and `shot --rect` is in those WINDOW pixels too
-- it crops the saved image, not the viewport. Divide an image pixel by the
reported `scale` to get a clickable point, and multiply a reported rect by it
to get a crop.
Prefer `click --text` over raw coordinates wherever a button has a label —
it reads the on-screen rect and aims at its centre, so it cannot drift when
the layout moves.
"""

import argparse
import json
import socket
import sys
import time

HOST, PORT = "127.0.0.1", 8899


class Harness:
    def __init__(self, timeout: float = 120.0) -> None:
        self._sock = socket.create_connection((HOST, PORT), timeout=timeout)
        self._buf = b""

    def send(self, **command):
        self._sock.sendall((json.dumps(command) + "\n").encode())
        while b"\n" not in self._buf:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise ConnectionError("game closed the connection")
            self._buf += chunk
        line, self._buf = self._buf.split(b"\n", 1)
        return json.loads(line.decode())

    def world_rect(self):
        """Image-pixel rect of the map between the two HUD panels.

        A full frame is mostly HUD when the subject is terrain -- the build
        menu alone takes the bottom third -- so a terrain screenshot cropped
        to this is several times more map per pixel.

        Found by looking for the densest ROW of HUD text rather than by
        hardcoding pixel bands, so it follows the layout instead of going
        stale the next time the HUD moves. A panel packs many items onto one
        y; things floating over the map do not. That distinction is what makes
        this work: the speed buttons, Menu, Tech Tree and the date readout all
        sit over terrain and must NOT be cropped to, while the resource bar's
        figures and the build menu's category headings each share one exact y.

        Uses labels as well as buttons because the build menu's icons are not
        Buttons -- `buttons` reports 8 items for the whole HUD and none of
        them are in the bottom half, so a button-only rule silently keeps the
        entire build menu in frame.
        """
        debug = self.send(cmd="debug")
        # Derived from the two sizes debug actually reports. `scale` appears
        # only in the screenshot response, and reading it off `debug` silently
        # yields 1.0 -- which crops a 1280-wide region out of a 1920-wide
        # image and loses the right third of the map.
        width, height = (int(v) for v in debug["window_size"])
        viewport_size = debug["viewport_size"]
        scale = width / (float(viewport_size[0]) or width)
        viewport_height = float(viewport_size[1]) or height

        items = [item["rect"] for item in self.send(cmd="labels")["labels"]]
        items += [item["rect"] for item in self.send(cmd="buttons")["buttons"]]

        def densest_row(candidates):
            """(y, height) of the y shared by the most items, or None."""
            rows = {}
            for x, y, w, h in candidates:
                rows.setdefault(y, []).append(h)
            if not rows:
                return None
            y = max(rows, key=lambda k: len(rows[k]))
            if len(rows[y]) < 3:
                return None
            return y, max(rows[y])

        top_row = densest_row([r for r in items if r[1] < viewport_height * 0.2])
        bottom_row = densest_row([r for r in items if r[1] > viewport_height * 0.5])
        if top_row is None or bottom_row is None:
            return [0, 0, width, height]

        # One row-height of margin past each: a panel's own padding and border
        # extend beyond the text it contains, and leaving a sliver of panel in
        # frame looks like a rendering fault rather than a crop.
        top = int((top_row[0] + top_row[1] * 2) * scale)
        bottom = int((bottom_row[0] - bottom_row[1]) * scale)
        if bottom - top < height * 0.2:
            return [0, 0, width, height]
        return [0, top, width, bottom - top]

    def click_text(self, text: str):
        """Click the button whose visible label matches, by its own rect."""
        for button in self.send(cmd="buttons")["buttons"]:
            if button["text"] == text:
                x, y, w, h = button["rect"]
                if button["disabled"]:
                    return {"ok": False, "error": f"button {text!r} is disabled"}
                return self.send(cmd="click", x=x + w // 2, y=y + h // 2)
        return {"ok": False, "error": f"no visible button labelled {text!r}"}


def wait_up(seconds: int = 120) -> int:
    """Block until the harness accepts connections; map generation is slow."""
    for attempt in range(seconds):
        try:
            socket.create_connection((HOST, PORT), timeout=2).close()
            print(f"harness up after {attempt}s")
            return 0
        except OSError:
            time.sleep(1)
    print("timed out waiting for the harness", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)

    sub.add_parser("wait-up")
    sub.add_parser("labels")
    sub.add_parser("buttons")
    sub.add_parser("screen")
    sub.add_parser("quit")

    click = sub.add_parser("click")
    click.add_argument("--text")
    click.add_argument("--x", type=int)
    click.add_argument("--y", type=int)
    click.add_argument("--button", default="left")

    hover = sub.add_parser("hover")
    hover.add_argument("x", type=int)
    hover.add_argument("y", type=int)

    shot = sub.add_parser("shot")
    shot.add_argument("path")
    shot.add_argument("--rect", nargs=4, type=int, metavar=("X", "Y", "W", "H"),
                      help="crop rect in IMAGE pixels (1920x1080), not viewport space")
    shot.add_argument(
        "--world",
        action="store_true",
        help="crop to the world area between the top resource bar and the bottom "
        "build menu, so a terrain screenshot is terrain rather than mostly HUD",
    )

    key = sub.add_parser("key")
    key.add_argument("name")
    key.add_argument(
        "--hold",
        type=float,
        default=0.0,
        help="seconds to hold the key down; required for camera panning "
        "(WASD/arrows), which integrates movement per frame while held",
    )

    wheel = sub.add_parser("wheel")
    wheel.add_argument("direction", choices=("in", "out"))
    wheel.add_argument("--steps", type=int, default=1)
    wheel.add_argument("--x", type=int, default=640)
    wheel.add_argument("--y", type=int, default=360)

    wait = sub.add_parser("wait")
    wait.add_argument("seconds", type=float)

    args = parser.parse_args()
    if args.action == "wait-up":
        return wait_up()

    harness = Harness()
    if args.action == "click":
        if args.text:
            result = harness.click_text(args.text)
        elif args.x is not None and args.y is not None:
            result = harness.send(cmd="click", x=args.x, y=args.y, button=args.button)
        else:
            print("click needs --text or both --x and --y", file=sys.stderr)
            return 2
    elif args.action == "hover":
        result = harness.send(cmd="hover", x=args.x, y=args.y)
    elif args.action == "shot":
        payload = {"cmd": "screenshot", "path": args.path}
        if args.world:
            payload["rect"] = harness.world_rect()
        elif args.rect:
            payload["rect"] = args.rect
        result = harness.send(**payload)
    elif args.action == "key":
        result = harness.send(cmd="key", key=args.name, hold=args.hold)
    elif args.action == "wheel":
        result = harness.send(
            cmd="wheel", up=args.direction == "in", steps=args.steps, x=args.x, y=args.y)
    elif args.action == "wait":
        result = harness.send(cmd="wait", seconds=args.seconds)
    elif args.action == "screen":
        result = harness.send(cmd="debug")
    else:
        result = harness.send(cmd=args.action)

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("ok", True) else 1


if __name__ == "__main__":
    raise SystemExit(main())
