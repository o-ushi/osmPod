#!/usr/bin/env python3
"""Add osmPodShare extension target to project.pbxproj"""
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "osmPod.xcodeproj" / "project.pbxproj"
text = PBX.read_text()

if "osmPodShare" in text and "S50000010000000000000002" in text:
    print("Already patched")
    raise SystemExit(0)

insertions = [
    (
        "/* End PBXBuildFile section */",
        """\t\tS10000020000000000000001 /* ShareViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = S10000010000000000000001 /* ShareViewController.swift */; };
\t\tS10000020000000000000002 /* ShareImportStorage.swift in Sources */ = {isa = PBXBuildFile; fileRef = S10000010000000000000006 /* ShareImportStorage.swift */; };
\t\tS10000020000000000000003 /* ShareImportStorage.swift in Sources */ = {isa = PBXBuildFile; fileRef = S10000010000000000000006 /* ShareImportStorage.swift */; };
\t\tS10000020000000000000009 /* osmPodShare.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = S10000010000000000000003 /* osmPodShare.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
\t\tS10000020000000000000010 /* RelatedShowsService.swift in Sources */ = {isa = PBXBuildFile; fileRef = S10000010000000000000007 /* RelatedShowsService.swift */; };
\t\tS10000020000000000000011 /* ShareImportCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = S10000010000000000000008 /* ShareImportCoordinator.swift */; };
\t\tS10000020000000000000012 /* ShareImportSheet.swift in Sources */ = {isa = PBXBuildFile; fileRef = S10000010000000000000009 /* ShareImportSheet.swift */; };
/* End PBXBuildFile section */""",
    ),
    (
        "/* End PBXFileReference section */",
        """\t\tS10000010000000000000001 /* ShareViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareViewController.swift; sourceTree = "<group>"; };
\t\tS10000010000000000000002 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
\t\tS10000010000000000000003 /* osmPodShare.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = osmPodShare.appex; sourceTree = BUILT_PRODUCTS_DIR; };
\t\tS10000010000000000000004 /* osmPodShare.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = osmPodShare.entitlements; sourceTree = "<group>"; };
\t\tS10000010000000000000005 /* osmPod.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = osmPod.entitlements; sourceTree = "<group>"; };
\t\tS10000010000000000000006 /* ShareImportStorage.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareImportStorage.swift; sourceTree = "<group>"; };
\t\tS10000010000000000000007 /* RelatedShowsService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RelatedShowsService.swift; sourceTree = "<group>"; };
\t\tS10000010000000000000008 /* ShareImportCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareImportCoordinator.swift; sourceTree = "<group>"; };
\t\tS10000010000000000000009 /* ShareImportSheet.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareImportSheet.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */""",
    ),
    (
        "/* End PBXFrameworksBuildPhase section */",
        """\t\tS30000010000000000000005 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXFrameworksBuildPhase section */""",
    ),
    (
        "/* End PBXGroup section */",
        """\t\tS4000001000000000000000B /* osmPodShare */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tS10000010000000000000001 /* ShareViewController.swift */,
\t\t\t\tS10000010000000000000002 /* Info.plist */,
\t\t\t\tS10000010000000000000004 /* osmPodShare.entitlements */,
\t\t\t);
\t\t\tpath = osmPodShare;
\t\t\tsourceTree = "<group>";
\t\t};
\t\tS4000001000000000000000C /* Shared */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tS10000010000000000000006 /* ShareImportStorage.swift */,
\t\t\t);
\t\t\tpath = Shared;
\t\t\tsourceTree = "<group>";
\t\t};
/* End PBXGroup section */""",
    ),
    (
        "/* End PBXNativeTarget section */",
        """\t\tS50000010000000000000002 /* osmPodShare */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = S70000010000000000000003 /* Build configuration list for PBXNativeTarget "osmPodShare" */;
\t\t\tbuildPhases = (
\t\t\t\tS30000010000000000000004 /* Sources */,
\t\t\t\tS30000010000000000000005 /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = osmPodShare;
\t\t\tproductName = osmPodShare;
\t\t\tproductReference = S10000010000000000000003 /* osmPodShare.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t};
/* End PBXNativeTarget section */""",
    ),
    (
        "/* End PBXProject section */",
        """/* Begin PBXContainerItemProxy section */
\t\tS60000010000000000000002 /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = A60000010000000000000001 /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = S50000010000000000000002;
\t\t\tremoteInfo = osmPodShare;
\t\t};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\tS30000010000000000000006 /* Embed Foundation Extensions */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\tS10000020000000000000009 /* osmPodShare.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\tS60000010000000000000003 /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = S50000010000000000000002 /* osmPodShare */;
\t\t\ttargetProxy = S60000010000000000000002 /* PBXContainerItemProxy */;
\t\t};
/* End PBXTargetDependency section */

/* End PBXProject section */""",
    ),
    (
        "/* End PBXSourcesBuildPhase section */",
        """\t\tS30000010000000000000004 /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\tS10000020000000000000001 /* ShareViewController.swift in Sources */,
\t\t\t\tS10000020000000000000002 /* ShareImportStorage.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXSourcesBuildPhase section */""",
    ),
    (
        "/* End XCBuildConfiguration section */",
        """\t\tS80000010000000000000005 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = osmPodShare/osmPodShare.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = ELS6C2V4CR;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = osmPodShare/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.1;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.osamushikubo.osmPod.Share;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "iphonesimulator iphoneos";
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\tS80000010000000000000006 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = osmPodShare/osmPodShare.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = ELS6C2V4CR;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = osmPodShare/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.1;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.osamushikubo.osmPod.Share;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "iphonesimulator iphoneos";
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t};
\t\t\tname = Release;
\t\t};
/* End XCBuildConfiguration section */""",
    ),
    (
        "/* End XCConfigurationList section */",
        """\t\tS70000010000000000000003 /* Build configuration list for PBXNativeTarget "osmPodShare" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\tS80000010000000000000005 /* Debug */,
\t\t\t\tS80000010000000000000006 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
/* End XCConfigurationList section */""",
    ),
]

