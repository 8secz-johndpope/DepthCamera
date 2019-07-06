Pod::Spec.new do |s|
  s.name             = 'DepthCamera'
  s.version          = '0.1.0'
  s.summary          = 'Basic DepthCamera to obtain and render Depth Imagery'
 
  s.description      = <<-DESC
Camera that displays Depth Imagery for the user. Can choose between original image and the blended image with the mask from the depth image. Basic usage - only photos currently. Plan on adding Video Usage that is depth based as well as normal imagery.
                       DESC
 
  s.homepage         = 'https://github.com/Evilsmaher/DepthCamera'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Evilsmaher' => 'bsf70344@gmail.com' }
  s.source           = { :git => 'https://github.com/Evilsmaher/DepthCamera.git', :tag => s.version.to_s }
 
  s.ios.deployment_target = '10.0'
  s.source_files = 'DepthCamera/*'
 
end