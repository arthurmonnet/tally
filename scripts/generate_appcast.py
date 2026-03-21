#!/usr/bin/env python3
"""Generate a Sparkle appcast.xml for Tally releases.

Usage:
    python3 scripts/generate_appcast.py \
        --version v0.1.4 \
        --dmg-url https://github.com/arthurmonnet/Tally/releases/download/v0.1.4/Tally.dmg \
        --signature "EdDSA_SIGNATURE_STRING" \
        --length 12345678 \
        --output appcast/appcast.xml

Maintains the last 10 release entries in the appcast for rollback visibility.
"""

import argparse
import os
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"
MIN_SYSTEM_VERSION = "14.0"
MAX_ENTRIES = 10


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Sparkle appcast.xml")
    parser.add_argument("--version", required=True, help="Release tag (e.g. v0.1.4)")
    parser.add_argument("--dmg-url", required=True, help="Direct download URL for the DMG")
    parser.add_argument("--signature", required=True, help="EdDSA signature from sign_update")
    parser.add_argument("--length", required=True, type=int, help="DMG file size in bytes")
    parser.add_argument("--output", default="appcast/appcast.xml", help="Output path")
    return parser.parse_args()


def version_from_tag(tag: str) -> str:
    """Strip leading 'v' from tag to get short version string."""
    return tag.lstrip("v")


def build_item(version_tag: str, dmg_url: str, signature: str, length: int) -> ET.Element:
    short_version = version_from_tag(version_tag)
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")

    item = ET.Element("item")

    title = ET.SubElement(item, "title")
    title.text = f"Version {short_version}"

    pub = ET.SubElement(item, "pubDate")
    pub.text = pub_date

    ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion").text = MIN_SYSTEM_VERSION
    ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = short_version

    # Use the short version string as sparkle:version too (CFBundleVersion)
    # This works because Sparkle compares shortVersionString for display
    ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = short_version

    link = ET.SubElement(
        item,
        "enclosure",
        url=dmg_url,
        length=str(length),
        type="application/octet-stream",
    )
    link.set(f"{{{SPARKLE_NS}}}edSignature", signature)

    return item


def load_or_create_appcast(path: str) -> ET.ElementTree:
    """Load existing appcast or create a fresh one."""
    if os.path.exists(path):
        ET.register_namespace("sparkle", SPARKLE_NS)
        ET.register_namespace("dc", DC_NS)
        return ET.parse(path)

    ET.register_namespace("sparkle", SPARKLE_NS)
    ET.register_namespace("dc", DC_NS)

    rss = ET.Element("rss", version="2.0")

    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Tally Updates"
    ET.SubElement(channel, "link").text = "https://github.com/arthurmonnet/Tally"
    ET.SubElement(channel, "description").text = "Appcast for Tally macOS app"
    ET.SubElement(channel, "language").text = "en"

    return ET.ElementTree(rss)


def main():
    args = parse_args()

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)

    tree = load_or_create_appcast(args.output)
    channel = tree.getroot().find("channel")

    new_item = build_item(args.version, args.dmg_url, args.signature, args.length)

    # Remove existing entry for same version (re-release)
    short_version = version_from_tag(args.version)
    for existing in channel.findall("item"):
        sv = existing.find(f"{{{SPARKLE_NS}}}shortVersionString")
        if sv is not None and sv.text == short_version:
            channel.remove(existing)

    # Insert new item at the top (after metadata elements)
    items = channel.findall("item")
    if items:
        insert_idx = list(channel).index(items[0])
    else:
        insert_idx = len(list(channel))
    channel.insert(insert_idx, new_item)

    # Keep only the last N entries
    all_items = channel.findall("item")
    for old_item in all_items[MAX_ENTRIES:]:
        channel.remove(old_item)

    ET.indent(tree, space="  ")

    with open(args.output, "wb") as f:
        f.write(b'<?xml version="1.0" encoding="utf-8"?>\n')
        tree.write(f, encoding="utf-8", xml_declaration=False)
        f.write(b"\n")

    print(f"Appcast updated: {args.output} ({len(channel.findall('item'))} entries)")


if __name__ == "__main__":
    main()
