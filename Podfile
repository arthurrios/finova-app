platform :ios, '15.0'

target 'FinanceApp' do
  use_frameworks!

  # Core Dependencies
  pod 'Firebase/Auth'
  pod 'Firebase/Firestore'

  pod 'GoogleSignIn'

  pod 'ShimmerView'
  pod 'SQLite.swift'

  target 'FinanceAppTests' do
    inherit! :search_paths
    # Pods for testing
  end
end

# SwiftLint integration
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
  
  # Fix duplicate UUID issue
  installer.pods_project.root_object.attributes['TargetAttributes'] = {}
end