for old, new in insertions:
    if old not in text:
        raise SystemExit(f"Anchor not found: {old}")
    text = text.replace(old, new, 1)

# Main group children
text = text.replace(
    "\t\t\tchildren = (\n\t\t\t\tA40000010000000000000002 /* osmPod */,",
    "\t\t\tchildren = (\n\t\t\t\tA40000010000000000000002 /* osmPod */,\n\t\t\t\tS4000001000000000000000B /* osmPodShare */,\n\t\t\t\tS4000001000000000000000C /* Shared */,",
    1,
)

text = text.replace(
    "\t\t\tchildren = (\n\t\t\t\tA40000010000000000000003 /* App */,",
    "\t\t\tchildren = (\n\t\t\t\tA40000010000000000000003 /* App */,\n\t\t\t\tS4000001000000000000000C /* Shared */,\n\t\t\t\tS10000010000000000000005 /* osmPod.entitlements */,",
    1,
)

text = text.replace(
    "\t\t\tchildren = (\n\t\t\t\tA2000001000000000000000D /* osmPod.app */,",
    "\t\t\tchildren = (\n\t\t\t\tA2000001000000000000000D /* osmPod.app */,\n\t\t\t\tS10000010000000000000003 /* osmPodShare.appex */,",
    1,
)

text = text.replace(
    "\t\t\tbuildPhases = (\n\t\t\t\tA30000010000000000000002 /* Sources */,\n\t\t\t\tA30000010000000000000001 /* Frameworks */,\n\t\t\t\tA30000010000000000000003 /* Resources */,",
    "\t\t\tbuildPhases = (\n\t\t\t\tA30000010000000000000002 /* Sources */,\n\t\t\t\tA30000010000000000000001 /* Frameworks */,\n\t\t\t\tS30000010000000000000006 /* Embed Foundation Extensions */,\n\t\t\t\tA30000010000000000000003 /* Resources */,",
    1,
)

text = text.replace(
    "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = osmPod;",
    "\t\t\tdependencies = (\n\t\t\t\tS60000010000000000000003 /* PBXTargetDependency */,\n\t\t\t);\n\t\t\tname = osmPod;",
    1,
)

text = text.replace(
    "\t\t\ttargets = (\n\t\t\t\tA50000010000000000000001 /* osmPod */,\n\t\t\t);",
    "\t\t\ttargets = (\n\t\t\t\tA50000010000000000000001 /* osmPod */,\n\t\t\t\tS50000010000000000000002 /* osmPodShare */,\n\t\t\t);",
    1,
)

text = text.replace(
    "\t\t\t\tA50000010000000000000001 = {\n\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t};",
    "\t\t\t\tA50000010000000000000001 = {\n\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t};\n\t\t\t\tS50000010000000000000002 = {\n\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t};",
    1,
)

# Services group
text = text.replace(
    "\t\t\t\tE10000010000000000000003 /* RSSURLExtractor.swift */,",
    "\t\t\t\tE10000010000000000000003 /* RSSURLExtractor.swift */,\n\t\t\t\tS10000010000000000000007 /* RelatedShowsService.swift */,\n\t\t\t\tS10000010000000000000008 /* ShareImportCoordinator.swift */,",
    1,
)

# AddShow group
text = text.replace(
    "\t\t\t\tE10000010000000000000005 /* CollapsibleFolderPickerRows.swift */,",
    "\t\t\t\tE10000010000000000000005 /* CollapsibleFolderPickerRows.swift */,\n\t\t\t\tS10000010000000000000009 /* ShareImportSheet.swift */,",
    1,
)

# Main sources
text = text.replace(
    "\t\t\t\tE10000020000000000000005 /* CollapsibleFolderPickerRows.swift in Sources */,",
    "\t\t\t\tE10000020000000000000005 /* CollapsibleFolderPickerRows.swift in Sources */,\n\t\t\t\tS10000020000000000000003 /* ShareImportStorage.swift in Sources */,\n\t\t\t\tS10000020000000000000010 /* RelatedShowsService.swift in Sources */,\n\t\t\t\tS10000020000000000000011 /* ShareImportCoordinator.swift in Sources */,\n\t\t\t\tS10000020000000000000012 /* ShareImportSheet.swift in Sources */,",
    1,
)

# Entitlements on main app
text = text.replace(
    "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n\t\t\t\tDEVELOPMENT_TEAM = ELS6C2V4CR;\n\t\t\t\tENABLE_PREVIEWS = YES;\n\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n\t\t\t\tINFOPLIST_FILE = Info.plist;",
    "\t\t\t\tCODE_SIGN_ENTITLEMENTS = osmPod.entitlements;\n\t\t\t\tCODE_SIGN_STYLE = Automatic;\n\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n\t\t\t\tDEVELOPMENT_TEAM = ELS6C2V4CR;\n\t\t\t\tENABLE_PREVIEWS = YES;\n\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n\t\t\t\tINFOPLIST_FILE = Info.plist;",
    2,
)

PBX.write_text(text)
print("Patched", PBX)
