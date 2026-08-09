#!/usr/bin/env python3
"""Add CloudSync files to project.pbxproj"""
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "osmPod.xcodeproj" / "project.pbxproj"
text = PBX.read_text()

if "GoogleDriveConfig.swift" in text:
    print("Already patched")
    raise SystemExit(0)

# --- PBXFileReference ---
file_refs = """\t\tCS0000010000000000000001 /* GoogleDriveConfig.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GoogleDriveConfig.swift; sourceTree = "<group>"; };
\t\tCS0000010000000000000002 /* KeychainHelper.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KeychainHelper.swift; sourceTree = "<group>"; };
\t\tCS0000010000000000000003 /* GoogleDriveService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GoogleDriveService.swift; sourceTree = "<group>"; };
\t\tCS0000010000000000000004 /* CloudSyncManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CloudSyncManager.swift; sourceTree = "<group>"; };
\t\tCS0000010000000000000005 /* CloudSyncSettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CloudSyncSettingsView.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */"""

text = text.replace(
    "/* End PBXFileReference section */",
    file_refs,
    1,
)

# --- PBXBuildFile ---
build_files = """\t\tCS0000020000000000000001 /* GoogleDriveConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = CS0000010000000000000001 /* GoogleDriveConfig.swift */; };
\t\tCS0000020000000000000002 /* KeychainHelper.swift in Sources */ = {isa = PBXBuildFile; fileRef = CS0000010000000000000002 /* KeychainHelper.swift */; };
\t\tCS0000020000000000000003 /* GoogleDriveService.swift in Sources */ = {isa = PBXBuildFile; fileRef = CS0000010000000000000003 /* GoogleDriveService.swift */; };
\t\tCS0000020000000000000004 /* CloudSyncManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = CS0000010000000000000004 /* CloudSyncManager.swift */; };
\t\tCS0000020000000000000005 /* CloudSyncSettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = CS0000010000000000000005 /* CloudSyncSettingsView.swift */; };
/* End PBXBuildFile section */"""

text = text.replace(
    "/* End PBXBuildFile section */",
    build_files,
    1,
)

# --- PBXGroup: CloudSync サブグループを追加 ---
cloud_sync_group = """\t\tCS0000030000000000000001 /* CloudSync */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tCS0000010000000000000001 /* GoogleDriveConfig.swift */,
\t\t\t\tCS0000010000000000000002 /* KeychainHelper.swift */,
\t\t\t\tCS0000010000000000000003 /* GoogleDriveService.swift */,
\t\t\t\tCS0000010000000000000004 /* CloudSyncManager.swift */,
\t\t\t);
\t\t\tpath = CloudSync;
\t\t\tsourceTree = "<group>";
\t\t};
/* End PBXGroup section */"""

text = text.replace(
    "/* End PBXGroup section */",
    cloud_sync_group,
    1,
)

# Services グループに CloudSync サブグループを追加
# Services グループは A40000010000000000000005
# 最後の子要素の後に追加（RelatedShowsService の後）
text = text.replace(
    "\t\t\t\tS10000010000000000000007 /* RelatedShowsService.swift */,\n\t\t\t\tS10000010000000000000008 /* ShareImportCoordinator.swift */,",
    "\t\t\t\tS10000010000000000000007 /* RelatedShowsService.swift */,\n\t\t\t\tS10000010000000000000008 /* ShareImportCoordinator.swift */,\n\t\t\t\tCS0000030000000000000001 /* CloudSync */,",
    1,
)

# Main グループ（Views/Main）に CloudSyncSettingsView.swift を追加
text = text.replace(
    "\t\t\t\tC10000010000000000000007 /* AppearanceSettingsView.swift */,\n\t\t\t);\n\t\t\tpath = Main;",
    "\t\t\t\tC10000010000000000000007 /* AppearanceSettingsView.swift */,\n\t\t\t\tCS0000010000000000000005 /* CloudSyncSettingsView.swift */,\n\t\t\t);\n\t\t\tpath = Main;",
    1,
)

# Sources ビルドフェーズに新ファイルを追加
text = text.replace(
    "\t\t\t\tS10000020000000000000012 /* ShareImportSheet.swift in Sources */,",
    "\t\t\t\tS10000020000000000000012 /* ShareImportSheet.swift in Sources */,\n\t\t\t\tCS0000020000000000000001 /* GoogleDriveConfig.swift in Sources */,\n\t\t\t\tCS0000020000000000000002 /* KeychainHelper.swift in Sources */,\n\t\t\t\tCS0000020000000000000003 /* GoogleDriveService.swift in Sources */,\n\t\t\t\tCS0000020000000000000004 /* CloudSyncManager.swift in Sources */,\n\t\t\t\tCS0000020000000000000005 /* CloudSyncSettingsView.swift in Sources */,",
    1,
)

PBX.write_text(text)
print("Patched", PBX)
