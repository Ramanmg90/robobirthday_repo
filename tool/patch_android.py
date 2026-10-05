import os, re, sys

root = sys.argv[1]

# ---- AndroidManifest.xml ----
mf = os.path.join(root, "android/app/src/main/AndroidManifest.xml")
s = open(mf, encoding="utf8").read()

perms = """    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
"""
recv = """        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
assert "<application" in s and "</application>" in s
s = s.replace("<application", perms + "    <application", 1)
s = s.replace("</application>", recv + "    </application>", 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="RoboBirthday"', s, count=1)
open(mf, "w", encoding="utf8").write(s)

# ---- build.gradle(.kts): core library desugaring ----
app = os.path.join(root, "android/app")
kts = os.path.join(app, "build.gradle.kts")
groovy = os.path.join(app, "build.gradle")

if os.path.exists(kts):
    g = open(kts, encoding="utf8").read()
    assert re.search(r"compileOptions\s*\{", g), "compileOptions not found"
    g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
    g += '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    open(kts, "w", encoding="utf8").write(g)
elif os.path.exists(groovy):
    g = open(groovy, encoding="utf8").read()
    assert re.search(r"compileOptions\s*\{", g), "compileOptions not found"
    g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", g, count=1)
    g += "\n\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    open(groovy, "w", encoding="utf8").write(g)
else:
    raise SystemExit("no app build.gradle found")

print("Android patched OK")
