#!/usr/bin/env python3
"""
Google Drive 関連エントリを pbxproj から全削除し、
ICloudSyncManager.swift を Services グループに追加する。
"""
import re
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "osmPod.xcodeproj" / "project.pbxproj"
text = PBX.read_text()

# ── 1. 削除対象の ID 一覧 ──────────────────────────────────────────────
REMOVE_IDS = [f"CS000001000000000000000{i}" for i in range(1, 8)]   # FileRef 1-7
REMOVE_IDS += [f"CS000002000000000000000{i}" for i in range(1, 8)]  # BuildFile 1-7
REMOVE_IDS.append("CS0000030000000000000001")                        # CloudSync group

# ── 2. 行単位で該当 ID を含む行を削除 ──────────────────────────────────
lines = text.splitlines(keepends=True)
kept = [l for l in lines if not any(cid in l for cid in REMOVE_IDS)]
text = "".join(kept)

# ── 3. CloudSync グループへの参照（Services グループ内）を削除 ──────────
text = re.sub(r'\s*CS0000030000000000000001 /\* CloudSync \*/,\n', '\n', text)

# ── 4. CloudSyncSettingsView は残す（再利用）。
#       DriveFolderPickerView / GoogleDriveSetupView は削除済み（ファイル自体も削除）。

# ── 5. ICloudSyncManager.swift を追加（まだなければ）───────────────────
if "ICloudSyncManager.swift" not in text:
    # FileReference
    text = text.replace(
        "/* End PBXFileReference section */",
        "\t\tIC000001 /* ICloudSyncManager.swift */ = {isa = PBXFileReference; "
        "lastKnownFileType = sourcecode.swift; path = ICloudSyncManager.swift; "
        "sourceTree = \"<group>\"; };\n/* End PBXFileReference section */",
        1,
    )
    # BuildFile
    text = text.replace(
        "/* End PBXBuildFile section */",
        "\t\tIC000002 /* ICloudSyncManager.swift in Sources */ = {isa = PBXBuildFile; "
        "fileRef = IC000001 /* ICloudSyncManager.swift */; };\n"
        "/* End PBXBuildFile section */",
        1,
    )
    # Services グループに追加（ShareImportCoordinator の後）
    text = text.replace(
        "\t\t\t\tS10000010000000000000008 /* ShareImportCoordinator.swift */,",
        "\t\t\t\tS10000010000000000000008 /* ShareImportCoordinator.swift */,\n"
        "\t\t\t\tIC000001 /* ICloudSyncManager.swift */,",
        1,
    )
    # Sources ビルドフェーズに追加
    text = text.replace(
        "\t\t\t\tS10000020000000000000012 /* ShareImportSheet.swift in Sources */,",
        "\t\t\t\tS10000020000000000000012 /* ShareImportSheet.swift in Sources */,\n"
        "\t\t\t\tIC000002 /* ICloudSyncManager.swift in Sources */,",
        1,
    )

PBX.write_text(text)
print("Patched", PBX)
