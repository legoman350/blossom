#!/usr/bin/env python3
"""Regenerates Blossom.xcodeproj from the files in Sources/, Tests/ and Resources/.

Run after adding or removing a source file:  python3 Tools/gen-xcodeproj.py
Object IDs are derived from file names, so re-running produces a stable diff.
"""
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent
def oid(name):  # stable 24-hex ID per logical object
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

sources = sorted(p.name for p in (root / "Sources").glob("*.swift"))
app_files = sources
test_files = ["LayoutEngine.swift"]  # from Sources
lines = []
def w(s=""): lines.append(s)

# --- file references
fref = {f: oid("fref:Sources/" + f) for f in sources}
fref_test = oid("fref:Tests/LayoutEngineTests.swift")
fref_assets = oid("fref:Resources/Assets.xcassets")
fref_app = oid("fref:Blossom.app")
fref_tool = oid("fref:LayoutEngineTests")
# --- build files
bf_app = {f: oid("bf:app:" + f) for f in app_files}
bf_assets = oid("bf:app:Assets.xcassets")
bf_tool_engine = oid("bf:tool:LayoutEngine.swift")
bf_tool_test = oid("bf:tool:LayoutEngineTests.swift")
# --- groups, targets, phases, configs
g_main, g_sources, g_tests, g_resources, g_products = (oid("g:" + n) for n in ("main", "Sources", "Tests", "Resources", "Products"))
t_app, t_tool = oid("t:Blossom"), oid("t:LayoutEngineTests")
ph = {n: oid("ph:" + n) for n in ("app.sources", "app.frameworks", "app.resources", "tool.sources", "tool.frameworks", "tool.copy")}
proj = oid("project")
cl_proj, cl_app, cl_tool = oid("cl:project"), oid("cl:Blossom"), oid("cl:LayoutEngineTests")
cfg = {f"{scope}.{c}": oid(f"cfg:{scope}:{c}") for scope in ("project", "app", "tool") for c in ("Debug", "Release")}

