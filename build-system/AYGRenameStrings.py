# AYG: rename only the strings where "Telegram" means *this app on this device*.
# Anything about the Telegram service, network, servers, accounts, company,
# legal terms or products (Premium / Stars / Passport / Ads / Business / Gifts)
# is left alone — those statements are Telegram's, not AyuGram's.
import io, re, sys

KEYS = """
Tour.Title1 Tour.Text2 Tour.Text3 Tour.Text4 Tour.Text5 Tour.Text6
Contacts.AccessDeniedError Contacts.AccessDeniedHelpLandscape Contacts.AccessDeniedHelpPortrait
Contacts.PermissionsText Contacts.LimitedAccess.Text
AccessDenied.Contacts AccessDenied.VoiceMicrophone AccessDenied.VideoMicrophone
AccessDenied.MicrophoneRestricted AccessDenied.Camera AccessDenied.CameraRestricted
AccessDenied.PhotosAndVideos AccessDenied.SaveMedia AccessDenied.PhotosRestricted
AccessDenied.LocationDenied AccessDenied.LocationDisabled AccessDenied.LocationTracking
AccessDenied.CallMicrophone AccessDenied.VideoMessageCamera AccessDenied.VideoMessageMicrophone
AccessDenied.LocationAlwaysDenied AccessDenied.Wallpapers AccessDenied.VideoCallCamera
AccessDenied.QrCode AccessDenied.QrCamera AccessDenied.LocationPreciseDenied
AccessDenied.LocationWeather AccessDenied.AgeVerificationCamera
InfoPlist.NSContactsUsageDescription InfoPlist.NSLocationWhenInUseUsageDescription
InfoPlist.NSLocationAlwaysAndWhenInUseUsageDescription InfoPlist.NSLocationAlwaysUsageDescription
PasscodeSettings.EncryptDataHelp EnterPasscode.EnterTitle EnterPasscode.EnterPasscode
EnterPasscode.TouchId DialogList.PasscodeLockHelp Passcode.AppLockedAlert
Cache.Indexing ClearCache.StorageCache ClearCache.StorageServiceFiles ClearCache.ClearCache
StorageManagement.DescriptionChatUsage StorageManagement.DescriptionAppUsage
Watch.AppName Watch.Location.Access Watch.Microphone.Access Watch.AuthRequired
Widget.AuthRequired Widget.GalleryTitle Application.Name
Update.Title Update.AppVersion Update.UpdateApp
Share.AuthTitle Share.AuthDescription ShareFileTip.Text Conversation.FileHowToText
AppUpgrade.Running Media.LimitedAccessText
Attachment.LimitedMediaAccessText Attachment.CameraAccessText
ChatImportActivity.OpenApp Intents.ErrorLockedText Story.Camera.AccessPlaceholderTitle
PowerSavingScreen.OptionAutoplayEffectsText Map.HomeAndWorkInfo
Permissions.CellularDataText.v0 Notifications.PermissionsSuppressWarningText
Calls.RatingTitle Call.StatusIncoming Call.StatusOngoing Call.PhoneCallInProgressMessage
UserInfo.TelegramCall UserInfo.TelegramVideoCall
Chat.Context.Phone.TelegramVoiceCall Chat.Context.Phone.TelegramVideoCall
Privacy.Calls.IntegrationHelp
WebBrowser.Telegram WebBrowser.OpenLinksInfo WebBrowser.ClearCookies.Info
Login.ErrorAppOutdated Story.UnsupportedText Story.UnsupportedAction
Conversation.UnsupportedMedia Conversation.UnsupportedMediaPlaceholder Conversation.UpdateTelegram
Passport.UpdateRequiredError Gift.Transfer.UpdateRequired.Text
Notifications.TelegramTones Notifications.UploadSuccess.Text
""".split()
KEYS = set(KEYS)

path = "Telegram/Telegram-iOS/en.lproj/Localizable.strings"
lines = io.open(path, encoding='utf-8').read().split("\n")
line_re = re.compile(r'^("([^"]+)"\s*=\s*")(.*)(";)\s*$')

changed, seen = [], set()
for i, ln in enumerate(lines):
    m = line_re.match(ln)
    if not m:
        continue
    key, value = m.group(2), m.group(3)
    if key not in KEYS or "Telegram" not in value:
        continue
    seen.add(key)
    # capital-T only: telegram.org / t.me URLs are lowercase and stay intact
    new_value = value.replace("TELEGRAM", "AYUGRAM").replace("Telegram", "AyuGram")
    lines[i] = m.group(1) + new_value + m.group(4)
    changed.append((key, value, new_value))

io.open(path, 'w', encoding='utf-8').write("\n".join(lines))
print(f"lines rewritten: {len(changed)}   distinct keys hit: {len(seen)} / {len(KEYS)} listed")
missing = sorted(KEYS - seen)
if missing:
    print("\nlisted but NOT found (check for typos / already clean):")
    for k in missing:
        print("   ", k)
