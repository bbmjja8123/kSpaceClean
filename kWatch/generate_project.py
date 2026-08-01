#!/usr/bin/env python3
"""Generate kWatch.xcodeproj/project.pbxproj manually — proper OpenStep plist format.

3 targets: kWatch (app), kWatchIntents (appex), kWatchTests (unit test bundle).
SPM wiring for kFoundation (local package, relativePath ../kFoundation):
  MetricsKit -> app + intents + tests; DesignSystem -> app only.
"""

import os, hashlib

BASE = os.path.dirname(os.path.abspath(__file__))
PROJECT_FILE = f"{BASE}/kWatch.xcodeproj/project.pbxproj"

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
    # plutil's OpenStep parser only accepts these chars in unquoted strings
    # (verified empirically: @, %, +, <, >, etc. must be quoted).
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$.:/-"
    if any(c not in allowed for c in v):
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
    root_group_id = add(("PBXGroup", {"name": "kWatch", "path": "", "sourceTree": "<group>",
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

    group_names = [
        "Alerts", "App", "DI", "Dashboard", "Data", "Diagnostics", "History",
        "Integrations", "Intents", "MenuBar", "Onboarding", "Processes",
        "Resources", "Settings", "Shared", "State", "Store", "Tests", "Products",
    ]
    group_ids = {}
    for gname in group_names:
        gid = add(make_group(gname), f"grp_{gname}")
        group_ids[gname] = gid

    # ========== App target sources (all kWatch sources except widget/liveactivity/test dirs) ==========
    app_files = [
        ("Alerts/AlertEditorView.swift", "Alerts"),
        ("Alerts/AlertsView.swift", "Alerts"),
        ("Alerts/AlertsViewModel.swift", "Alerts"),
        ("Alerts/NotificationScheduler.swift", "Alerts"),
        ("App/AppCoordinator.swift", "App"),
        ("App/kWatchApp.swift", "App"),
        ("App/kWatchAppDelegate.swift", "App"),
        ("DI/AppContainer.swift", "DI"),
        ("DI/LiveAppContainer.swift", "DI"),
        ("DI/TestAppContainer.swift", "DI"),
        ("Dashboard/DashboardView.swift", "Dashboard"),
        ("Dashboard/DashboardViewModel.swift", "Dashboard"),
        ("Dashboard/MetricCardView.swift", "Dashboard"),
        ("Dashboard/MetricCardViewModel.swift", "Dashboard"),
        ("Data/AlertEvaluator.swift", "Data"),
        ("Data/AlertRepository.swift", "Data"),
        ("Data/CoreDataStack.swift", "Data"),
        ("Data/HistoryRepository.swift", "Data"),
        ("Data/ManagedObjects.swift", "Data"),
        ("Data/MetricsRepository.swift", "Data"),
        ("Data/PreferencesRepository.swift", "Data"),
        ("Diagnostics/DiagnosticsExporter.swift", "Diagnostics"),
        ("Diagnostics/MetricKitSubscriber.swift", "Diagnostics"),
        ("History/HistoryView.swift", "History"),
        ("History/HistoryViewModel.swift", "History"),
        ("History/TrendChart.swift", "History"),
        ("Integrations/KWatchSpotlightIndexer.swift", "Integrations"),
        ("Intents/ExportDiagnosticsIntent.swift", "Intents"),
        ("Intents/IntentService.swift", "Intents"),
        ("Intents/KWatchAppShortcuts.swift", "Intents"),
        ("Intents/LiveIntentService.swift", "Intents"),
        ("Intents/OpenDashboardIntent.swift", "Intents"),
        ("Intents/QueryMetricIntent.swift", "Intents"),
        ("Intents/ShowDiskUsageIntent.swift", "Intents"),
        ("Intents/ShowNetworkRateIntent.swift", "Intents"),
        ("Intents/ShowTopProcessesIntent.swift", "Intents"),
        ("Intents/StartMonitoringIntent.swift", "Intents"),
        ("Intents/StopMonitoringIntent.swift", "Intents"),
        ("Intents/StubIntentService.swift", "Intents"),
        ("MenuBar/MenuBarView.swift", "MenuBar"),
        ("MenuBar/MenuBarViewModel.swift", "MenuBar"),
        ("MenuBar/MetricMenuRow.swift", "MenuBar"),
        ("MenuBar/MiniTrendChart.swift", "MenuBar"),
        ("Onboarding/CompletePage.swift", "Onboarding"),
        ("Onboarding/MenuBarCustomizePage.swift", "Onboarding"),
        ("Onboarding/OnboardingView.swift", "Onboarding"),
        ("Onboarding/OnboardingViewModel.swift", "Onboarding"),
        ("Onboarding/ProIntroPage.swift", "Onboarding"),
        ("Onboarding/WelcomePage.swift", "Onboarding"),
        ("Processes/ProcessRowView.swift", "Processes"),
        ("Processes/ProcessesView.swift", "Processes"),
        ("Processes/ProcessesViewModel.swift", "Processes"),
        ("Settings/AboutView.swift", "Settings"),
        ("Settings/MenuBarSettingsView.swift", "Settings"),
        ("Settings/SettingsView.swift", "Settings"),
        ("Settings/SettingsViewModel.swift", "Settings"),
        ("Shared/AppGroupConfiguration.swift", "Shared"),
        ("Shared/MenuBarMode.swift", "Shared"),
        ("Shared/SharedSnapshot.swift", "Shared"),
        ("Shared/SnapshotWriter.swift", "Shared"),
        ("State/AppState.swift", "State"),
        ("State/PurchaseState.swift", "State"),
        ("Store/PaywallView.swift", "Store"),
        ("Store/PaywallViewModel.swift", "Store"),
        ("Store/PurchaseButton.swift", "Store"),
        ("Store/StoreKitClient.swift", "Store"),
        ("Store/StoreManager.swift", "Store"),
        ("Store/SubscriptionTerms.swift", "Store"),
    ]

    # ========== Intents appex sources (Intents + the two extension-safe Shared files) ==========
    appex_shared = ["Shared/AppGroupConfiguration.swift", "Shared/MenuBarMode.swift", "Shared/SharedSnapshot.swift"]

    # ========== Test sources ==========
    test_files = [
        "AlertsViewModelTests.swift", "AppContainerTests.swift", "AppCoordinatorTests.swift",
        "AppShortcutsVerificationTests.swift", "CoreDataStackTests.swift", "DashboardViewModelTests.swift",
        "DiagnosticsExporterTests.swift", "HistoryViewModelTests.swift", "IntentParameterTests.swift",
        "IntentTests.swift", "MetricCardViewModelTests.swift", "NotificationSchedulerTests.swift",
        "OnboardingViewModelTests.swift", "PaywallViewModelTermsTests.swift",
        "PreferencesRepositoryTests.swift", "ProcessesViewModelTests.swift", "RepositoryTests.swift",
        "RestorePurchaseStubs.swift", "SettingsViewModelRestoreTests.swift",
        "SettingsViewModelTests.swift", "SnapshotRoundTripTests.swift",
        "SnapshotWriterTests.swift", "StoreManagerTests.swift",
    ]

    static_files = [
        "Info.plist",
        "kWatch.entitlements",
    ]

    resource_dirs = [
        ("Localizable.xcstrings", "Resources", "text.json.xcstrings"),
        ("PrivacyInfo.xcprivacy", "Resources", "text.plist.xml"),
    ]

    main_build_files = []
    file_ref_of_path = {}

    for sf_path, grp in app_files:
        fname = os.path.basename(sf_path)
        gid = group_ids[grp]
        ref_id = add(make_fileref(fname, sf_path, last="sourcecode.swift"), f"ref_{sf_path}")
        bf_id = add(make_buildfile(ref_id), f"bf_{sf_path}")
        objects[gid][1]["children"].append((ref_id, fname))
        main_build_files.append(bf_id)
        file_ref_of_path[sf_path] = ref_id

    # Appex build files (share file refs for the two Shared files)
    appex_build_files = []
    for sf_path, _grp in app_files:
        if sf_path.startswith("Intents/"):
            ref_id = file_ref_of_path[sf_path]
            bf_id = add(make_buildfile(ref_id), f"bf_appex_{sf_path}")
            appex_build_files.append(bf_id)
    for sf_path in appex_shared:
        ref_id = file_ref_of_path[sf_path]
        bf_id = add(make_buildfile(ref_id), f"bf_appex_{sf_path}")
        appex_build_files.append(bf_id)

    test_build_files = []
    for tf in test_files:
        tpath = f"Tests/{tf}"
        ref_id = add(make_fileref(tf, tpath, last="sourcecode.swift"), f"ref_{tpath}")
        bf_id = add(make_buildfile(ref_id), f"bf_{tpath}")
        objects[group_ids["Tests"]][1]["children"].append((ref_id, tf))
        test_build_files.append(bf_id)

    for fpath in static_files:
        fname = os.path.basename(fpath)
        if fpath.endswith(".plist"):
            lkft = "text.plist.xml"
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

    # ========== SPM: local package + product dependencies ==========
    # Matches kSpaceClean's proven-working wiring (Xcode 14.3.1 / macOS 13.3 SDK):
    # absolute relativePath, empty Frameworks phases, `/* kFoundation */` comment.
    package_ref_id = add(("XCLocalSwiftPackageReference", {
        "relativePath": "/Users/mengjianjun/Documents/ai/aicoding/macapp/kFoundation",
    }), "pkg_kFoundation")

    def make_pkg_product(product_name, seed):
        return add(("XCSwiftPackageProductDependency", {
            "package": package_ref_id,
            "productName": product_name,
        }), seed)

    prod_metrics_id = make_pkg_product("MetricsKit", "pkgprod_MetricsKit")
    prod_ds_id = make_pkg_product("DesignSystem", "pkgprod_DesignSystem")

    # ========== Local package folder reference (REQUIRED for Xcode 14 to resolve the package graph) ==========
    # kSpaceClean has a PBXFileReference (lastKnownFileType = folder) to the package dir
    # inside a "Frameworks" group; without it Xcode silently resolves an EMPTY package graph.
    pkg_folder_ref_id = add(("PBXFileReference", {
        "lastKnownFileType": "folder",
        "name": "kFoundation",
        "path": "/Users/mengjianjun/Documents/ai/aicoding/macapp/kFoundation",
        "sourceTree": '"<absolute>"',
    }), "ref_pkg_kFoundation")
    frameworks_group_id = add(make_group("Frameworks", [(pkg_folder_ref_id, "kFoundation")]),
                              "grp_Frameworks")

    # ========== Products ==========
    app_product_id = add(make_fileref("kWatch.app", "kWatch.app",
                                        explicit='"wrapper.application"', includeInIndex=0,
                                        sourceTree="BUILT_PRODUCTS_DIR"), "prod_app")
    appex_product_id = add(make_fileref("kWatchIntents.appex", "kWatchIntents.appex",
                                          explicit='"wrapper.app-extension"', includeInIndex=0,
                                          sourceTree="BUILT_PRODUCTS_DIR"), "prod_appex")
    test_product_id = add(make_fileref("kWatchTests.xctest", "kWatchTests.xctest",
                                         explicit='"wrapper.cfbundle"', includeInIndex=0,
                                         sourceTree="BUILT_PRODUCTS_DIR"), "prod_test")

    objects[group_ids["Products"]][1]["children"] = [
        (app_product_id, "kWatch.app"),
        (appex_product_id, "kWatchIntents.appex"),
        (test_product_id, "kWatchTests.xctest"),
    ]

    # ========== Build Phases ==========
    main_sources_phase_id = add(("PBXSourcesBuildPhase", {
        "buildActionMask": 2147483647, "files": [(fid, "") for fid in main_build_files],
        "runOnlyForDeploymentPostprocessing": 0
    }), "phase_main_sources")
    main_frameworks_phase_id = add(("PBXFrameworksBuildPhase", {
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0
    }), "phase_main_frameworks")
    main_resources_phase_id = add(("PBXResourcesBuildPhase", {
        "buildActionMask": 2147483647, "files": [(fid, "") for fid in resource_refs],
        "runOnlyForDeploymentPostprocessing": 0
    }), "phase_main_resources")

    appex_sources_phase_id = add(("PBXSourcesBuildPhase", {
        "buildActionMask": 2147483647, "files": [(fid, "") for fid in appex_build_files],
        "runOnlyForDeploymentPostprocessing": 0
    }), "phase_appex_sources")
    appex_frameworks_phase_id = add(("PBXFrameworksBuildPhase", {
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0
    }), "phase_appex_frameworks")
    appex_resources_phase_id = add(("PBXResourcesBuildPhase", {
        "buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0
    }), "phase_appex_resources")

    test_sources_phase_id = add(("PBXSourcesBuildPhase", {
        "buildActionMask": 2147483647, "files": [(fid, "") for fid in test_build_files],
        "runOnlyForDeploymentPostprocessing": 0
    }), "phase_test_sources")
    test_frameworks_phase_id = add(("PBXFrameworksBuildPhase", {
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0
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

    def make_target_config(name, settings, seed):
        return add(("XCBuildConfiguration", {
            "name": name,
            "buildSettings": settings,
        }), seed)

    main_debug_id = make_target_config("Debug", {
        "CODE_SIGNING_ALLOWED": "NO",
        "CODE_SIGN_STYLE": "Manual",
        "COMBINE_HIDPI_IMAGES": "YES",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": "Info.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": "kWatch",
        "INFOPLIST_KEY_CFBundleIdentifier": "app.kraftly.kwatch",
        "INFOPLIST_KEY_CFBundleName": "kWatch",
        "INFOPLIST_KEY_CFBundlePackageType": '"APPL"',
        "INFOPLIST_KEY_CFBundleShortVersionString": '"1.0"',
        "INFOPLIST_KEY_CFBundleVersion": "1",
        "INFOPLIST_KEY_LSMinimumSystemVersion": "13.0",
        "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.kwatch",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SDKROOT": "macosx",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
    }, "config_main_debug")

    main_release_id = make_target_config("Release", {
        "CODE_SIGN_IDENTITY": '"-"',
        "CODE_SIGN_STYLE": "Manual",
        "COMBINE_HIDPI_IMAGES": "YES",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": "Info.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": "kWatch",
        "INFOPLIST_KEY_CFBundleIdentifier": "app.kraftly.kwatch",
        "INFOPLIST_KEY_CFBundleName": "kWatch",
        "INFOPLIST_KEY_CFBundlePackageType": '"APPL"',
        "INFOPLIST_KEY_CFBundleShortVersionString": '"1.0"',
        "INFOPLIST_KEY_CFBundleVersion": "1",
        "INFOPLIST_KEY_LSMinimumSystemVersion": "13.0",
        "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.kwatch",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SDKROOT": "macosx",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
    }, "config_main_release")

    main_config_list_id = add(("XCConfigurationList", {
        "buildConfigurations": [(main_debug_id, "Debug"), (main_release_id, "Release")],
        "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"
    }), "configlist_main")

    appex_debug_id = make_target_config("Debug", {
        "APPLICATION_EXTENSION_API_ONLY": "YES",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_CFBundleDisplayName": "kWatchIntents",
        "INFOPLIST_KEY_CFBundleIdentifier": "app.kraftly.kwatch.intents",
        "INFOPLIST_KEY_CFBundlePackageType": '"XPC!"',
        "INFOPLIST_KEY_CFBundleShortVersionString": '"1.0"',
        "INFOPLIST_KEY_CFBundleVersion": "1",
        "INFOPLIST_KEY_NSExtensionPointIdentifier": "com.apple.app-intents-extension",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks",
                                    "@executable_path/../../../../Frameworks"],
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.kwatch.intents",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SDKROOT": "macosx",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
    }, "config_appex_debug")

    appex_release_id = make_target_config("Release", {
        "APPLICATION_EXTENSION_API_ONLY": "YES",
        "CODE_SIGN_IDENTITY": '"-"',
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_CFBundleDisplayName": "kWatchIntents",
        "INFOPLIST_KEY_CFBundleIdentifier": "app.kraftly.kwatch.intents",
        "INFOPLIST_KEY_CFBundlePackageType": '"XPC!"',
        "INFOPLIST_KEY_CFBundleShortVersionString": '"1.0"',
        "INFOPLIST_KEY_CFBundleVersion": "1",
        "INFOPLIST_KEY_NSExtensionPointIdentifier": "com.apple.app-intents-extension",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks",
                                    "@executable_path/../../../../Frameworks"],
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.kwatch.intents",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SDKROOT": "macosx",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
    }, "config_appex_release")

    appex_config_list_id = add(("XCConfigurationList", {
        "buildConfigurations": [(appex_debug_id, "Debug"), (appex_release_id, "Release")],
        "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"
    }), "configlist_appex")

    def make_test_config(name, settings, seed):
        base = {
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "GENERATE_INFOPLIST_FILE": "YES",
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "app.kraftly.kwatch.tests",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "macosx",
            "SWIFT_VERSION": "5.0",
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/kWatch.app/Contents/MacOS/kWatch"',
        }
        base.update(settings)
        return add(("XCBuildConfiguration", {
            "name": name,
            "buildSettings": base,
        }), seed)

    test_debug_id = make_test_config("Debug", {}, "config_test_debug")
    test_release_id = make_test_config("Release", {}, "config_test_release")

    test_config_list_id = add(("XCConfigurationList", {
        "buildConfigurations": [(test_debug_id, "Debug"), (test_release_id, "Release")],
        "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"
    }), "configlist_test")

    # ========== Target Dependencies ==========
    def make_proxy(remote_target_seed, remote_info, seed):
        return add(("PBXContainerItemProxy", {
            "containerPortal": oid("project_object"),
            "proxyType": 1,
            "remoteGlobalIDString": oid(remote_target_seed),
            "remoteInfo": remote_info,
        }), seed)

    def make_dep(name, target_seed, proxy_seed, dep_seed):
        proxy_id = make_proxy(target_seed, name, proxy_seed)
        dep_id = add(("PBXTargetDependency", {
            "name": name,
            "target": oid(target_seed),
            "targetProxy": proxy_id,
        }), dep_seed)
        return dep_id

    # Bisect gates: allow removing appex/test targets to isolate SPM resolution
    INCLUDE_APPEX = os.environ.get("INCLUDE_APPEX", "1") != "0"
    INCLUDE_TESTS = os.environ.get("INCLUDE_TESTS", "1") != "0"

    dep_app_intents = make_dep("kWatchIntents", "target_kWatchIntents", "cip_app_intents", "dep_app_intents")
    dep_test_app = make_dep("kWatch", "target_kWatch", "cip_test_app", "dep_test_app")
    dep_test_intents = make_dep("kWatchIntents", "target_kWatchIntents", "cip_test_intents", "dep_test_intents")

    # ========== Targets ==========
    main_target_id = add(("PBXNativeTarget", {
        "name": "kWatch",
        "productName": "kWatch",
        "productReference": app_product_id,
        "productType": '"com.apple.product-type.application"',
        "buildConfigurationList": main_config_list_id,
        "buildPhases": [(main_sources_phase_id, "Sources"),
                        (main_frameworks_phase_id, "Frameworks"),
                        (main_resources_phase_id, "Resources")],
        "buildRules": [],
        "dependencies": ([(dep_app_intents, "kWatchIntents")] if INCLUDE_APPEX else []),
        "packageProductDependencies": [(prod_metrics_id, "MetricsKit"), (prod_ds_id, "DesignSystem")],
    }), "target_kWatch")

    if INCLUDE_APPEX:
        appex_target_id = add(("PBXNativeTarget", {
            "name": "kWatchIntents",
            "productName": "kWatchIntents",
            "productReference": appex_product_id,
            "productType": '"com.apple.product-type.app-extension"',
            "buildConfigurationList": appex_config_list_id,
            "buildPhases": [(appex_sources_phase_id, "Sources"),
                            (appex_frameworks_phase_id, "Frameworks"),
                            (appex_resources_phase_id, "Resources")],
            "buildRules": [],
            "dependencies": [],
            "packageProductDependencies": [(prod_metrics_id, "MetricsKit")],
        }), "target_kWatchIntents")

    if INCLUDE_TESTS:
        test_deps = [(dep_test_app, "kWatch")]
        if INCLUDE_APPEX:
            test_deps.append((dep_test_intents, "kWatchIntents"))
        test_target_id = add(("PBXNativeTarget", {
            "name": "kWatchTests",
            "productName": "kWatchTests",
            "productReference": test_product_id,
            "productType": '"com.apple.product-type.bundle.unit-test"',
            "buildConfigurationList": test_config_list_id,
            "buildPhases": [(test_sources_phase_id, "Sources"),
                            (test_frameworks_phase_id, "Frameworks")],
            "buildRules": [],
            "dependencies": test_deps,
            "packageProductDependencies": [(prod_metrics_id, "MetricsKit")],
        }), "target_kWatchTests")

    # ========== Project ==========
    project_targets = [(main_target_id, "kWatch")]
    if INCLUDE_APPEX:
        project_targets.append((appex_target_id, "kWatchIntents"))
    if INCLUDE_TESTS:
        project_targets.append((test_target_id, "kWatchTests"))

    target_attrs = {main_target_id: {"CreatedOnToolsVersion": "14.3"}}
    if INCLUDE_APPEX:
        target_attrs[appex_target_id] = {"CreatedOnToolsVersion": "14.3"}
    if INCLUDE_TESTS:
        target_attrs[test_target_id] = {"CreatedOnToolsVersion": "14.3", "TestTargetID": main_target_id}

    project_id = add(("PBXProject", {
        "name": "kWatch",
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
        "targets": project_targets,
        "attributes": {
            "BuildIndependentTargetsInParallel": 1,
            "LastSwiftUpdateCheck": 1430,
            "LastUpgradeCheck": 1430,
            "TargetAttributes": target_attrs,
        },
    }), "project_object")

    # ========== Root group children ==========
    root_children = []
    for gname in group_names:
        if gname == "Products":
            continue
        root_children.append((group_ids[gname], gname))
    root_children.append((group_ids["Products"], "Products"))
    root_children.append((frameworks_group_id, "Frameworks"))
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
            comment = props.pop("_comment", props.get("name", props.get("path", oid_key)))
            lines.append(f"\t{oid_key}{fmt_comment(comment)} = {{")
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
                        elif isinstance(dv, tuple):
                            lines.append(f"\t\t\t{dk} = {dv[0]}{fmt_comment(dv[1])};")
                        else:
                            lines.append(f"\t\t\t{dk} = {q(dv)};")
                    lines.append(f"\t\t}};")
                elif isinstance(val, tuple):
                    lines.append(f"\t\t{key} = {val[0]}{fmt_comment(val[1])};")
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
    print(f"App build files: {len(main_build_files)}")
    print(f"Appex build files: {len(appex_build_files)}")
    print(f"Test build files: {len(test_build_files)}")
    print(f"Target IDs: kWatch={oid('target_kWatch')} kWatchIntents={oid('target_kWatchIntents')} kWatchTests={oid('target_kWatchTests')}")

if __name__ == "__main__":
    main()
