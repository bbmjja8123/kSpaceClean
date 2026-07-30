#!/usr/bin/env python3
"""Generate kSpaceClean.xcodeproj/project.pbxproj manually — proper OpenStep plist format.

# Path resolution
#
# The default ``BASE`` path points at the main repository's ``kSpaceClean``
# directory. When the script is run from inside a worktree
# (e.g. ``.claude/worktrees/feat-kspaceclean-v1/kSpaceClean/generate_project.py``),
# that absolute path would write the regenerated ``project.pbxproj`` into the
# *parent* repository rather than the worktree, leaving the worktree's
# on-disk copy stale. The worktree workflow therefore relied on a manual
# ``cp`` after every regeneration (see A6/A12/A13 reports).
#
# To fix that, the script now resolves ``BASE`` with the following
# precedence:
#
# 1. ``--base <path>`` CLI argument (explicit override; highest priority).
# 2. ``KSPACECLEAN_BASE`` environment variable (CI / Makefile use).
# 3. The directory containing this script — i.e. the worktree-aware default
#    that always regenerates the project file alongside the script.
#
# This means running ``python3 generate_project.py`` inside the worktree now
# writes to the worktree's ``kSpaceClean.xcodeproj`` automatically, and
# callers that really do want the main-repo path can opt in with
# ``--base /Users/mengjianjun/Documents/ai/aicoding/macapp/kSpaceClean``.
"""

import os
import sys
import argparse
import hashlib

DEFAULT_BASE = "/Users/mengjianjun/Documents/ai/aicoding/macapp/kSpaceClean"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def resolve_base():
    """Resolve the BASE directory using CLI > env > script-dir precedence."""
    parser = argparse.ArgumentParser(
        description="Generate kSpaceClean.xcodeproj/project.pbxproj."
    )
    parser.add_argument(
        "--base",
        default=None,
        help=(
            "Output directory containing the kSpaceClean target sources. "
            "Defaults to $KSPACECLEAN_BASE, then the directory containing "
            "this script (so worktree workflows regenerate in place)."
        ),
    )
    args = parser.parse_args()

    if args.base:
        base = os.path.abspath(args.base)
    elif os.environ.get("KSPACECLEAN_BASE"):
        base = os.path.abspath(os.environ["KSPACECLEAN_BASE"])
    else:
        # Default to the directory containing this script so the script
        # always regenerates the project file alongside it (worktree-safe).
        base = SCRIPT_DIR
    return base


BASE = resolve_base()
PROJECT_FILE = f"{BASE}/kSpaceClean.xcodeproj/project.pbxproj"
# kFoundation lives alongside the parent directory of BASE (the kSpaceClean
# sibling). Try a few candidates to stay portable across worktrees.
_KFOUNDATION_CANDIDATES = [
    os.path.join(os.path.dirname(BASE), "kFoundation"),
    "/Users/mengjianjun/Documents/ai/aicoding/macapp/kFoundation",
]
KFOUNTATION_PATH = next(
    (p for p in _KFOUNDATION_CANDIDATES if os.path.isdir(p)),
    _KFOUNDATION_CANDIDATES[0],
)

def hash_id(seed, length=24):
    return hashlib.sha256(seed.encode()).hexdigest()[:length].upper()

def q(v):
    """Quote a value for pbxproj if it contains special chars, but only wrap once."""
    if v is None:
        return '""'
    if not isinstance(v, str):
        return str(v)
    if v == "":
        return '""'
    if v.startswith('"') and v.endswith('"') and len(v) > 1:
        return v
    # NOTE: + must be quoted — Apple's old-style plist parser interprets
    # unquoted + as a numeric sign prefix, causing "missing semicolon" errors.
    special = '{}()=,; \t\n<>+'
    if any(c in v for c in special):
        return f'"{v}"'
    return v

def fmt_comment(s):
    return f" /* {s} */"

def fmt_build_settings(settings, indent=2):
    """Format a buildSettings dictionary into pbxproj format."""
    tab = "\t" * indent
    lines = ["{"]
    for key in sorted(settings.keys()):
        val = settings[key]
        if isinstance(val, list):
            # Array value
            items = []
            for v in val:
                if isinstance(v, str):
                    items.append(f"{tab}\t{q(v)},")
                else:
                    items.append(f"{tab}\t{v},")
            arr = f"(\n" + "\n".join(items) + f"\n{tab})"
            lines.append(f"{tab}{key} = {arr};")
        elif isinstance(val, str):
            lines.append(f"{tab}{key} = {q(val)};")
        elif isinstance(val, bool):
            lines.append(f"{tab}{key} = {'YES' if val else 'NO'};")
        elif isinstance(val, int):
            lines.append(f"{tab}{key} = {val};")
        elif val is None:
            lines.append(f"{tab}{key} = ;")
    lines.append(f"{tab}}}")
    return "\n".join(lines)

