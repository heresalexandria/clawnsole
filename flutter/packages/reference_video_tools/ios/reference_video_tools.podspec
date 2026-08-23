Pod::Spec.new do |s|
  s.name             = 'reference_video_tools'
  s.version          = '0.1.0'
  s.summary          = 'Clawnsole reference-video compatibility tools.'
  s.homepage         = 'https://github.com/heresalexandria/clawnsole'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Alexandria' => '70348962+heresalexandria@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency       'Flutter'
  s.frameworks       = 'CoreGraphics', 'ImageIO'
  s.platform         = :ios, '15.0'
  s.requires_arc     = true
  s.static_framework = true
  s.prepare_command  = <<-CMD
    if [ ! -d "Frameworks/ffmpegkit.xcframework" ]; then
      chmod +x prepare_frameworks.sh
      ./prepare_frameworks.sh
    fi
  CMD
  s.ios.vendored_frameworks = 'Frameworks/ffmpegkit.xcframework',
                              'Frameworks/libavcodec.xcframework',
                              'Frameworks/libavdevice.xcframework',
                              'Frameworks/libavfilter.xcframework',
                              'Frameworks/libavformat.xcframework',
                              'Frameworks/libavutil.xcframework',
                              'Frameworks/libswresample.xcframework',
                              'Frameworks/libswscale.xcframework'
end
