#!/usr/bin/env python3
"""Add GoogleDriveSetupView.swift to project.pbxproj"""
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "osmPod.xcodeproj" / "project.pbxproj"
text = PBX.read_text()

if "GoogleDriveSetupView.swift" in text:
    print("Already patched")
    raise SystemExit(0)

text = text.replace(
    "/* End PBXFileReference section */",
    "\t\tCS0000010000000000000007 /* GoogleDriveSetupView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GoogleDriveSetupView.swift; sourceTree = \"<group>\"; };\n/* End PBXFileReference section */",
    1,
)

text = text.replace(
    "/* End PBXBuildFile section */",
    "\t\tCS0000020000000000000007 /* GoogleDriveSetupView.swift in Sources */ = {isa = PBXBuildFile; fileRef = CS0000010000000000000007 /* GoogleDriveSetupView.swift */; };\n/* End PBXBuildFile section */",
    1,
)

text = text.replace(
    "\t\t\t\tCS0000010000000000000006 /* DriveFolderPickerView.swift */,",
    "\t\t\t\tCS0000010000000000000006 /* DriveFolderPickerView.swift */,\n\t\t\t\tCS0000010000000000000007 /* GoogleDriveSetupView.swift */,",
    1,
)

text = text.replace(
    "\t\t\t\tCS0000020000000000000006 /* DriveFolderPickerView.swift in Sources */,",
    "\t\t\t\tCS0000020000000000000006 /* DriveFolderPickerView.swift in Sources */,\n\t\t\t\tCS0000020000000000000007 /* GoogleDriveSetupView.swift in Sources */,",
    1,
)

PBX.write_text(text)
print("Patched", PBX)