w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {")
w("\n/* Begin PBXBuildFile section */")
for f in app_files:
    w(f"\t\t{bf_app[f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref[f]} /* {f} */; }};")
w(f"\t\t{bf_assets} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {fref_assets} /* Assets.xcassets */; }};")
w(f"\t\t{bf_tool_engine} /* LayoutEngine.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {fref['LayoutEngine.swift']} /* LayoutEngine.swift */; }};")
w(f"\t\t{bf_tool_test} /* LayoutEngineTests.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {fref_test} /* LayoutEngineTests.swift */; }};")
w("/* End PBXBuildFile section */")

w("\n/* Begin PBXCopyFilesBuildPhase section */")
w(f"\t\t{ph['tool.copy']} /* CopyFiles */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = /usr/share/man/man1/;\n\t\t\tdstSubfolderSpec = 0;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 1;\n\t\t}};")
w("/* End PBXCopyFilesBuildPhase section */")

w("\n/* Begin PBXFileReference section */")
w(f"\t\t{fref_app} /* Blossom.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Blossom.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
w(f"\t\t{fref_tool} /* LayoutEngineTests */ = {{isa = PBXFileReference; explicitFileType = \"compiled.mach-o.executable\"; includeInIndex = 0; path = LayoutEngineTests; sourceTree = BUILT_PRODUCTS_DIR; }};")
w(f"\t\t{fref_assets} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
w(f"\t\t{fref_test} /* LayoutEngineTests.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LayoutEngineTests.swift; sourceTree = \"<group>\"; }};")
for f in sources:
    w(f"\t\t{fref[f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};")
w("/* End PBXFileReference section */")

w("\n/* Begin PBXFrameworksBuildPhase section */")
for key in ("app.frameworks", "tool.frameworks"):
    w(f"\t\t{ph[key]} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
w("/* End PBXFrameworksBuildPhase section */")

def group(gid, name, children, path=None, extra=""):
    w(f"\t\t{gid} /* {name} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (")
    for cid, cname in children:
        w(f"\t\t\t\t{cid} /* {cname} */,")
    w("\t\t\t);")
    if path: w(f"\t\t\tpath = {path};")
    else: w(f"\t\t\tname = {name};")
    w("\t\t\tsourceTree = \"<group>\";\n\t\t};")
w("\n/* Begin PBXGroup section */")
w(f"\t\t{g_main} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{g_sources} /* Sources */,\n\t\t\t\t{g_tests} /* Tests */,\n\t\t\t\t{g_resources} /* Resources */,\n\t\t\t\t{g_products} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
group(g_products, "Products", [(fref_app, "Blossom.app"), (fref_tool, "LayoutEngineTests")])
group(g_resources, "Resources", [(fref_assets, "Assets.xcassets")], path="Resources")
group(g_sources, "Sources", [(fref[f], f) for f in sources], path="Sources")
group(g_tests, "Tests", [(fref_test, "LayoutEngineTests.swift")], path="Tests")
w("/* End PBXGroup section */")

w("\n/* Begin PBXNativeTarget section */")
def target(tid, name, cl, phases, product, ptype):
    w(f"\t\t{tid} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {cl} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n\t\t\tbuildPhases = (")
    for pid, pname in phases: w(f"\t\t\t\t{pid} /* {pname} */,")
    w(f"\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = {name};\n\t\t\tproductName = {name};\n\t\t\tproductReference = {product[0]} /* {product[1]} */;\n\t\t\tproductType = \"{ptype}\";\n\t\t}};")
target(t_app, "Blossom", cl_app, [(ph["app.sources"], "Sources"), (ph["app.frameworks"], "Frameworks"), (ph["app.resources"], "Resources")],
       (fref_app, "Blossom.app"), "com.apple.product-type.application")
target(t_tool, "LayoutEngineTests", cl_tool, [(ph["tool.sources"], "Sources"), (ph["tool.frameworks"], "Frameworks"), (ph["tool.copy"], "CopyFiles")],
       (fref_tool, "LayoutEngineTests"), "com.apple.product-type.tool")
w("/* End PBXNativeTarget section */")

w("\n/* Begin PBXProject section */")
w(f"\t\t{proj} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1600;\n\t\t\t\tLastUpgradeCheck = 2700;\n\t\t\t}};")
w(f"\t\t\tbuildConfigurationList = {cl_proj} /* Build configuration list for PBXProject \"Blossom\" */;\n\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);")
w(f"\t\t\tmainGroup = {g_main};\n\t\t\tproductRefGroup = {g_products} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n\t\t\t\t{t_app} /* Blossom */,\n\t\t\t\t{t_tool} /* LayoutEngineTests */,\n\t\t\t);\n\t\t}};")
w("/* End PBXProject section */")

w("\n/* Begin PBXResourcesBuildPhase section */")
w(f"\t\t{ph['app.resources']} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t{bf_assets} /* Assets.xcassets in Resources */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
w("/* End PBXResourcesBuildPhase section */")

w("\n/* Begin PBXSourcesBuildPhase section */")
w(f"\t\t{ph['app.sources']} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (")
for f in app_files: w(f"\t\t\t\t{bf_app[f]} /* {f} in Sources */,")
w("\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};")
w(f"\t\t{ph['tool.sources']} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t{bf_tool_engine} /* LayoutEngine.swift in Sources */,\n\t\t\t\t{bf_tool_test} /* LayoutEngineTests.swift in Sources */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
w("/* End PBXSourcesBuildPhase section */")

def settings_block(cid, name, settings):
    w(f"\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{")
    for k in sorted(settings):
        v = settings[k]
        if isinstance(v, list):
            w(f"\t\t\t\t{k} = (")
            for item in v: w(f"\t\t\t\t\t{item},")
            w("\t\t\t\t);")
        else:
            w(f"\t\t\t\t{k} = {v};")
    w(f"\t\t\t}};\n\t\t\tname = {name};\n\t\t}};")

common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "DEAD_CODE_STRIPPING": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES", "MACOSX_DEPLOYMENT_TARGET": "13.0", "SDKROOT": "macosx",
    # Products land in ./build/Debug and ./build/Release, the same place build.sh uses.
    "SYMROOT": "\"$(SRCROOT)/build\"",
}
debug = dict(common, **{"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
                        "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "\"$(inherited) DEBUG\"",
                        "SWIFT_OPTIMIZATION_LEVEL": "\"-Onone\""})
release = dict(common, **{"DEBUG_INFORMATION_FORMAT": "\"dwarf-with-dsym\"", "ENABLE_NS_ASSERTIONS": "NO",
                          "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "\"-O\""})
app = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    # Same signer and identifier as build.sh, so the Accessibility grant covers both builds.
    "CODE_SIGN_IDENTITY": "\"Blossom Dev\"", "CODE_SIGN_STYLE": "Manual", "DEVELOPMENT_TEAM": "\"\"",
    "COMBINE_HIDPI_IMAGES": "YES", "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.1.0",
    "ENABLE_HARDENED_RUNTIME": "NO", "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Blossom", "INFOPLIST_KEY_LSApplicationCategoryType": "\"public.app-category.productivity\"",
    "INFOPLIST_KEY_LSUIElement": "YES", "INFOPLIST_KEY_NSHumanReadableCopyright": "\"\"",
    "LD_RUNPATH_SEARCH_PATHS": ["\"$(inherited)\"", "\"@executable_path/../Frameworks\""],
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.blossom.Blossom", "PRODUCT_NAME": "\"$(TARGET_NAME)\"", "SWIFT_VERSION": "5.0",
}
tool = {"CODE_SIGN_IDENTITY": "\"-\"", "CODE_SIGN_STYLE": "Manual", "PRODUCT_NAME": "\"$(TARGET_NAME)\"", "SWIFT_VERSION": "5.0"}

w("\n/* Begin XCBuildConfiguration section */")
settings_block(cfg["project.Debug"], "Debug", debug)
settings_block(cfg["project.Release"], "Release", release)
settings_block(cfg["app.Debug"], "Debug", app)
settings_block(cfg["app.Release"], "Release", app)
settings_block(cfg["tool.Debug"], "Debug", tool)
settings_block(cfg["tool.Release"], "Release", tool)
w("/* End XCBuildConfiguration section */")

w("\n/* Begin XCConfigurationList section */")
for cl, label, scope in ((cl_proj, "PBXProject \"Blossom\"", "project"), (cl_app, "PBXNativeTarget \"Blossom\"", "app"), (cl_tool, "PBXNativeTarget \"LayoutEngineTests\"", "tool")):
    w(f"\t\t{cl} /* Build configuration list for {label} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{cfg[scope + '.Debug']} /* Debug */,\n\t\t\t\t{cfg[scope + '.Release']} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};")
w("/* End XCConfigurationList section */")
w(f"\t}};\n\trootObject = {proj} /* Project object */;\n}}")

out = root / "Blossom.xcodeproj"
(out / "project.xcworkspace").mkdir(parents=True, exist_ok=True)
(out / "project.pbxproj").write_text("\n".join(lines) + "\n")
(out / "project.xcworkspace/contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')

def scheme(name, tid, buildable, launch_cfg):
    ref = f'''            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{tid}"
               BuildableName = "{buildable}"
               BlueprintName = "{name}"
               ReferencedContainer = "container:Blossom.xcodeproj">
            </BuildableReference>'''
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
{ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction
      buildConfiguration = "{launch_cfg}"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      allowLocationSimulation = "NO">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{ref.replace("            ", "            ")}
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
sd = out / "xcshareddata/xcschemes"
sd.mkdir(parents=True, exist_ok=True)
(sd / "Blossom.xcscheme").write_text(scheme("Blossom", t_app, "Blossom.app", "Debug"))
(sd / "LayoutEngineTests.xcscheme").write_text(scheme("LayoutEngineTests", t_tool, "LayoutEngineTests", "Debug"))
print("generated", len(sources), "sources")
