#!/usr/bin/env python3
"""Write Finder layout for the release disk image."""

import datetime
import sys
from pathlib import Path

from ds_store import DSStore
from mac_alias import (
    ALIAS_EJECTABLE_DISK,
    ALIAS_HFS_VOLUME_SIGNATURE,
    ALIAS_KIND_FILE,
    ALIAS_NO_CNID,
    Alias,
    TargetInfo,
    VolumeInfo,
)

VOLUME_NAME = "Dict Local AI"
APP_NAME = "Dict Local AI.app"
BACKGROUND_PATH = "/.background/background.png"


def write_layout(path: Path) -> None:
    # Finder resolves this alias from the final volume.
    stamp = datetime.datetime(2000, 1, 1, tzinfo=datetime.timezone.utc)
    volume = VolumeInfo(
        name=VOLUME_NAME,
        creation_date=stamp,
        fs_type=ALIAS_HFS_VOLUME_SIGNATURE,
        disk_type=ALIAS_EJECTABLE_DISK,
        attribute_flags=0,
        fs_id=b"\x00\x00",
        posix_path=f"/Volumes/{VOLUME_NAME}",
    )
    target = TargetInfo(
        kind=ALIAS_KIND_FILE,
        filename="background.png",
        folder_cnid=ALIAS_NO_CNID,
        cnid=ALIAS_NO_CNID,
        creation_date=stamp,
        creator_code=b"\x00\x00\x00\x00",
        type_code=b"\x00\x00\x00\x00",
        folder_name=None,
        posix_path=BACKGROUND_PATH,
        carbon_path=f"{VOLUME_NAME}:.background:background.png",
    )
    background_alias = Alias(volume=volume, target=target).to_bytes()

    with DSStore.open(str(path), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = {
            "WindowBounds": "{{180, 120}, {760, 440}}",
            "ShowStatusBar": False,
            "ContainerShowSidebar": False,
            "PreviewPaneVisibility": False,
            "SidebarWidth": 180,
            "ShowTabView": False,
            "ShowToolbar": False,
            "ShowPathbar": False,
            "ShowSidebar": False,
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1,
            "backgroundType": 2,
            "backgroundImageAlias": background_alias,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
            "arrangeBy": "none",
            "showIconPreview": True,
            "showItemInfo": False,
            "labelOnBottom": True,
            "textSize": 14.0,
            "iconSize": 112.0,
            "backgroundColorRed": 1.0,
            "backgroundColorGreen": 1.0,
            "backgroundColorBlue": 1.0,
        }
        store["."]["icvl"] = (b"type", b"icnv")
        store[APP_NAME]["Iloc"] = (165, 220)
        store["Applications"]["Iloc"] = (580, 220)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: write-dmg-layout.py OUTPUT_DS_STORE")
    write_layout(Path(sys.argv[1]))
