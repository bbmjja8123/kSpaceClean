#!/usr/bin/env python3
"""Generate kFresh.xcodeproj/project.pbxproj manually — proper OpenStep plist format."""

import os, hashlib

BASE = os.path.dirname(os.path.abspath(__file__))
PROJECT_FILE = f"{BASE}/kFresh.xcodeproj/project.pbxproj"

def hash_id(seed, length=24):
    return hashlib.sha256(seed.encode()).hexdigest()[:length].upper()

def q(v):
    if v is None:
        return '""'
    if not isinstance(v, str):
        return str(v)
    if v == "":
        return '""'
    if v.startswith('"') and v.endswith('"') and len(v) > 1:
        return v
    special = '{}()=,; \t\n<>+'
    if any(c in v for c in special):
        return f'"{v}"'
    return v

def fmt_comment(s):
    return f" /* {s} */"

def fmt_build_settings(settings, indent=2):
    tab = "\t" * indent
    lines = ["{"]
    for key in sorted(settings.keys()):
        val = settings[key]
        if isinstance(val, list):
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
    root_group_id = add(("PBXGroup", {"name": "kFresh", "path": "", "sourceTree": "<group>",
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

    group_defs = {
        "App": make_group("App"),
        "Core": make_group("Core"),
        "Detect": make_group("Detect"),
        "Clean": make_group("Clean"),
        "Rules": make_group("Rules"),
        "Startup": make_group("Startup"),
        "StartupItems": make_group("StartupItems"),
        "Features": make_group("Features"),
        "AppList": make_group("AppList"),
        "DeepClean": make_group("DeepClean"),
        "Detail": make_group("Detail"),
        "Common": make_group("Common"),
        "History": make_group("History"),
        "Onboarding": make_group("Onboarding"),
        "Settings": make_group("Settings"),
        "FinderExtension": make_group("FinderExtension"),
        "Intents": make_group("Intents"),
        "Data": make_group("Data"),
        "DS_DesignSystem": make_group("DesignSystem"),
        "MenuBar": make_group("MenuBar"),
        "Resources": make_group("Resources"),
        "Store": make_group("Store"),
        "Widgets": make_group("Widgets"),
        "Tests": make_group("Tests"),
        "DetectTests": make_group("DetectTests"),
        "CleanTests": make_group("CleanTests"),
        "RulesTests": make_group("RulesTests"),
        "IntegrationTests": make_group("IntegrationTests"),
        "OnboardingTests": make_group("OnboardingTests"),
        "AppListTests": make_group("AppListTests"),
        "DetailTests": make_group("DetailTests"),
        "HistoryTests": make_group("HistoryTests"),
        "StartupTests": make_group("StartupTests"),
        "DeepCleanTests": make_group("DeepCleanTests"),
        "StoreTests": make_group("StoreTests"),
        "UITests": make_group("UITests"),
        "Products": make_group("Products"),
    }

    group_ids = {}
    for gname in group_defs:
        gid = add(group_defs[gname], f"grp_{gname}")
        group_ids[gname] = gid

    # ========== File references and build files ==========
    swift_files = [
        ("App/kFreshApp.swift", "App"),
        ("App/AppState.swift", "App"),
        ("App/RootView.swift", "App"),
        ("App/AppCoordinator.swift", "App"),
        ("App/AppServices.swift", "App"),
        ("Core/Detect/InstalledApp.swift", "Detect"),
        ("Core/Detect/AppCatalogService.swift", "Detect"),
        ("Core/Detect/ResidueDetector.swift", "Detect"),
        ("Core/Detect/BundleRuleStore.swift", "Detect"),
        ("Core/Detect/DirectorySizeCalculator.swift", "Detect"),
        ("Core/Rules/KFreshBundleRule.swift", "Rules"),
        ("Core/Rules/CaskParser.swift", "Rules"),
        ("Core/Clean/TrashMover.swift", "Clean"),
        ("Core/Clean/ResidueScanner.swift", "Clean"),
        ("Core/Clean/AuditLogger.swift", "Clean"),
        ("Data/BackupManager.swift", "Data"),
        ("Data/UninstallHistoryRepository.swift", "Data"),
        ("Data/FDAuthorizer.swift", "Data"),
        ("Features/AppList/AppListViewModel.swift", "AppList"),
        ("Features/AppList/AppListView.swift", "AppList"),
        ("Features/AppList/AppListSidebar.swift", "AppList"),
        ("Features/AppList/AppRowView.swift", "AppList"),
        ("Features/AppList/ScanProgressBanner.swift", "AppList"),
        ("Features/AppList/HistoryRow.swift", "AppList"),
        ("Features/Common/EmptyStateView.swift", "Common"),
        ("Features/Common/LoadingStateView.swift", "Common"),
        ("Features/Common/BrandStyles.swift", "Common"),
        ("Features/Common/BrandButtonStyle.swift", "Common"),
        ("Features/Common/WindowFrames.swift", "Common"),
        ("Features/DeepClean/DeepCleanEngine.swift", "DeepClean"),
        ("Features/DeepClean/DeepCleanViewModel.swift", "DeepClean"),
        ("Features/DeepClean/DeepCleanView.swift", "DeepClean"),
        ("Features/DeepClean/SystemCleanGroupView.swift", "DeepClean"),
        ("Features/DeepClean/SystemCleanRowView.swift", "DeepClean"),
        ("Features/Detail/AppDetailView.swift", "Detail"),
        ("Features/Detail/DetailViewModel.swift", "Detail"),
        ("Features/Detail/ResidueSectionView.swift", "Detail"),
        ("Features/Detail/UninstallConfirmSheet.swift", "Detail"),
        ("Features/Detail/UninstallToast.swift", "Detail"),
        ("Features/History/HistoryView.swift", "History"),
        ("Features/History/HistoryViewModel.swift", "History"),
        ("Features/History/HistoryRowView.swift", "History"),
        ("Features/Onboarding/FDAGuideController.swift", "Onboarding"),
        ("Features/Onboarding/FDAGuideView.swift", "Onboarding"),
        ("Features/Onboarding/FDAGuidePage.swift", "Onboarding"),
        ("Features/Onboarding/FDAPermissionProbe.swift", "Onboarding"),
        ("Features/Settings/SettingsView.swift", "Settings"),
        ("Features/Settings/SettingsViewModel.swift", "Settings"),
        ("Features/Settings/AboutView.swift", "Settings"),
        ("Core/Startup/StartupItemManager.swift", "Startup"),
        ("Features/StartupItems/StartupItemsView.swift", "StartupItems"),
        ("Features/StartupItems/StartupItemsViewModel.swift", "StartupItems"),
        ("Features/StartupItems/StartupItemRowView.swift", "StartupItems"),
        ("Store/StoreDefinitions.swift", "Store"),
        ("Store/StoreManager.swift", "Store"),
        ("Store/PaywallView.swift", "Store"),
        ("Store/ProGateModifier.swift", "Store"),
        ("MenuBar/MenuBarController.swift", "MenuBar"),
        ("Intents/UninstallAppIntent.swift", "Intents"),
        ("Intents/ScanResidueIntent.swift", "Intents"),
        ("Intents/DeepCleanIntent.swift", "Intents"),
        ("FinderExtension/FinderSync.swift", "FinderExtension"),
        ("Widgets/AppUsageWidget.swift", "Widgets"),
        ("Widgets/QuickUninstallWidget.swift", "Widgets"),
        ("Data/Models/UninstallHistory+CoreDataClass.swift", "Data"),
        ("Data/Models/UninstallHistory+CoreDataProperties.swift", "Data"),
        # DesignSystem source files (included directly, not as Swift Package)
        ("../kFoundation/Sources/DesignSystem/Colors.swift", "DS_DesignSystem"),
        ("../kFoundation/Sources/DesignSystem/Icons.swift", "DS_DesignSystem"),
        ("../kFoundation/Sources/DesignSystem/Typography.swift", "DS_DesignSystem"),
        ("../kFoundation/Sources/DesignSystem/Radius.swift", "DS_DesignSystem"),
        ("../kFoundation/Sources/DesignSystem/Shadow.swift", "DS_DesignSystem"),
        ("../kFoundation/Sources/DesignSystem/Spacing.swift", "DS_DesignSystem"),
        ("../kFoundation/Sources/DesignSystem/Animation.swift", "DS_DesignSystem"),
    ]

    test_file_groups = {
        "DetectTests": [
            "InstalledAppTests.swift",
            "AppCatalogServiceTests.swift",
            "ResidueDetectorTests.swift",
            "AppSourceClassifierTests.swift",
            "DirectorySizeCalculatorTests.swift",
        ],
        "RulesTests": [
            "CaskParserTests.swift",
            "BundleRuleStoreTests.swift",
        ],
        "CleanTests": [
            "TrashMoverTests.swift",
            "BackupManagerTests.swift",
            "ResidueScannerTests.swift",
            "AuditLoggerTests.swift",
        ],
        "OnboardingTests": [
            "FDAPermissionProbeTests.swift",
            "FDAGuideControllerTests.swift",
            "OnboardingRoutingTests.swift",
        ],
        "AppListTests": [
            "AppListViewModelTests.swift",
            "AppListFilterSortTests.swift",
        ],
        "DetailTests": [
            "DetailViewModelTests.swift",
            "UninstallSafetyCheckTests.swift",
            "UninstallConfirmSheetTests.swift",
            "UninstallConfirmFlowTests.swift",
        ],
        "HistoryTests": [
            "HistoryViewModelTests.swift",
        ],
        "StartupTests": [
            "StartupItemManagerTests.swift",
            "StartupItemsViewModelTests.swift",
        ],
        "DeepCleanTests": [
            "DeepCleanEngineTests.swift",
            "DeepCleanViewModelTests.swift",
        ],
        "StoreTests": [
            "StoreManagerTests.swift",
            "ProGateModifierTests.swift",
        ],
        "IntegrationTests": [
            "UninstallFlowTests.swift",
            "SandboxDegradationTests.swift",
        ],
        "UITests": [
            "OnboardingUITests.swift",
            "AppListUITests.swift",
            "ProGateUITests.swift",
        ],
    }

    test_build_files = []
    for sub_grp, files in test_file_groups.items():
        for tf in files:
            tdir = f"Tests/{sub_grp}"
            tpath = f"{tdir}/{tf}"
            gid = group_ids[sub_grp]
            ref_id = add(make_fileref(tf, tpath, last="sourcecode.swift"), f"ref_{tpath}")
            bf_id = add(make_buildfile(ref_id), f"bf_{tpath}")
            objects[gid][1]["children"].append((ref_id, tf))
            test_build_files.append(bf_id)

    static_files = [
        "Info.plist",
        "kFresh.entitlements",
        "kFreshDebug.entitlements",
        "Configuration.storekit",
    ]

    resource_dirs = [
        ("Assets.xcassets", "Resources", "folder.assetcatalog"),
        ("Localizable.xcstrings", "Resources", "text.json.xcstrings"),
        ("PrivacyInfo.xcprivacy", "Resources", "text.plist.xml"),
        ("cask_rules.json", "Resources", "text.json"),
    ]

    main_build_files = []

    for sf_path, grp in swift_files:
        fname = os.path.basename(sf_path)
        gid = group_ids[grp]
        ext = os.path.splitext(sf_path)[1]
        if ext == ".swift":
            lkft = "sourcecode.swift"
        elif ext == ".plist":
            lkft = "text.plist.xml"
        else:
            lkft = "text.json.xcstrings"

        ref_id = add(make_fileref(fname, sf_path, last=lkft), f"ref_{sf_path}")
        bf_id = add(make_buildfile(ref_id), f"bf_{sf_path}")
        objects[gid][1]["children"].append((ref_id, fname))
        main_build_files.append(bf_id)

    for fpath in static_files:
        fname = os.path.basename(fpath)
        if fpath.endswith(".plist"):
            lkft = "text.plist.xml"
        elif fpath.endswith(".storekit"):
            lkft = "text.json"
        else:
            lkft = "text.plist.entitlements"
        ref_id = add(make_fileref(fname, fpath, last=lkft), f"ref_{fpath}")
        objects[root_group_id][1]["children"].append((ref_id, fname))

    resource_refs = []
    for rname, rgrp, rtype in resource_dirs:
        rpath = f"Resources/{rname}"
        gid = group_ids[rgrp]
        ref_id = add(make_fileref(rname, rpath, last=rtype), f"ref_{rpath}")
        bf_id = add(make_buildfile(ref_id), f"bf_{rpath}")
        objects[gid][1]["children"].append((ref_id, rname))
        resource_refs.append(bf_id)

    # ========== Products ==========
    app_product_id = add(make_fileref("kFresh.app", "kFresh.app",
                                        explicit='"wrapper.application"', includeInIndex=0,
                                        sourceTree="BUILT_PRODUCTS_DIR"), "prod_app")
    test_product_id = add(make_fileref("kFreshTests.xctest", "kFreshTests.xctest",
                                         explicit='"wrapper.cfbundle"', includeInIndex=0,
                                         sourceTree="BUILT_PRODUCTS_DIR"), "prod_test")

    objects[group_ids["Products"]][1]["children"] = [
        (app_product_id, "kFresh.app"), (test_product_id, "kFreshTests.xctest")]

    # (Swift Package section removed — DesignSystem sources included directly)

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

    main_debug_id = add(("XCBuildConfiguration", {
        "name": "Debug",
        "buildSettings": {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "CODE_SIGNING_ALLOWED": "NO",
            "CODE_SIGN_STYLE": "Manual",
            "COMBINE_HIDPI_IMAGES": "YES",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": "Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": "kFresh",
            "INFOPLIST_KEY_CFBundleIdentifier": "app.kraftly.kfresh",
            "INFOPLIST_KEY_CFBundleName": "kFresh",
            "INFOPLIST_KEY_CFBundlePackageType": '"APPL"',
            "INFOPLIST_KEY_CFBundleShortVersionString": '"1.0"',
            "INFOPLIST_KEY_CFBundleVersion": "1",
            "INFOPLIST_KEY_LSMinimumSystemVersion": "13.0",
            "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.kfresh",
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
            "CODE_SIGN_ENTITLEMENTS": "kFresh.entitlements",
            "CODE_SIGN_IDENTITY": '"-"',
            "CODE_SIGN_STYLE": "Manual",
            "COMBINE_HIDPI_IMAGES": "YES",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": "Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": "kFresh",
            "INFOPLIST_KEY_CFBundleIdentifier": "app.kraftly.kfresh",
            "INFOPLIST_KEY_CFBundleName": "kFresh",
            "INFOPLIST_KEY_CFBundlePackageType": '"APPL"',
            "INFOPLIST_KEY_CFBundleShortVersionString": '"1.0"',
            "INFOPLIST_KEY_CFBundleVersion": "1",
            "INFOPLIST_KEY_LSMinimumSystemVersion": "13.0",
            "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.kfresh",
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
            "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.kfresh.tests",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "macosx",
            "SWIFT_VERSION": "5.0",
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/kFresh.app/Contents/MacOS/kFresh"',
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
            "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.kfresh.tests",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "macosx",
            "SWIFT_VERSION": "5.0",
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/kFresh.app/Contents/MacOS/kFresh"',
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
        "remoteGlobalIDString": oid("target_kFresh"),
        "remoteInfo": "kFresh",
    }), "cip_main")

    target_dep_id = add(("PBXTargetDependency", {
        "name": "kFresh",
        "target": oid("target_kFresh"),
        "targetProxy": cip_id,
    }), "dep_main")

    # ========== Targets ==========
    main_target_id = add(("PBXNativeTarget", {
        "name": "kFresh",
        "productName": "kFresh",
        "productReference": app_product_id,
        "productType": '"com.apple.product-type.application"',
        "buildConfigurationList": main_config_list_id,
        "buildPhases": [(main_sources_phase_id, "Sources"),
                        (main_frameworks_phase_id, "Frameworks"),
                        (main_resources_phase_id, "Resources")],
        "buildRules": [],
        "dependencies": [],
        "packageProductDependencies": [],
    }), "target_kFresh")

    test_target_id = add(("PBXNativeTarget", {
        "name": "kFreshTests",
        "productName": "kFreshTests",
        "productReference": test_product_id,
        "productType": '"com.apple.product-type.bundle.unit-test"',
        "buildConfigurationList": test_config_list_id,
        "buildPhases": [(test_sources_phase_id, "Sources"),
                        (test_frameworks_phase_id, "Frameworks")],
        "buildRules": [],
        "dependencies": [(target_dep_id, "kFresh")],
    }), "target_kFreshTests")

    # ========== Project ==========
    project_id = add(("PBXProject", {
        "name": "kFresh",
        "buildConfigurationList": proj_config_list_id,
        "compatibilityVersion": '"Xcode 14.0"',
        "developmentRegion": "en",
        "hasScannedForEncodings": 0,
        "knownRegions": ["en", "Base", "zh-Hans", "ja"],
        "mainGroup": root_group_id,
        "productRefGroup": group_ids["Products"],
        "projectDirPath": '""',
        "projectRoot": '""',
        "targets": [(main_target_id, "kFresh"), (test_target_id, "kFreshTests")],
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

    # Set Core group children
    core_children = []
    for sub in ["Detect", "Clean", "Rules", "Startup"]:
        core_children.append((group_ids[sub], sub))
    objects[group_ids["Core"]][1]["children"] = core_children

    # Set Features group children
    features_children = []
    for sub in ["AppList", "Common", "DeepClean", "Detail", "History", "Onboarding", "Settings", "StartupItems"]:
        features_children.append((group_ids[sub], sub))
    objects[group_ids["Features"]][1]["children"] = features_children

    # Set Tests group children
    tests_children = []
    for sub in ["DetectTests", "CleanTests", "RulesTests", "IntegrationTests", "OnboardingTests", "AppListTests", "DetailTests", "HistoryTests", "StartupTests", "DeepCleanTests", "StoreTests", "UITests"]:
        tests_children.append((group_ids[sub], sub))
    objects[group_ids["Tests"]][1]["children"] = tests_children

    # Set root group children
    root_children = []
    for gname in ["App", "Core", "DS_DesignSystem", "Data", "Features", "FinderExtension", "Intents",
                   "MenuBar", "Resources", "Store", "Widgets", "Tests",
                   "Products"]:
        root_children.append((group_ids[gname], gname))
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
            comment_str = props.get("name", props.get("path", oid_key))
            lines.append(f"\t{oid_key}{fmt_comment(comment_str)} = {{")
            lines.append(f"\t\tisa = {isa_name};")
            for key in sorted(props.keys()):
                val = props[key]
                if key == "buildSettings":
                    bs_text = fmt_build_settings(val, indent=2)
                    lines.append(f"\t\t{key} = {bs_text};")
                elif key == "attributes":
                    lines.append(f"\t\t{key} = {{")
                    for ak, av in val.items():
                        if ak == "TargetAttributes":
                            lines.append(f"\t\t\t{ak} = {{")
                            for tid, tattrs in av.items():
                                tname = "kFresh"
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
                elif isinstance(val, list):
                    if not val:
                        lines.append(f"\t\t{key} = (")
                        lines.append(f"\t\t);")
                    else:
                        lines.append(f"\t\t{key} = (")
                        for item in val:
                            if isinstance(item, tuple) and len(item) == 2:
                                ref, cmt = item[0], item[1]
                                obj_name = cmt if cmt else (ref if ref else "")
                                lines.append(f"\t\t\t{ref}{fmt_comment(obj_name)},")
                            elif isinstance(item, tuple):
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

if __name__ == "__main__":
    main()
