import json, os, re, shutil, subprocess, sys

PKG = 'com.bookease.bookease_app'
subprocess.check_call(['flutter', 'create', '--org', 'com.bookease', '--project-name',
                       'bookease_app', '--platforms', 'android', 'app'])
shutil.copy('pubspec.yaml', 'app/pubspec.yaml')
shutil.rmtree('app/lib')
shutil.copytree('lib', 'app/lib')
shutil.rmtree('app/test', ignore_errors=True)

try:
    g = json.load(open('google-services.json'))
except Exception:
    sys.exit('ERROR: google-services.json is missing from the repository root.')
c = g['client'][0]
pkg = c['client_info']['android_client_info']['package_name']
if pkg != PKG:
    sys.exit('ERROR: Firebase package name is "%s" but must be "%s". Register a new Android app in Firebase with the correct name and upload its google-services.json.' % (pkg, PKG))
pi = g['project_info']
open('app/lib/firebase_options.dart', 'w').write("""import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: '%s',
    appId: '%s',
    messagingSenderId: '%s',
    projectId: '%s',
    storageBucket: '%s',
  );
}
""" % (c['api_key'][0]['current_key'], c['client_info']['mobilesdk_app_id'],
       pi['project_number'], pi['project_id'], pi.get('storage_bucket', '')))

p = 'app/android/app/build.gradle'
s = open(p).read()
s, n = re.subn(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdkVersion 23', s)
if n == 0:
    sys.exit('ERROR: could not set minSdkVersion')
open(p, 'w').write(s)

p = 'app/android/app/src/main/AndroidManifest.xml'
m = open(p).read()
m = m.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="BookEase"', m, count=1)
open(p, 'w').write(m)
for d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']:
    src = 'icons/mipmap-%s/ic_launcher.png' % d
    dst = 'app/android/app/src/main/res/mipmap-%s/ic_launcher.png' % d
    if os.path.exists(src) and os.path.isdir(os.path.dirname(dst)):
        shutil.copy(src, dst)
print('Prepared OK')