def main():
    objects = {}
    id_map = {}

    def oid(seed):
        if seed not in id_map:
            id_map[seed] = hash_id(seed)
        return id_map[seed]

    def add(obj, seed):
        obj_id = oid(seed)
        objects[obj_id] = obj
        return obj_id

    # ========== Group structure ==========
    root_group_id = add(("PBXGroup", {"name": "kSpaceClean", "path": "", "sourceTree": "<group>",
                                       "children": []}), "root_group")

    def make_group(name, children=None):
        g = {"name": name, "sourceTree": "<group>", "children": children or []}
        return ("PBXGroup", g)

    def make_fileref(name, path, last=None, explicit=None, sourceTree="<group>", includeInIndex=None):
        r = {"name": name, "path": path, "sourceTree": sourceTree}
        if last: r["lastKnownFileType"] = last
        if explicit: r["explicitFileType"] = explicit
        if includeInIndex is not None: r["includeInIndex"] = includeInIndex
        return ("PBXFileReference", r)

    def make_buildfile(fileref, settings=None):
        b = {"fileRef": fileref}
        if settings: b["settings"] = settings
        return ("PBXBuildFile", b)

    # All groups
    group_defs = {
        "App": make_group("App"),
        "Features": make_group("Features"),
        "AIClassifier": make_group("AIClassifier"),
        "Cleanup": make_group("Cleanup"),
        "Common": make_group("Common"),
        "Components": make_group("Components"),
        "DesignSystem": make_group("DesignSystem"),
        "Models": make_group("Models"),
        "DiskGalaxy": make_group("DiskGalaxy"),
        "LargeOldFile": make_group("LargeOldFile"),
        "DuplicateFile": make_group("DuplicateFile"),
        "AppUninstall": make_group("AppUninstall"),
        "PrivacyClean": make_group("PrivacyClean"),
        "PhotoClean": make_group("PhotoClean"),
        "Maintenance": make_group("Maintenance"),
        "Onboarding": make_group("Onboarding"),
        "RightPanel": make_group("RightPanel"),
        "SmartScan": make_group("SmartScan"),
        "FinderExtension": make_group("FinderExtension"),
        "Intents": make_group("Intents"),
        "LaunchAgent": make_group("LaunchAgent"),
        "LiveActivity": make_group("LiveActivity"),
        "MenuBar": make_group("MenuBar"),
        "Persistence": make_group("Persistence"),
        "Resources": make_group("Resources"),
        "Settings": make_group("Settings"),
        "Spotlight": make_group("Spotlight"),
        "Store": make_group("Store"),
        "Widgets": make_group("Widgets"),
        "Tests": make_group("Tests"),
        "Products": make_group("Products"),
        "Frameworks": make_group("Frameworks"),
    }

    group_ids = {}
    for gname in group_defs:
        gid = add(group_defs[gname], f"grp_{gname}")
        group_ids[gname] = gid

    # ========== File references and build files ==========
    # Format: (path, group_name)
    swift_files = [
        ("App/AppCoordinator.swift", "App"),
        ("App/AppState.swift", "App"),
        ("App/RootView.swift", "App"),
        ("App/kSpaceCleanApp.swift", "App"),
        ("Features/AIClassifier/AIClassifier.swift", "AIClassifier"),
        ("Features/AIClassifier/RuleClassifier.swift", "AIClassifier"),
        ("Features/Cleanup/CleanupContentView.swift", "Cleanup"),
        ("Features/Cleanup/CleanupHistory.swift", "Cleanup"),
        ("Features/Cleanup/CleanupViewModel.swift", "Cleanup"),
        ("Features/Cleanup/HistoryContentView.swift", "Cleanup"),
        ("Features/Cleanup/TrashMover.swift", "Cleanup"),
        ("Features/Cleanup/CleanupEngine.swift", "Cleanup"),
        ("Features/Cleanup/CleanActionExecutors.swift", "Cleanup"),
        ("Features/Cleanup/Models/CleanupTypes.swift", "Cleanup"),
        ("Features/Cleanup/Views/CleanupConfirmSheet.swift", "Cleanup"),
        ("Features/Cleanup/Views/DangerousConfirmDialog.swift", "Cleanup"),
        ("Features/Cleanup/Views/WarningToast.swift", "Cleanup"),
        ("Features/Cleanup/Engine/WarningDetectionService.swift", "Cleanup"),
        ("Features/Common/DesignSystem/Colors.swift", "DesignSystem"),
        ("Features/Common/DesignSystem/Typography.swift", "DesignSystem"),
        ("Features/Common/DesignSystem/Spacing.swift", "DesignSystem"),
        ("Features/Common/DesignSystem/Accessibility.swift", "DesignSystem"),
        ("Features/Common/Components/RiskBadge.swift", "Components"),
        ("Features/Common/Components/IndeterminateCheckbox.swift", "Components"),
        ("Features/Common/Components/EmptyStateView.swift", "Components"),
        ("Features/Common/Components/SkeletonRow.swift", "Components"),
        ("Features/Common/Components/ToolbarView.swift", "Components"),
        ("Features/Common/KeyboardShortcuts.swift", "Common"),
        ("Features/Common/Models/RiskLevel.swift", "Models"),
        ("Features/Common/Models/CheckState.swift", "Models"),
        ("Features/Common/Models/SelectionPolicy.swift", "Models"),
        ("Features/LargeOldFile/LargeOldScanner.swift", "LargeOldFile"),
        ("Features/LargeOldFile/LargeOldViewModel.swift", "LargeOldFile"),
        ("Features/LargeOldFile/LargeOldView.swift", "LargeOldFile"),
        ("Features/DuplicateFile/DuplicateScanner.swift", "DuplicateFile"),
        ("Features/DuplicateFile/DuplicateViewModel.swift", "DuplicateFile"),
        ("Features/DuplicateFile/DuplicateView.swift", "DuplicateFile"),
        ("Features/AppUninstall/AppUninstallScanner.swift", "AppUninstall"),
        ("Features/AppUninstall/AppUninstallViewModel.swift", "AppUninstall"),
        ("Features/AppUninstall/AppUninstallView.swift", "AppUninstall"),
        ("Features/PrivacyClean/PrivacyScanner.swift", "PrivacyClean"),
        ("Features/PrivacyClean/PrivacyViewModel.swift", "PrivacyClean"),
        ("Features/PrivacyClean/PrivacyView.swift", "PrivacyClean"),
        ("Features/PhotoClean/PhotoCacheScanner.swift", "PhotoClean"),
        ("Features/PhotoClean/PhotoCleanViewModel.swift", "PhotoClean"),
        ("Features/PhotoClean/PhotoCleanView.swift", "PhotoClean"),
        ("Features/Maintenance/MaintenanceScript.swift", "Maintenance"),
        ("Features/Maintenance/MaintenanceViewModel.swift", "Maintenance"),
        ("Features/Maintenance/MaintenanceView.swift", "Maintenance"),
        ("Features/DiskGalaxy/GalaxyRenderer.swift", "DiskGalaxy"),
        ("Features/DiskGalaxy/GalaxyScene.swift", "DiskGalaxy"),
        ("Features/DiskGalaxy/GalaxyView.swift", "DiskGalaxy"),
        ("Features/DiskGalaxy/GalaxyViewModel.swift", "DiskGalaxy"),
        ("Features/DiskGalaxy/DiskUsageBar.swift", "DiskGalaxy"),
        ("Features/Onboarding/OnboardingCoordinator.swift", "Onboarding"),
        ("Features/Onboarding/OnboardingPages.swift", "Onboarding"),
        ("Features/RightPanel/AllFilesTabView.swift", "RightPanel"),
        ("Features/RightPanel/OverviewTabView.swift", "RightPanel"),
        ("Features/RightPanel/RightPanelView.swift", "RightPanel"),
        ("Features/RightPanel/SuggestionsTabView.swift", "RightPanel"),
        ("Features/Settings/SettingsView.swift", "Settings"),
        ("Features/SmartScan/FilterEvaluator.swift", "SmartScan"),
        ("Features/SmartScan/ScanContentView.swift", "SmartScan"),
        ("Features/SmartScan/ScanEngine.swift", "SmartScan"),
        ("Features/SmartScan/ScanProgress.swift", "SmartScan"),
        ("Features/SmartScan/ScanRule.swift", "SmartScan"),
        ("Features/SmartScan/AppScanRules.swift", "SmartScan"),
        ("Features/SmartScan/ScanSpeed.swift", "SmartScan"),
        ("Features/SmartScan/ScanResultsTreeView.swift", "SmartScan"),
        ("Features/SmartScan/ScanViewModel.swift", "SmartScan"),
        ("Features/SmartScan/SpecializedScanners.swift", "SmartScan"),
        ("Features/SmartScan/Models/ScanTreeNode.swift", "SmartScan"),
        ("Features/SmartScan/Models/ScanCategory.swift", "SmartScan"),
        ("Features/SmartScan/Models/ScanSubCategory.swift", "SmartScan"),
        ("Features/SmartScan/Models/ScanAction.swift", "SmartScan"),
        ("Features/SmartScan/Models/ScanResult.swift", "SmartScan"),
        ("Features/SmartScan/Models/ScanThreshold.swift", "SmartScan"),
        ("Features/SmartScan/Engine/ScanOrchestrator.swift", "SmartScan"),
        ("Features/SmartScan/Engine/ScanEngineStream.swift", "SmartScan"),
        ("Features/SmartScan/Views/ScanResultsView.swift", "SmartScan"),
        ("Features/SmartScan/Views/ScanResultsViewModel.swift", "SmartScan"),
        ("Features/SmartScan/Views/ScanTreeRow.swift", "SmartScan"),
        ("Features/SmartScan/Views/ScanProgressRing.swift", "SmartScan"),
        ("Features/SmartScan/Views/ScanProgressView.swift", "SmartScan"),
        ("FinderExtension/FinderSync.swift", "FinderExtension"),
        ("Intents/ScanIntent.swift", "Intents"),
        ("LaunchAgent/TrashMonitorService.swift", "LaunchAgent"),
        ("LiveActivity/CleanupActivityAttributes.swift", "LiveActivity"),
        ("MenuBar/DiskStatusView.swift", "MenuBar"),
        ("MenuBar/MenuBarManager.swift", "MenuBar"),
        ("Persistence/CoreDataModels/CleanupHistoryItem.swift", "Persistence"),
        ("Persistence/CoreDataModels/CleanupRecord.swift", "Persistence"),
        ("Persistence/CoreDataModels/FileEntry.swift", "Persistence"),
        ("Persistence/CoreDataModels/ScanRecord.swift", "Persistence"),
        ("Persistence/CoreDataStack.swift", "Persistence"),
        ("Persistence/PersistenceController.swift", "Persistence"),
        ("Persistence/UserPreferences.swift", "Persistence"),
        ("Spotlight/SpotlightIndexer.swift", "Spotlight"),
        ("Store/PaywallView.swift", "Store"),
        ("Store/StoreManager.swift", "Store"),
        ("Store/StoreProtocol.swift", "Store"),
        ("Widgets/KSpaceCleanWidget.swift", "Widgets"),
    ]

    static_files = [
        "Info.plist",
        "kSpaceClean.entitlements",
        "AppStoreMetadata.plist",
    ]

    resource_dirs = [
        ("KSpaceClean.xcdatamodeld", "Resources", "wrapper.coredata"),
        ("Assets.xcassets", "Resources", "folder.assetcatalog"),
    ]

    resource_files = [
        "Localizable.xcstrings",
        "com.kraftly.kspaceclean.trashmonitor.plist",
        "bundleIDMapping.json",
    ]

    test_files = [
        "TestHelpers.swift",
        "RuleClassifierTests.swift",
        "GalaxyViewModelTests.swift",
        "AppStateTests.swift",
        "AppCoordinatorTests.swift",
        "ScanProgressTests.swift",
        "ScanProgressModelTests.swift",
        "TrashMoverTests.swift",
        "UserPreferencesTests.swift",
        "FileSizeFormatterTests.swift",
        "CleanupConfirmationTests.swift",
        "DangerousConfirmDialogTests.swift",
        "WarningToastTests.swift",
        "DuplicateDetectorTests.swift",
        "StoreManagerTests.swift",
        "ScanSpeedTests.swift",
        "RiskLevelTests.swift",
        "SelectionCascadeTests.swift",
        "CascadeCheckboxTests.swift",
        "DesignTokensTests.swift",
        "AccessibilityTests.swift",
        "RiskBadgeTests.swift",
        "IndeterminateCheckboxTests.swift",
        "RiskClassifierTests.swift",
        "EmptyStateViewTests.swift",
        "SnapshotTestCase.swift",
        "PhaseAComponentSnapshotTests.swift",
        "ScanResultsViewSnapshotTests.swift",
        "CleanupHistoryPersistenceTests.swift",
        "CleanupEngineTests.swift",
        "WarningDetectionServiceTests.swift",
    ]  # EmptyStateViewTests covers both EmptyStateView and SkeletonRow (Task A11)
    # CascadeCheckboxTests.swift — Task A5's 5 cascade-behaviour tests
    # (recommended-only parent selection, parent-off propagation,
    # mixed/on aggregation, manual dangerous selection). Re-registered in A14
    # after it had been sitting on disk unregistered since A5.

    main_build_files = []

    for sf_path, grp in swift_files:
        fname = os.path.basename(sf_path)
        gid = group_ids[grp]
        ext = os.path.splitext(sf_path)[1]
        lkft = "sourcecode.swift" if ext == ".swift" else "text.json.xcstrings"

        ref_id = add(make_fileref(fname, sf_path, last=lkft), f"ref_{sf_path}")
        bf_id = add(make_buildfile(ref_id), f"bf_{sf_path}")
        objects[gid][1]["children"].append((ref_id, fname))
        main_build_files.append(bf_id)

    for fpath in static_files:
        fname = os.path.basename(fpath)
        lkft = "text.plist.xml" if fpath.endswith(".plist") else "text.plist.entitlements"
        ref_id = add(make_fileref(fname, fpath, last=lkft), f"ref_{fpath}")
        objects[root_group_id][1]["children"].append((ref_id, fname))

    # Resource directories (go in Resources group, need PBXBuildFile for resource phase)
    resource_refs = []
    for rname, rgrp, rtype in resource_dirs:
        rpath = f"Resources/{rname}"
        gid = group_ids[rgrp]
        ref_id = add(make_fileref(rname, rpath, last=rtype), f"ref_{rpath}")
        bf_id = add(make_buildfile(ref_id), f"bf_{rpath}")
        objects[gid][1]["children"].append((ref_id, rname))
        resource_refs.append(bf_id)

    # Individual resource files
    for rf in resource_files:
        rpath = f"Resources/{rf}"
        gid = group_ids["Resources"]
        ext = os.path.splitext(rf)[1]
        lkft = "text.json.xcstrings" if ext == ".xcstrings" else "file"
        ref_id = add(make_fileref(rf, rpath, last=lkft), f"ref_{rpath}")
        bf_id = add(make_buildfile(ref_id), f"bf_{rpath}")
        objects[gid][1]["children"].append((ref_id, rf))
        resource_refs.append(bf_id)

    test_build_files = []
    for tf in test_files:
        tpath = f"Tests/{tf}"
        gid = group_ids["Tests"]
        ref_id = add(make_fileref(tf, tpath, last="sourcecode.swift"), f"ref_{tpath}")
        bf_id = add(make_buildfile(ref_id), f"bf_{tpath}")
        objects[gid][1]["children"].append((ref_id, tf))
        test_build_files.append(bf_id)

    # ========== Products ==========
    app_product_id = add(make_fileref("kSpaceClean.app", "kSpaceClean.app",
                                        explicit='"wrapper.application"', includeInIndex=0,
                                        sourceTree="BUILT_PRODUCTS_DIR"), "prod_app")
    test_product_id = add(make_fileref("kSpaceCleanTests.xctest", "kSpaceCleanTests.xctest",
                                         explicit='"wrapper.cfbundle"', includeInIndex=0,
                                         sourceTree="BUILT_PRODUCTS_DIR"), "prod_test")

    objects[group_ids["Products"]][1]["children"] = [
        (app_product_id, "kSpaceClean.app"), (test_product_id, "kSpaceCleanTests.xctest")]

    # ========== Swift Package ==========
    # PBXFileReference for the package folder (goes in Frameworks group)
    package_dir_ref_id = add(make_fileref("kFoundation", KFOUNTATION_PATH,
                                           last="folder", sourceTree="<absolute>"), "ref_kFoundation")

    # XCLocalSwiftPackageReference (goes in project-level packageReferences)
    package_ref_id = add(("XCLocalSwiftPackageReference", {"relativePath": KFOUNTATION_PATH}), "pkg_kfoundation")

    package_products = ["DesignSystem", "FileScanner", "CommonUtils", "Capabilities"]
    pkg_product_ids = {}
    for pp in package_products:
        ppid = add(("XCSwiftPackageProductDependency", {"productName": pp, "package": package_ref_id}), f"pkgprod_{pp}")
        pkg_product_ids[pp] = ppid

    # Put the package folder reference in the Frameworks group (NOT product deps)
    objects[group_ids["Frameworks"]][1]["children"] = [(package_dir_ref_id, "kFoundation")]

    # ========== Build Phases ==========
    main_sources_phase_id = add(("PBXSourcesBuildPhase", {
        "buildActionMask": 2147483647, "files": [(fid, "") for fid in main_build_files],
        "runOnlyForDeploymentPostprocessing": 0
    }), "phase_main_sources")
    main_frameworks_phase_id = add(("PBXFrameworksBuildPhase", {
        "buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0
    }), "phase_main_frameworks")
    main_resources_phase_id = add(("PBXResourcesBuildPhase", {
        "buildActionMask": 2147483647, "files": [(fid, "") for fid in resource_refs],
        "runOnlyForDeploymentPostprocessing": 0
    }), "phase_main_resources")

    test_sources_phase_id = add(("PBXSourcesBuildPhase", {
        "buildActionMask": 2147483647, "files": [(fid, "") for fid in test_build_files],
        "runOnlyForDeploymentPostprocessing": 0
    }), "phase_test_sources")
    test_frameworks_phase_id = add(("PBXFrameworksBuildPhase", {
        "buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0
    }), "phase_test_frameworks")

    # ========== Configurations ==========
    # Project-level
    proj_debug_id = add(("XCBuildConfiguration", {
        "name": "Debug",
        "buildSettings": {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
            "CLANG_ANALYZER_NONNULL": "YES",
            "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
            "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "COPY_PHASE_STRIP": "NO",
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_STRICT_OBJC_MSGSEND": "YES",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "ONLY_ACTIVE_ARCH": "YES",
            "SDKROOT": "macosx",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG"',
            "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_VERSION": "5.0",
        }
    }), "config_proj_debug")

    proj_release_id = add(("XCBuildConfiguration", {
        "name": "Release",
        "buildSettings": {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
            "CLANG_ANALYZER_NONNULL": "YES",
            "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
            "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "COPY_PHASE_STRIP": "NO",
            "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
            "ENABLE_NS_ASSERTIONS": "NO",
            "ENABLE_STRICT_OBJC_MSGSEND": "YES",
            "GCC_OPTIMIZATION_LEVEL": "s",
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "SDKROOT": "macosx",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_VERSION": "5.0",
        }
    }), "config_proj_release")

    proj_config_list_id = add(("XCConfigurationList", {
        "buildConfigurations": [(proj_debug_id, "Debug"), (proj_release_id, "Release")],
        "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"
    }), "configlist_proj")

    # Main target configs
    main_debug_id = add(("XCBuildConfiguration", {
        "name": "Debug",
        "buildSettings": {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "CODE_SIGNING_ALLOWED": "NO",
            "COMBINE_HIDPI_IMAGES": "YES",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": "Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": "kSpaceClean",
            "INFOPLIST_KEY_CFBundleIdentifier": "app.kraftly.sclean",
            "INFOPLIST_KEY_CFBundleName": "kSpaceClean",
            "INFOPLIST_KEY_CFBundlePackageType": '"APPL"',
            "INFOPLIST_KEY_CFBundleShortVersionString": '"1.0"',
            "INFOPLIST_KEY_CFBundleVersion": "1",
            "INFOPLIST_KEY_LSMinimumSystemVersion": "13.0",
            "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.sclean",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "macosx",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_VERSION": "5.0",
        }
    }), "config_main_debug")

    main_release_id = add(("XCBuildConfiguration", {
        "name": "Release",
        "buildSettings": {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "CODE_SIGN_ENTITLEMENTS": "kSpaceClean.entitlements",
            "CODE_SIGN_IDENTITY": '"-"',
            "CODE_SIGN_STYLE": "Manual",
            "COMBINE_HIDPI_IMAGES": "YES",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": "Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": "kSpaceClean",
            "INFOPLIST_KEY_CFBundleIdentifier": "app.kraftly.sclean",
            "INFOPLIST_KEY_CFBundleName": "kSpaceClean",
            "INFOPLIST_KEY_CFBundlePackageType": '"APPL"',
            "INFOPLIST_KEY_CFBundleShortVersionString": '"1.0"',
            "INFOPLIST_KEY_CFBundleVersion": "1",
            "INFOPLIST_KEY_LSMinimumSystemVersion": "13.0",
            "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.sclean",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "macosx",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_VERSION": "5.0",
        }
    }), "config_main_release")

    main_config_list_id = add(("XCConfigurationList", {
        "buildConfigurations": [(main_debug_id, "Debug"), (main_release_id, "Release")],
        "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"
    }), "configlist_main")

    # Test target configs
    test_debug_id = add(("XCBuildConfiguration", {
        "name": "Debug",
        "buildSettings": {
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "GENERATE_INFOPLIST_FILE": "YES",
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.sclean.tests",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "macosx",
            "SWIFT_VERSION": "5.0",
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/kSpaceClean.app/Contents/MacOS/kSpaceClean"',
        }
    }), "config_test_debug")

    test_release_id = add(("XCBuildConfiguration", {
        "name": "Release",
        "buildSettings": {
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "GENERATE_INFOPLIST_FILE": "YES",
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.sclean.tests",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "macosx",
            "SWIFT_VERSION": "5.0",
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/kSpaceClean.app/Contents/MacOS/kSpaceClean"',
        }
    }), "config_test_release")

    test_config_list_id = add(("XCConfigurationList", {
        "buildConfigurations": [(test_debug_id, "Debug"), (test_release_id, "Release")],
        "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"
    }), "configlist_test")

    # ========== Target Dependencies ==========
    cip_id = add(("PBXContainerItemProxy", {
        "containerPortal": oid("project_object"),
        "proxyType": 1,
        "remoteGlobalIDString": oid("target_kSpaceClean"),
        "remoteInfo": "kSpaceClean",
    }), "cip_main")

    target_dep_id = add(("PBXTargetDependency", {
        "name": "kSpaceClean",
        "target": oid("target_kSpaceClean"),
        "targetProxy": cip_id,
    }), "dep_main")

    # ========== Targets ==========
    main_target_id = add(("PBXNativeTarget", {
        "name": "kSpaceClean",
        "productName": "kSpaceClean",
        "productReference": app_product_id,
        "productType": '"com.apple.product-type.application"',
        "buildConfigurationList": main_config_list_id,
        "buildPhases": [(main_sources_phase_id, "Sources"),
                        (main_frameworks_phase_id, "Frameworks"),
                        (main_resources_phase_id, "Resources")],
        "buildRules": [],
        "dependencies": [],
        "packageProductDependencies": [(ppid, pp) for pp, ppid in pkg_product_ids.items()],
    }), "target_kSpaceClean")

    test_target_id = add(("PBXNativeTarget", {
        "name": "kSpaceCleanTests",
        "productName": "kSpaceCleanTests",
        "productReference": test_product_id,
        "productType": '"com.apple.product-type.bundle.unit-test"',
        "buildConfigurationList": test_config_list_id,
        "buildPhases": [(test_sources_phase_id, "Sources"),
                        (test_frameworks_phase_id, "Frameworks")],
        "buildRules": [],
        "dependencies": [(target_dep_id, "kSpaceClean")],
    }), "target_kSpaceCleanTests")

    # ========== Project ==========
    project_id = add(("PBXProject", {
        "name": "kSpaceClean",
        "buildConfigurationList": proj_config_list_id,
        "compatibilityVersion": '"Xcode 14.0"',
        "developmentRegion": "en",
        "hasScannedForEncodings": 0,
        "knownRegions": ["en", "Base", "zh-Hans", "ja"],
        "mainGroup": root_group_id,
        "packageReferences": [(package_ref_id, "kFoundation")],
        "productRefGroup": group_ids["Products"],
        "projectDirPath": '""',
        "projectRoot": '""',
        "targets": [(main_target_id, "kSpaceClean"), (test_target_id, "kSpaceCleanTests")],
        "attributes": {
            "BuildIndependentTargetsInParallel": 1,
            "LastSwiftUpdateCheck": 1430,
            "LastUpgradeCheck": 1430,
            "TargetAttributes": {
                main_target_id: {"CreatedOnToolsVersion": "14.3"},
                test_target_id: {"CreatedOnToolsVersion": "14.3", "TestTargetID": main_target_id},
            },
        },
    }), "project_object")

    # Set Features group children
    features_children = []
    for sub in ["AIClassifier", "Cleanup", "Common", "Components", "DesignSystem", "Models", "DiskGalaxy", "LargeOldFile", "DuplicateFile",
                 "AppUninstall", "PrivacyClean", "PhotoClean", "Maintenance",
                 "Onboarding", "RightPanel", "Settings", "SmartScan"]:
        features_children.append((group_ids[sub], sub))
    objects[group_ids["Features"]][1]["children"] = features_children

    # Set root group children
    root_children = []
    for gname in ["App", "Features", "FinderExtension", "Intents", "LaunchAgent",
                   "LiveActivity", "MenuBar", "Persistence", "Resources", "Spotlight",
                   "Store", "Widgets", "Tests", "Products", "Frameworks"]:
        root_children.append((group_ids[gname], gname))
    # Add static files to root
    for fpath in static_files:
        fname = os.path.basename(fpath)
        root_children.append((oid(f"ref_{fpath}"), fname))
    objects[root_group_id][1]["children"] = root_children

    # ========== Write Output ==========
    os.makedirs(os.path.dirname(PROJECT_FILE), exist_ok=True)

    section_order = [
        "PBXBuildFile", "PBXContainerItemProxy", "PBXFileReference",
        "PBXFrameworksBuildPhase", "PBXGroup", "PBXNativeTarget",
        "PBXProject", "PBXResourcesBuildPhase", "PBXSourcesBuildPhase",
        "PBXTargetDependency", "XCBuildConfiguration", "XCConfigurationList",
        "XCLocalSwiftPackageReference", "XCSwiftPackageProductDependency",
    ]

    lines = ["// !$*UTF8*$!", "{",
             "\tarchiveVersion = 1;",
             "\tclasses = {", "\t};",
             "\tobjectVersion = 56;",
             "\tobjects = {"]

    by_isa = {}
    for oid_key, (isa, props) in objects.items():
        if isa not in by_isa:
            by_isa[isa] = {}
        by_isa[isa][oid_key] = props

    for isa_name in section_order:
        if isa_name not in by_isa:
            continue
        lines.append(f"\n/* Begin {isa_name} section */")
        for oid_key in sorted(by_isa[isa_name].keys()):
            props = by_isa[isa_name][oid_key]
            # Generate comment from name or path
            comment_str = props.get("name", props.get("path", oid_key))
            lines.append(f"\t{oid_key}{fmt_comment(comment_str)} = {{")
            lines.append(f"\t\tisa = {isa_name};")
            for key in sorted(props.keys()):
                val = props[key]
                if key == "buildSettings":
                    # Special handling for build settings
                    bs_text = fmt_build_settings(val, indent=2)
                    lines.append(f"\t\t{key} = {bs_text};")
                elif key == "attributes":
                    # Attributes dict
                    lines.append(f"\t\t{key} = {{")
                    for ak, av in val.items():
                        if ak == "TargetAttributes":
                            lines.append(f"\t\t\t{ak} = {{")
                            for tid, tattrs in av.items():
                                # Find name for this target
                                tname = "kSpaceClean"
                                if tid in objects:
                                    tname = objects[tid][1].get("name", "target")
                                tattrs_str = "{"
                                for tk, tv in tattrs.items():
                                    if isinstance(tv, int):
                                        tattrs_str += f"{tk} = {tv}; "
                                    elif isinstance(tv, str):
                                        tattrs_str += f"{tk} = {tv}; "
                                    else:
                                        tattrs_str += f"{tk} = {tv}; "
                                tattrs_str += "}"
                                lines.append(f"\t\t\t\t{tid}{fmt_comment(tname)} = {tattrs_str};")
                            lines.append(f"\t\t\t}};")
                        elif isinstance(av, int):
                            lines.append(f"\t\t\t{ak} = {av};")
                        else:
                            lines.append(f"\t\t\t{ak} = {av};")
                    lines.append(f"\t\t}};")
                elif key == "buildSettings":
                    pass  # handled above
                elif isinstance(val, list):
                    if not val:
                        lines.append(f"\t\t{key} = (")
                        lines.append(f"\t\t);")
                    else:
                        lines.append(f"\t\t{key} = (")
                        for item in val:
                            if isinstance(item, tuple) and len(item) == 2:
                                ref, cmt = item[0], item[1]
                                # Check if ref is a known object
                                obj_name = cmt if cmt else (ref if ref else "")
                                lines.append(f"\t\t\t{ref}{fmt_comment(obj_name)},")
                            elif isinstance(item, tuple):
                                # Single element tuple
                                lines.append(f"\t\t\t{item[0]},")
                            else:
                                lines.append(f"\t\t\t{item},")
                        lines.append(f"\t\t);")
                elif isinstance(val, dict):
                    lines.append(f"\t\t{key} = {{")
                    for dk, dv in val.items():
                        if isinstance(dv, int):
                            lines.append(f"\t\t\t{dk} = {dv};")
                        elif isinstance(dv, list):
                            lines.append(f"\t\t\t{dk} = (")
                            for dvi in dv:
                                if isinstance(dvi, tuple):
                                    lines.append(f"\t\t\t\t{dvi[0]}{fmt_comment(dvi[1])},")
                                else:
                                    lines.append(f"\t\t\t\t{dvi},")
                            lines.append(f"\t\t\t);")
                        else:
                            lines.append(f"\t\t\t{dk} = {q(dv)};")
                    lines.append(f"\t\t}};")
                elif isinstance(val, bool):
                    lines.append(f"\t\t{key} = {'1' if val else '0'};")
                elif isinstance(val, int):
                    lines.append(f"\t\t{key} = {val};")
                elif isinstance(val, str):
                    lines.append(f"\t\t{key} = {q(val)};")
                else:
                    lines.append(f"\t\t{key} = {val};")
            lines.append(f"\t}};")
        lines.append(f"/* End {isa_name} section */")

    lines.append("\t};")
    lines.append(f"\trootObject = {project_id}{fmt_comment('Project object')};")
    lines.append("}")

    content = "\n".join(lines)

    with open(PROJECT_FILE, "w") as f:
        f.write(content)

    print(f"Generated: {PROJECT_FILE}")
    print(f"Total objects: {len(objects)}")
    print(f"Main build files: {len(main_build_files)}")
    print(f"Test build files: {len(test_build_files)}")
    print(f"BASE resolved to: {BASE}")

if __name__ == "__main__":
    main()
