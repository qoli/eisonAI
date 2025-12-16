xcodebuild \
  -workspace /Volumes/Data/Github/eisonAI/eisonAI.xcodeproj/project.xcworkspace \
  -scheme iOS \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build

APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/eisonAI-* | head -n1)/Build/Products/Debug-iphoneos/eisonAI.app
open "$APP"