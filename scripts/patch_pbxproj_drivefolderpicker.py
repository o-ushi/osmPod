#!/usr/bin/env python3
"""Add DriveFolderPickerView.swift to project.pbxproj"""
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "osmPod.xcodeproj" / "project.pbxproj"
text = PBX.read_text()

if "DriveFolderPickerView.swift" in text:
    print("Already patched")
    raise SystemExit(0)

# --- PBXFileReference ---
text = text.replace(
    "/* End PBXFileReference section */",
    "\t\tCS0000010000000000000006 /* DriveFolderPickerView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DriveFolderPickerView.swift; sourceTree = \"<group>\"; };\n/* End PBXFileReference section */",
    1,
)

# --- PBXBuildFile ---
text = text.replace(
    "/* End PBXBuildFile section */",
    "\t\tCS0000020000000000000006 /* DriveFolderPickerView.swift in Sources */ = {isa = PBXBuildFile; fileRef = CS0000010000000000000006 /* DriveFolderPickerView.swift */; };\n/* End PBXBuildFile section */",
    1,
)

# Views/Main グループに追加（CloudSyncSettingsView の後）
text = text.replace(
    "\t\t\t\tCS0000010000000000000005 /* CloudSyncSettingsView.swift */,",
    "\t\t\t\tCS0000010000000000000005 /* CloudSyncSettingsView.swift */,\n\t\t\t\tCS0000010000000000000006 /* DriveFolderPickerView.swift */,",
    1,
)

# Sources ビルドフェーズに追加
text = text.replace(
    "\t\t\t\tCS0000020000000000000005 /* CloudSyncSettingsView.swift in Sources */,",
    "\t\t\t\tCS0000020000000000000005 /* CloudSyncSettingsView.swift in Sources */,\n\t\t\t\tCS0000020000000000000006 /* DriveFolderPickerView.swift in Sources */,",
    1,
)

PBX.write_text(text)
print("Patched", PBX)
