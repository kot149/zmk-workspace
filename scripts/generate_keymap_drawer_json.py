#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path


def load_text(input_path, dts_include_dirs=(), _visited=None):
    if _visited is None:
        _visited = set()
    resolved = input_path.resolve()
    if resolved in _visited:
        return ""
    _visited.add(resolved)
    text = input_path.read_text()
    parts = [text]
    for m in re.finditer(r'#include\s+"([^"]+)"', text):
        inc = input_path.parent / m.group(1)
        if inc.exists():
            parts.append(load_text(inc, dts_include_dirs, _visited))
    for m in re.finditer(r'#include\s+<([^>]+)>', text):
        for search_dir in dts_include_dirs:
            inc = Path(search_dir) / m.group(1)
            if inc.exists():
                parts.append(load_text(inc, dts_include_dirs, _visited))
                break
    return "\n".join(parts)


def detect_layout_label(text):
    match = re.search(r'zmk,physical-layout\s*=\s*(?:<\s*)?&([A-Za-z0-9_]+)\s*[>;]', text)
    if not match:
        raise SystemExit("Could not auto-detect physical layout label (no zmk,physical-layout = &<label> found)")
    return match.group(1)


def find_labeled_block(text, label):
    match = re.search(rf"\b{re.escape(label)}\s*:\s*[A-Za-z0-9_,@-]+\s*\{{", text)
    if not match:
        raise SystemExit(f"Could not find node label: {label}")

    start = match.end()
    depth = 1
    index = start
    while index < len(text) and depth:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1

    if depth:
        raise SystemExit(f"Unclosed node block for label: {label}")
    return text[start : index - 1]


def clean_number(value):
    number = int(value)
    scaled = number / 100
    return int(scaled) if scaled.is_integer() else scaled


_NUM = r"\(?\s*(-?\d+)\s*\)?"


def parse_key_attrs(layout_block):
    keys_match = re.search(r"\bkeys\b.*?=\s*(.*?);", layout_block, re.S)
    if not keys_match:
        raise SystemExit("Could not find physical layout keys")

    attrs = []
    for match in re.finditer(
        rf"<\s*&key_physical_attrs\s+{_NUM}\s+{_NUM}\s+{_NUM}\s+{_NUM}\s+{_NUM}\s+{_NUM}\s+{_NUM}\s*>",
        keys_match.group(1),
    ):
        width, height, x, y, rotation, rx, ry = map(int, match.groups())
        key = {
            "x": clean_number(x),
            "y": clean_number(y),
        }
        if width != 100:
            key["w"] = clean_number(width)
        if height != 100:
            key["h"] = clean_number(height)
        if rotation != 0:
            key["r"] = clean_number(rotation)
            key["rx"] = clean_number(rx)
            key["ry"] = clean_number(ry)
        attrs.append(key)

    if not attrs:
        raise SystemExit("No key_physical_attrs entries found")
    return attrs


def parse_transform_positions(text, layout_block):
    transform_match = re.search(r"transform\s*=\s*<\s*&([A-Za-z0-9_]+)\s*>", layout_block)
    if not transform_match:
        return []

    transform_block = find_labeled_block(text, transform_match.group(1))
    map_match = re.search(r"\bmap\b\s*=\s*<(.*?)>;", transform_block, re.S)
    if not map_match:
        return []

    return [
        {"row": int(row), "col": int(col)}
        for row, col in re.findall(r"RC\(\s*(\d+)\s*,\s*(\d+)\s*\)", map_match.group(1))
    ]


def generate(input_path, output_path, layout_name, keyboard_id, keyboard_name, dts_include_dirs=()):
    text = load_text(input_path, dts_include_dirs)
    if not layout_name:
        layout_name = detect_layout_label(text)
    layout_block = find_labeled_block(text, layout_name)
    keys = parse_key_attrs(layout_block)
    positions = parse_transform_positions(text, layout_block)

    if positions and len(positions) != len(keys):
        raise SystemExit(
            f"Transform position count ({len(positions)}) does not match key count ({len(keys)})"
        )

    for index, key in enumerate(keys):
        if positions:
            key.update(positions[index])

    if output_path.exists():
        data = json.loads(output_path.read_text())
    else:
        data = {}

    data["id"] = data.get("id") or keyboard_id
    data["name"] = data.get("name") or keyboard_name
    data.setdefault("layouts", {})
    data["layouts"][layout_name] = {"layout": keys}

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(data, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Generate keymap-drawer/QMK info JSON from a ZMK physical layout."
    )
    parser.add_argument("input", type=Path, help="ZMK .dtsi/.overlay containing zmk,physical-layout")
    parser.add_argument("output", type=Path, help="JSON file to write")
    parser.add_argument("--layout", default=None, help="Physical layout node label (auto-detected if omitted)")
    parser.add_argument("--id", default=None, help="Keyboard id for new JSON files")
    parser.add_argument("--name", default=None, help="Keyboard name for new JSON files")
    parser.add_argument("--dts-include-dirs", nargs="*", default=[], metavar="DIR",
                        help="Directories to search for angle-bracket DTS includes")
    args = parser.parse_args()

    keyboard_id = args.id or args.output.stem
    keyboard_name = args.name or keyboard_id
    generate(args.input, args.output, args.layout, keyboard_id, keyboard_name, args.dts_include_dirs)


if __name__ == "__main__":
    main()
